import 'dart:math';

/// Dual SIM (DSDS) mobile-data transitions, detected from the data SIM and the
/// cellular IP addresses (Android). Fed 4 times a second with RadioInfo.dataState().
///
/// A change of data SIM is a switch attempt. It succeeds when the new SIM's
/// own network has an IP (switch time = from the old data path ending, or the
/// SIM change if earlier, to the new IP); it fails if the phone goes back to
/// the old SIM first, or no IP comes within [switchTimeout].
///
/// Direction: Hand In = onto the Spectrum HMNO subscription (PLMN 314020 or an
/// HMNO IP); Hand Out = off it; Other = neither SIM is HMNO.
///
/// Events: SIM switch, SIM switch failed, IP change (same SIM, new address),
/// Data interrupted (IP gone and back unchanged), Data lost (no IP for 30 s).
class DsdsState {
  final int? slot;
  final int? _dataSub, _netSub;
  final String carrier, plmn, iface, ipv4, ipv6, sims;
  final DateTime time;
  DsdsState(Map<String, dynamic> m, this.time)
      : slot = (m['dataSimSlot'] as num?)?.toInt(),
        _dataSub = (m['dataSubId'] as num?)?.toInt(),
        _netSub = (m['cellNetSubId'] as num?)?.toInt(),
        carrier = (m['dataCarrier'] ?? '').toString(),
        plmn = (m['dataPlmn'] ?? '').toString(),
        iface = (m['cellIface'] ?? '').toString(),
        ipv4 = (m['cellIpv4'] ?? '').toString(),
        ipv6 = (m['cellIpv6'] ?? '').toString(),
        sims = (m['sims'] ?? '').toString();

  /// An IP on the data SIM's own network (during a switch the old SIM's
  /// network can still be up for a moment; that doesn't count).
  bool get hasIp =>
      (ipv4.isNotEmpty || ipv6.isNotEmpty) && (_dataSub == null || _netSub == null || _dataSub == _netSub);
  String get ips => '$ipv4|$ipv6';
  bool get known => slot != null || hasIp;
  String get label => slot == null ? 'no data SIM' : 'SIM$slot $carrier';
  bool get isHmno => plmn == '314020' || DsdsEvent.owner(ipv4, ipv6).startsWith('Spectrum HMNO');
}

class DsdsEvent {
  final DateTime time;
  final String event;
  final DsdsState from, to;
  final DateTime started; // when the old data path ended (or the SIM changed)
  final double? gapSeconds; // switch / outage time; null for a failed switch
  final double? onPreviousSeconds; // time on the previous SIM / address
  final String direction; // Hand In, Hand Out, Other ('' for non-switch events)
  final bool? success; // switches only
  DsdsEvent(this.time, this.event, this.from, this.to, this.started, this.onPreviousSeconds,
      {this.direction = '', this.success, bool hasGap = true})
      : gapSeconds = hasGap ? time.difference(started).inMilliseconds / 1000 : null;

  String get summary {
    final g = gapSeconds == null ? '' : ', ${gapSeconds!.toStringAsFixed(1)} s';
    return switch (event) {
      'SIM switch' => '$direction SIM${from.slot} -> SIM${to.slot}$g',
      'SIM switch failed' => '$direction failed SIM${from.slot} -> SIM${to.slot}',
      _ => '$event on SIM${to.slot ?? from.slot}$g',
    };
  }

  static String directionOf(DsdsState from, DsdsState to) =>
      to.isHmno && !from.isHmno ? 'Hand In' : (from.isHmno && !to.isHmno ? 'Hand Out' : 'Other');

