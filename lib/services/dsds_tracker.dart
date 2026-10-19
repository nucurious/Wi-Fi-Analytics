/// Dual SIM (DSDS) mobile-data transitions, detected from the data SIM and the
/// cellular IP addresses (Android). Fed every second with RadioInfo.dataState().
///
/// Events:
///   SIM switch       data moved to the other SIM (new IP on the new SIM)
///   IP change        same SIM, new IP address (new PDN / re-attach)
///   Data interrupted cellular IP disappeared and came back unchanged
///   Data lost        no cellular IP for [lostAfter] (logged once; the next
///                    SIM switch / IP change still closes the gap)
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
}

class DsdsEvent {
  final DateTime time; // when the new data path was up (or loss confirmed)
  final String event;
  final DsdsState from, to;
  final DateTime started; // when the old data path ended
  final double gapSeconds; // no cellular IP between the two
  final double? onPreviousSeconds; // time on the previous SIM / IP
  DsdsEvent(this.time, this.event, this.from, this.to, this.started, this.onPreviousSeconds)
      : gapSeconds = time.difference(started).inMilliseconds / 1000;

  String get summary => event == 'SIM switch'
      ? 'SIM${from.slot} -> SIM${to.slot} (${to.carrier}), gap ${gapSeconds.toStringAsFixed(0)} s'
      : '$event on SIM${to.slot ?? from.slot}, gap ${gapSeconds.toStringAsFixed(0)} s';

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

class DsdsTracker {
  static const lostAfter = Duration(seconds: 30);

  DsdsState? current; // last snapshot seen
  DsdsState? _stable; // last state that had an IP
  DateTime? _stableSince; // when that SIM/IP started
  DateTime? _lostAt; // when the IP disappeared
  bool _lostLogged = false;

  /// Events in the running session (for the summary).
  final sessionEvents = <DsdsEvent>[];
  final _onSlot = <int, double>{}; // seconds with data per SIM slot this session
  DateTime? _sessionStart;

  void startSession(DateTime t) {
    sessionEvents.clear();
    _onSlot.clear();
    _sessionStart = t;
    if (_stable != null && _lostAt == null) _stableSince = t;
  }

  List<DsdsEvent> update(Map<String, dynamic> raw, {DateTime? at}) {
    final now = at ?? DateTime.now();
    final s = DsdsState(raw, now);
    current = s;
    if (!s.known) return const [];
    final out = <DsdsEvent>[];
    final prev = _stable;

    if (!s.hasIp) {
      if (prev != null && _lostAt == null) {
        _lostAt = now;
        _lostLogged = false;
      }
      if (prev != null && _lostAt != null && !_lostLogged && now.difference(_lostAt!) >= lostAfter) {
        _lostLogged = true;
        out.add(DsdsEvent(now, 'Data lost', prev, s, _lostAt!, _secs(_stableSince, _lostAt!)));
      }
      return _record(out);
    }

    if (prev == null) {
      _stable = s;
      _stableSince = now;
      return const [];
    }
    final simChanged = s.slot != null && prev.slot != null && s.slot != prev.slot;
    final ipChanged = s.ips != prev.ips;
    final started = _lostAt ?? now;
    if (simChanged || ipChanged) {
      out.add(DsdsEvent(now, simChanged ? 'SIM switch' : 'IP change', prev, s, started, _secs(_stableSince, started)));
      _addTime(prev.slot, _stableSince, started);
      _stable = s;
      _stableSince = now;
    } else if (_lostAt != null) {
      out.add(DsdsEvent(now, 'Data interrupted', prev, s, started, _secs(_stableSince, started)));
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

  void _addTime(int? slot, DateTime? from, DateTime to) {
    if (slot == null || from == null || _sessionStart == null) return;
    final start = from.isBefore(_sessionStart!) ? _sessionStart! : from;
    _onSlot[slot] = (_onSlot[slot] ?? 0) + to.difference(start).inMilliseconds / 1000;
  }

  /// Session statistics as (metric, value) rows, for the "DSDS summary" sheet.
  List<List<Object?>> summary(DateTime end) {
    final onSlot = Map.of(_onSlot);
    final st = _stable;
    if (st?.slot != null && _stableSince != null && _lostAt == null && _sessionStart != null) {
      final from = _stableSince!.isBefore(_sessionStart!) ? _sessionStart! : _stableSince!;
      onSlot[st!.slot!] = (onSlot[st.slot!] ?? 0) + end.difference(from).inMilliseconds / 1000;
    }
    String f(double v) => v.toStringAsFixed(1);
    List<double> gaps(Iterable<DsdsEvent> e) => e.map((x) => x.gapSeconds).toList()..sort();
    double med(List<double> v) => v.isEmpty ? 0 : (v.length.isOdd ? v[v.length ~/ 2] : (v[v.length ~/ 2 - 1] + v[v.length ~/ 2]) / 2);
    final rows = <List<Object?>>[];
    final byType = <String, List<DsdsEvent>>{};
    for (final e in sessionEvents) {
      byType.putIfAbsent(e.event, () => []).add(e);
    }
    rows.add(['Session length (s)', _sessionStart == null ? '' : f(end.difference(_sessionStart!).inMilliseconds / 1000), '', '', '']);
    for (final slot in onSlot.keys.toList()..sort()) {
      rows.add(['Time with data on SIM$slot (s)', f(onSlot[slot]!), '', '', '']);
    }
    // Per direction for SIM switches.
    final dirs = <String, List<DsdsEvent>>{};
    for (final e in byType['SIM switch'] ?? const <DsdsEvent>[]) {
      dirs.putIfAbsent('SIM${e.from.slot} ${e.from.carrier} -> SIM${e.to.slot} ${e.to.carrier}', () => []).add(e);
    }
    for (final d in dirs.entries) {
      final g = gaps(d.value);
      rows.add(['SIM switch ${d.key}', d.value.length,
          f(g.reduce((a, b) => a + b) / g.length), f(med(g)), f(g.last)]);
    }
    for (final t in ['IP change', 'Data interrupted', 'Data lost']) {
      final e = byType[t] ?? const <DsdsEvent>[];
      if (e.isEmpty) {
        rows.add([t, 0, '', '', '']);
        continue;
      }
      final g = gaps(e);
      rows.add([t, e.length, f(g.reduce((a, b) => a + b) / g.length), f(med(g)), f(g.last)]);
    }
    return rows;
  }

  static const summaryHeader = ['metric', 'count_or_value', 'gap_avg_s', 'gap_median_s', 'gap_max_s'];
}