  /// Who owns an IP address, from the registry-checked ranges used by the
  /// PC analyzer (v5.14).
  static String owner(String ipv4, String ipv6) {
    final v6 = ipv6.split(',').first.toLowerCase();
    final v4 = ipv4.split(',').first;
    if (v6.startsWith('2603:90f4')) return 'Spectrum HMNO (CBRS)';
    if (v6.startsWith('2600:100c')) return 'Spectrum Mobile on Verizon';
    if (RegExp(r'^2600:10(0[0-9a-f]|1[0-7]):').hasMatch(v6)) return 'Verizon Wireless';
    if (v6.startsWith('2607:fb90')) return 'T-Mobile';
    if (v6.startsWith('2600:3')) return 'AT&T Mobility';
    if (v4.startsWith('10.14.')) return 'Spectrum HMNO (CBRS)';
    if (v4.startsWith('100.124.')) return 'Spectrum Mobile on Verizon';
    final o = v4.split('.').map(int.tryParse).toList();
    if (o.length == 4 && o.every((x) => x != null)) {
      final a = o[0]!, b = o[1]!;
      if ((a == 97 && b >= 128) || (a == 174 && b >= 192) || (a == 70 && b >= 192 && b < 224)) return 'Verizon Wireless';
      if (a == 100 && b >= 64 && b < 128) return 'Carrier NAT (100.64/10)';
      if (a == 10) return 'Private (10/8)';
    }
    return (ipv4.isEmpty && ipv6.isEmpty) ? '' : 'Other';
  }
}

class _Attempt {
  final DsdsState from;
  DsdsState to; // latest state on the target SIM (PLMN known before the IP)
  final DateTime start;
  _Attempt(this.from, this.to, this.start);
}

class DsdsTracker {
  static const lostAfter = Duration(seconds: 30);
  static const switchTimeout = Duration(seconds: 60);

  DsdsState? current; // last snapshot seen
  DsdsState? _stable; // last state that had an IP
  DateTime? _stableSince; // when that SIM/IP started
  DateTime? _lostAt; // when the IP disappeared
  bool _lostLogged = false;
  bool _lostOnWifi = false;
  _Attempt? _attempt;
  int? _timedOutSlot; // a switch to this SIM already counted as failed (no IP in time)

  /// Events in the running session (for the summary).
  final sessionEvents = <DsdsEvent>[];
  DateTime? _sessionStart;

  void startSession(DateTime t) {
    sessionEvents.clear();
    _sessionStart = t;
  }

  /// [onWifi]: the phone's default network is Wi-Fi. Android often drops the
  /// mobile data connection then; that is not a data outage, so it is not
  /// logged as Data lost / Data interrupted.
  List<DsdsEvent> update(Map<String, dynamic> raw, {DateTime? at, bool onWifi = false}) {
    final now = at ?? DateTime.now();
    final s = DsdsState(raw, now);
    current = s;
    if (!s.known) return const [];
    final out = <DsdsEvent>[];
    final prev = _stable;

    DsdsEvent failed(_Attempt a) => DsdsEvent(now, 'SIM switch failed', a.from, a.to, a.start,
        _secs(_stableSince, a.start), direction: DsdsEvent.directionOf(a.from, a.to), success: false, hasGap: false);

    // A different data SIM than the one that last had an IP: a switch attempt.
    if (prev != null && prev.slot != null && s.slot != null) {
      final a = _attempt;
      if (a != null && s.slot != a.to.slot) {
        out.add(failed(a)); // went back (or on to a third SIM) before an IP came
        _attempt = null;
      }
      if (s.slot == prev.slot) _timedOutSlot = null;
      if (_attempt == null && s.slot != prev.slot && s.slot != _timedOutSlot) {
        _attempt = _Attempt(prev, s, _lostAt ?? now);
      } else if (_attempt != null) {
        _attempt!.to = s;
      }
    }

    if (!s.hasIp) {
      if (prev != null && _lostAt == null) {
        _lostAt = now;
        _lostLogged = false;
        _lostOnWifi = onWifi;
      }
      if (onWifi) _lostOnWifi = true;
      final a = _attempt;
      if (a != null && now.difference(a.start) >= switchTimeout) {
        out.add(failed(a));
        _attempt = null;
        _timedOutSlot = a.to.slot;
      } else if (a == null && prev != null && _lostAt != null && !_lostLogged && !_lostOnWifi &&
          now.difference(_lostAt!) >= lostAfter) {
        _lostLogged = true;
        out.add(DsdsEvent(now, 'Data lost', prev, s, _lostAt!, _secs(_stableSince, _lostAt!)));
      }
      return _record(out);
    }

    if (prev == null) {
      _stable = s;
      _stableSince = now;
      return _record(out);
    }
    final a = _attempt;
    if (a != null && s.slot == a.to.slot) {
      out.add(DsdsEvent(now, 'SIM switch', a.from, s, a.start, _secs(_stableSince, a.start),
          direction: DsdsEvent.directionOf(a.from, s), success: true));
      _attempt = null;
      _stable = s;
      _stableSince = now;
    } else if (s.slot != null && prev.slot != null && s.slot != prev.slot) {
      // IP on the new SIM after the switch had already timed out.
      final started = _lostAt ?? now;
      out.add(DsdsEvent(now, 'SIM switch (late)', prev, s, started, _secs(_stableSince, started),
          direction: DsdsEvent.directionOf(prev, s), success: false));
      _timedOutSlot = null;
      _stable = s;
      _stableSince = now;
    } else if (s.ips != prev.ips) {
      final started = _lostAt ?? now;
      out.add(DsdsEvent(now, 'IP change', prev, s, started, _secs(_stableSince, started)));
      _stable = s;
      _stableSince = now;
    } else if (_lostAt != null && !_lostOnWifi) {
      out.add(DsdsEvent(now, 'Data interrupted', prev, s, _lostAt!, _secs(_stableSince, _lostAt!)));
    }
    _lostAt = null;
    _lostLogged = false;
    return _record(out);
  }

  List<DsdsEvent> _record(List<DsdsEvent> out) {
    if (_sessionStart != null) sessionEvents.addAll(out);
    return out;
  }

  static double? _secs(DateTime? a, DateTime b) => a == null ? null : b.difference(a).inMilliseconds / 1000;

  /// "Transition Performance" table for this session: rows Switch Count,
  /// Successful switches, Mean, Median, Min, Max, Std Dev (seconds); columns
  /// Hand In, Hand Out (and Other if any), then the other event counts.
  List<List<Object?>> summary(DateTime end) {
    final dirs = ['Hand In', 'Hand Out', if (sessionEvents.any((e) => e.direction == 'Other')) 'Other'];
    final rows = <List<Object?>>[];
    String f(double v) => v.toStringAsFixed(3);
    final attempts = {
      for (final d in dirs)
        d: sessionEvents.where((e) => e.direction == d && (e.event == 'SIM switch' || e.event == 'SIM switch failed')).toList()
    };
    final times = {
      for (final d in dirs)
        d: (attempts[d]!.where((e) => e.success == true).map((e) => e.gapSeconds!).toList()..sort())
    };
    double med(List<double> v) => v.length.isOdd ? v[v.length ~/ 2] : (v[v.length ~/ 2 - 1] + v[v.length ~/ 2]) / 2;
    double sd(List<double> v) {
      if (v.length < 2) return 0;
      final m = v.reduce((a, b) => a + b) / v.length;
      return sqrt(v.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / (v.length - 1));
    }

    rows.add(['Switch Count', for (final d in dirs) attempts[d]!.length]);
    rows.add(['Successful switches', for (final d in dirs) times[d]!.length]);
    rows.add(['Mean (s)', for (final d in dirs) times[d]!.isEmpty ? '' : f(times[d]!.reduce((a, b) => a + b) / times[d]!.length)]);
    rows.add(['Median (s)', for (final d in dirs) times[d]!.isEmpty ? '' : f(med(times[d]!))]);
    rows.add(['Min (s)', for (final d in dirs) times[d]!.isEmpty ? '' : f(times[d]!.first)]);
    rows.add(['Max (s)', for (final d in dirs) times[d]!.isEmpty ? '' : f(times[d]!.last)]);
    rows.add(['Std Dev (s)', for (final d in dirs) times[d]!.length < 2 ? '' : f(sd(times[d]!))]);
    rows.add([]);
    for (final t in ['IP change', 'Data interrupted', 'Data lost']) {
      rows.add(['$t (count)', sessionEvents.where((e) => e.event == t).length]);
    }
    if (_sessionStart != null) {
      rows.add(['Session length (s)', f(end.difference(_sessionStart!).inMilliseconds / 1000)]);
    }
    summaryHeader = ['Transition Type', ...dirs];
    return rows;
  }

  List<String> summaryHeader = const ['Transition Type', 'Hand In', 'Hand Out'];
}
