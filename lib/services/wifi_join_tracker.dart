import 'dart:math';

/// One AP in a Wi-Fi scan.
class WifiAp {
  final String ssid, bssid;
  final int rssi, freq;
  final DateTime? heard; // when its beacon / probe response was received
  final bool passpoint;
  final String? operator; // Passpoint operator friendly name
  WifiAp(this.ssid, this.bssid, this.rssi, this.freq, this.heard, this.passpoint, this.operator);

  static WifiAp fromMap(Map m) => WifiAp(
        (m['ssid'] ?? '').toString(),
        (m['bssid'] ?? '').toString(),
        (m['rssi'] as num?)?.toInt() ?? -127,
        (m['freq'] as num?)?.toInt() ?? 0,
        m['heard'] == null ? null : DateTime.fromMillisecondsSinceEpoch((m['heard'] as num).toInt()),
        m['passpoint'] == true,
        m['operator']?.toString(),
      );

  int get channel => wifiChannel(freq);
  String get band => wifiBand(freq);
}

int wifiChannel(int f) {
  if (f == 2484) return 14;
  if (f >= 2412 && f < 2484) return (f - 2407) ~/ 5;
  if (f >= 5955 && f <= 7115) return (f - 5950) ~/ 5;
  if (f >= 5000 && f < 5900) return (f - 5000) ~/ 5;
  return 0;
}

String wifiBand(int f) {
  if (f >= 2400 && f < 2500) return '2.4 GHz';
  if (f >= 4900 && f < 5900) return '5 GHz';
  if (f >= 5925 && f < 7125) return '6 GHz';
  return f > 0 ? '$f MHz' : '';
}

/// A Wi-Fi scan in which at least one Spectrum SSID was heard.
class SpectrumScan {
  final DateTime time;
  final int scanNo;
  final bool updated; // false = Android returned cached results (scan throttled / failed)
  final bool requestedByApp;
  final int apsTotal;
  final List<WifiAp> spectrum; // strongest first
  final String? connectedSsid, connectedBssid;
  final SpectrumVisit? visit;
  SpectrumScan(this.time, this.scanNo, this.updated, this.requestedByApp, this.apsTotal, this.spectrum,
      this.connectedSsid, this.connectedBssid, this.visit);
}

/// A connection step reported by Android (any SSID).
class WifiStateEvent {
  final DateTime time;
  final String source; // network, supplicant, net
  final String state;
  final String? error, ssid, bssid;
  final int? rssi, freq;
  final bool spectrum;
  final SpectrumVisit? visit;
  WifiStateEvent(this.time, this.source, this.state, this.error, this.ssid, this.bssid, this.rssi, this.freq,
      this.spectrum, this.visit);
}

/// From the first time the phone hears a Spectrum SSID, through joining it,
/// to leaving it (or losing sight of it without joining).
class SpectrumVisit {
  final int id;
  final String firstSsid;
  final DateTime firstHeard; // earliest beacon / probe response in the first scan that had it
  final DateTime? firstScan; // when that scan was delivered (null = joined without a scan seen)
  final String? firstBssid;
  final int? firstRssi, firstFreq;
  final bool passpoint;
  final bool atStart; // already connected when the app started
  int scansBeforeConnect = 0;
  int? bestRssi;
  DateTime lastSeen;
  int missedScans = 0;

  DateTime? assocStart, authStart, ipStart, associated, connected, ipAvailable, validated;
  int attempts = 0, failures = 0;
  String? lastFailure;
  String? connSsid, connBssid;
  int? connRssi, connFreq;
  final bssids = <String>{};
  int roams = 0;

  DateTime? disconnected;
  double activeSeconds = 0;
  int rxBytes = 0, txBytes = 0;
  String? endReason;

  // Context captured by the app when the visit opens / connects.
  List<Object?> contextAtHeard = const [];
  List<Object?> contextAtConnect = const [];

  SpectrumVisit(this.id, this.firstSsid, this.firstHeard, this.firstScan, this.firstBssid, this.firstRssi,
      this.firstFreq, this.passpoint, {this.atStart = false})
      : lastSeen = firstHeard,
        bestRssi = firstRssi;

  bool get isConnected => connected != null && disconnected == null;
  bool get connecting => connected == null && assocStart != null;

  double? _s(DateTime? a, DateTime? b) => a == null || b == null ? null : b.difference(a).inMilliseconds / 1000;

  /// First heard -> connected (IP up). Not for visits already connected at start.
  double? get timeToConnect => atStart ? null : _s(firstHeard, connected);
  double? get heardToAssoc => atStart ? null : _s(firstHeard, assocStart);
  /// Association + authentication (802.11 join, EAP / 4-way handshake), to the IP request.
  double? get assocAuth => _s(assocStart, ipStart ?? associated ?? connected);
  double? get ipTime => _s(ipStart, connected);
  double? get toValidated => _s(connected, validated);
  double? connectedSeconds(DateTime now) => connected == null ? null : _s(connected, disconnected ?? now);

  String get state => disconnected != null
      ? 'Left'
      : connected != null
          ? 'Connected'
          : assocStart != null
              ? 'Connecting'
              : 'Seen';
}

/// Tracks Spectrum Mobile Wi-Fi (SSIDs matching [patterns], or Passpoint
/// operator "Spectrum") from the phone's Wi-Fi scans and connection steps.
class WifiJoinTracker {
  List<String> patterns;
  WifiJoinTracker(this.patterns);

  /// Bytes per second on Wi-Fi above which a second counts as "sending traffic".
  static const activeBytesPerSecond = 2000;

  SpectrumVisit? visit; // open visit
  final sessionVisits = <SpectrumVisit>[]; // closed during this session
  DateTime? _sessionStart;
  int scansTotal = 0, scansWithSpectrum = 0, sessionScans = 0, sessionScansWithSpectrum = 0;
  int _nextId = 1;
  DateTime? lastScanRequest;
  int? _lastRx, _lastTx;
  DateTime? _lastBytesAt;
  String? _connSsid, _connBssid; // current Wi-Fi network (any SSID)
  bool _connUp = false;

  void startSession(DateTime t) {
    _sessionStart = t;
    sessionVisits.clear();
    sessionScans = 0;
    sessionScansWithSpectrum = 0;
  }

  bool isSpectrum(String? ssid, [String? operator]) {
    if (ssid == null || ssid.isEmpty) return operator?.toLowerCase().contains('spectrum') == true;
    final s = ssid.toLowerCase();
    return patterns.any((p) => p.isNotEmpty && s.contains(p)) || operator?.toLowerCase().contains('spectrum') == true;
  }

  static List<String> parsePatterns(String text) =>
      text.split(RegExp(r'[,;\n]')).map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toList();

  /// Feeds the events collected from Android since the last call.
  /// [onScan], [onState] and [onClosed] receive what should be logged.
  void update(
    Map<String, dynamic> raw, {
    required DateTime now,
    String? radioSsid,
    bool radioOnWifi = false,
    required SpectrumVisit Function(SpectrumVisit) onOpen,
    required void Function(SpectrumScan) onScan,
    required void Function(WifiStateEvent) onState,
    required void Function(SpectrumVisit) onConnected,
    required void Function(SpectrumVisit) onClosed,
  }) {
    final events = ((raw['events'] as List?) ?? const []).cast<Map>().toList()
      ..sort((a, b) => ((a['t'] as num?) ?? 0).compareTo((b['t'] as num?) ?? 0));

    // Already on Spectrum Wi-Fi when the app started (no join seen).
    if (visit == null && events.isEmpty && radioOnWifi && isSpectrum(radioSsid) && _connSsid == null) {
      final v = onOpen(SpectrumVisit(_nextId++, radioSsid!, now, null, null, null, null, false, atStart: true));
      v.connected = now;
      v.connSsid = radioSsid;
      visit = v;
      _connSsid = radioSsid;
      _connUp = true;
      onConnected(v);
    }

    for (final e in events) {
      final t = DateTime.fromMillisecondsSinceEpoch(((e['t'] as num?) ?? now.millisecondsSinceEpoch).toInt());
      if (e['kind'] == 'scan') {
        _scan(e, t, onOpen, onScan, onClosed);
      } else {
        _state(e, t, onOpen, onState, onConnected, onClosed);
      }
    }

    // Wi-Fi bytes since the last call: counted while connected to Spectrum Wi-Fi.
    final rx = (raw['wifiRxBytes'] as num?)?.toInt();
    final tx = (raw['wifiTxBytes'] as num?)?.toInt();
    if (rx != null && tx != null) {
      final v = visit;
      if (_lastRx != null && _lastBytesAt != null && v != null && v.isConnected) {
        final dRx = max(0, rx - _lastRx!), dTx = max(0, tx - _lastTx!);
        final dt = now.difference(_lastBytesAt!).inMilliseconds / 1000;
        if (dt > 0 && dt < 30) {
          v.rxBytes += dRx;
          v.txBytes += dTx;
          if ((dRx + dTx) / dt >= activeBytesPerSecond) v.activeSeconds += dt;
        }
      }
      _lastRx = rx;
      _lastTx = tx;
      _lastBytesAt = now;
    }
  }

  void _scan(Map e, DateTime t, SpectrumVisit Function(SpectrumVisit) onOpen, void Function(SpectrumScan) onScan,
      void Function(SpectrumVisit) onClosed) {
    scansTotal++;
    if (_sessionStart != null) sessionScans++;
    final aps = ((e['aps'] as List?) ?? const []).cast<Map>().map(WifiAp.fromMap).toList();
    final sp = aps.where((a) => isSpectrum(a.ssid, a.operator)).toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
    final requested = lastScanRequest != null && t.difference(lastScanRequest!).inSeconds.abs() <= 10;
    var v = visit;
    if (sp.isNotEmpty) {
      scansWithSpectrum++;
      if (_sessionStart != null) sessionScansWithSpectrum++;
      if (v == null) {
        // Earliest time any Spectrum AP in this scan was heard; cached results
        // older than 30 s are not "first heard".
        var first = t;
        WifiAp best = sp.first;
        for (final a in sp) {
          final h = a.heard;
          if (h != null && h.isBefore(first) && t.difference(h).inSeconds <= 30) {
            first = h;
            best = a;
          }
        }
        v = visit = onOpen(SpectrumVisit(_nextId++, best.ssid, first, t, best.bssid, best.rssi, best.freq, best.passpoint));
      }
      v.lastSeen = t;
      v.missedScans = 0;
      if (v.connected == null) {
        v.scansBeforeConnect++;
        if (v.bestRssi == null || sp.first.rssi > v.bestRssi!) v.bestRssi = sp.first.rssi;
      }
    } else if (v != null && v.connected == null && v.assocStart == null) {
      v.missedScans++;
      if (v.missedScans >= 2 && t.difference(v.lastSeen).inSeconds >= 30) {
        _close(v, v.lastSeen, v.failures > 0 ? 'Seen, connect failed' : 'Seen, not connected', onClosed);
        v = null;
      }
    }
    if (sp.isNotEmpty) {
      onScan(SpectrumScan(t, scansTotal, e['updated'] != false, requested, aps.length, sp, e['ssid']?.toString(),
          e['bssid']?.toString(), v));
    }
  }

  static const _connectingStates = {'CONNECTING', 'AUTHENTICATING', 'OBTAINING_IPADDR', 'ASSOCIATING', 'ASSOCIATED',
      'FOUR_WAY_HANDSHAKE', 'GROUP_HANDSHAKE'};

  static void _beginAttempt(SpectrumVisit v, DateTime t) {
    if (v.connected != null) return;
    if (v.assocStart == null) v.attempts++;
    v.assocStart ??= t;
  }

  void _state(Map e, DateTime t, SpectrumVisit Function(SpectrumVisit) onOpen, void Function(WifiStateEvent) onState,
      void Function(SpectrumVisit) onConnected, void Function(SpectrumVisit) onClosed) {
    final source = (e['kind'] ?? '').toString();
    final st = (e['state'] ?? '').toString();
    final ssid = e['ssid']?.toString();
    final bssid = e['bssid']?.toString();
    final rssi = (e['rssi'] as num?)?.toInt();
    final freq = (e['freq'] as num?)?.toInt();
    final error = e['error']?.toString();
    final sp = isSpectrum(ssid) || (ssid == null && visit != null);
    var v = visit;

    // A different (non-Spectrum) network came up: the Spectrum visit is over.
    if (v != null && v.isConnected && ssid != null && !isSpectrum(ssid) && (st == 'CONNECTED' || st == 'COMPLETED')) {
      _close(v, t, 'Moved to another Wi-Fi ($ssid)', onClosed);
      v = null;
    }

    if (sp && v == null && _connectingStates.contains(st)) {
      // Joined without a scan showing it first (e.g. Passpoint from the phone's own PNO scan).
      v = visit = onOpen(SpectrumVisit(_nextId++, ssid ?? '', t, null, bssid, rssi, freq, e['passpoint'] == true));
    }

    if (v != null && (sp || ssid == null)) {
      switch (st) {
        case 'CONNECTING':
        case 'ASSOCIATING':
          _beginAttempt(v, t);
        case 'AUTHENTICATING':
        case 'FOUR_WAY_HANDSHAKE':
          _beginAttempt(v, t);
          if (v.connected == null) v.authStart ??= t;
        case 'OBTAINING_IPADDR':
          _beginAttempt(v, t);
          if (v.connected == null) v.ipStart ??= t;
        case 'COMPLETED':
          _beginAttempt(v, t);
          if (v.connected == null) v.associated ??= t;
        case 'CONNECTED':
          if (v.connected == null) {
            v.connected = t;
            v.connSsid = ssid ?? v.firstSsid;
            v.connBssid = bssid;
            v.connRssi = rssi;
            v.connFreq = freq;
            v.assocStart ??= t;
            if (v.attempts == 0) v.attempts = 1;
            onConnected(v);
          }
        case 'IP available':
          if (v.connected != null || v.assocStart != null) v.ipAvailable ??= t;
        case 'Internet validated':
          if (v.connected != null) v.validated ??= t;
        case 'DISCONNECTED':
        case 'FAILED':
        case 'Lost':
          if (v.isConnected) {
            _close(v, t, 'Disconnected', onClosed);
            v = null;
          } else if (v.connecting && st != 'Lost') {
            _fail(v, error ?? 'Disconnected while joining');
          }
      }
      if (error != null && v != null && v.connecting) _fail(v, error);
      if (v != null && v.isConnected && bssid != null) {
        if (v.connBssid != null && bssid != v.connBssid && !v.bssids.contains(bssid)) v.roams++;
        if (v.connBssid != null && bssid != v.connBssid) v.connBssid = bssid;
        v.bssids.add(bssid);
      }
    }
    if (st == 'CONNECTED') {
      _connSsid = ssid;
      _connBssid = bssid;
      _connUp = true;
    } else if (st == 'DISCONNECTED') {
      _connUp = false;
    }
    onState(WifiStateEvent(t, source, st, error, ssid, bssid, rssi, freq, isSpectrum(ssid), v));
  }

  /// A join attempt that ended without a connection; the next attempt starts fresh.
  static void _fail(SpectrumVisit v, String why) {
    v.failures++;
    v.lastFailure = why;
    v.assocStart = null;
    v.authStart = null;
    v.ipStart = null;
    v.associated = null;
  }

  void _close(SpectrumVisit v, DateTime t, String reason, void Function(SpectrumVisit) onClosed) {
    if (v.connected != null) v.disconnected ??= t;
    v.endReason = reason;
    if (_sessionStart != null) sessionVisits.add(v);
    if (identical(visit, v)) visit = null;
    onClosed(v);
  }

  bool get connectedToWifi => _connUp;
  String? get wifiSsid => _connSsid;
  String? get wifiBssid => _connBssid;

  /// Visits for this session's summary: closed ones plus the open one.
  List<SpectrumVisit> visitsForSummary() => [...sessionVisits, if (visit != null) visit!];

  /// One line for the Test screen.
  String status(DateTime now) {
    final v = visit;
    String d(double? s) => s == null ? '-' : (s >= 60 ? '${s ~/ 60}m ${(s % 60).round()}s' : '${s.toStringAsFixed(1)} s');
    if (v == null) {
      final last = sessionVisits.isEmpty ? null : sessionVisits.last;
      return last == null ? 'not heard ($scansWithSpectrum of $scansTotal scans)' : 'left ${last.connSsid ?? last.firstSsid} (${last.endReason})';
    }
    if (v.connected == null) {
      return '${v.firstSsid} heard ${d(now.difference(v.firstHeard).inMilliseconds / 1000)} ago, best ${v.bestRssi ?? '-'} dBm, '
          '${v.connecting ? 'joining' : 'not joined'}${v.failures > 0 ? ', ${v.failures} failed' : ''}';
    }
    final mb = (v.rxBytes + v.txBytes) / 1e6;
    return '${v.connSsid}: ${v.atStart ? 'connected at start' : 'joined in ${d(v.timeToConnect)}'}, '
        'on it ${d(v.connectedSeconds(now))}, active ${d(v.activeSeconds)}, ${mb.toStringAsFixed(1)} MB';
  }

  // ------------------------------------------------------------------ summary

  static const summaryHeader = ['Metric', 'Value', 'Mean', 'Median', 'Min', 'Max', 'Std Dev'];

  List<List<Object?>> summary(DateTime end) {
    final vs = visitsForSummary();
    String f(double? x) => x == null ? '' : x.toStringAsFixed(3);
    List<Object?> stats(String name, Iterable<double?> xs) {
      final l = xs.whereType<double>().toList()..sort();
      if (l.isEmpty) return [name, 0, '', '', '', '', ''];
      final mean = l.reduce((a, b) => a + b) / l.length;
      final med = l.length.isOdd ? l[l.length ~/ 2] : (l[l.length ~/ 2 - 1] + l[l.length ~/ 2]) / 2;
      final sd = l.length < 2 ? 0.0 : sqrt(l.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / (l.length - 1));
      return [name, l.length, f(mean), f(med), f(l.first), f(l.last), f(sd)];
    }

    final joined = vs.where((v) => v.connected != null && !v.atStart).toList();
    final conn = vs.where((v) => v.connected != null).toList();
    final connTime = conn.fold<double>(0, (a, v) => a + (v.connectedSeconds(end) ?? 0));
    final active = conn.fold<double>(0, (a, v) => a + v.activeSeconds);
    final rx = conn.fold<int>(0, (a, v) => a + v.rxBytes), tx = conn.fold<int>(0, (a, v) => a + v.txBytes);
    return [
      ['Wi-Fi scans (this session)', sessionScans],
      ['Scans with a Spectrum SSID', sessionScansWithSpectrum],
      ['Visits (Spectrum SSID heard or joined)', vs.length],
      ['Joined', joined.length],
      ['Already connected at start', vs.where((v) => v.atStart).length],
      ['Heard, not joined', vs.where((v) => v.connected == null).length],
      ['Failed join attempts', vs.fold<int>(0, (a, v) => a + v.failures)],
      [],
      ['Timing (s)', 'Count', 'Mean', 'Median', 'Min', 'Max', 'Std Dev'],
      stats('Time to connect (first heard -> connected)', joined.map((v) => v.timeToConnect)),
      stats('First heard -> join started', joined.map((v) => v.heardToAssoc)),
      stats('Association + authentication', joined.map((v) => v.assocAuth)),
      stats('IP address (DHCP)', joined.map((v) => v.ipTime)),
      stats('Connected -> internet validated', joined.map((v) => v.toValidated)),
      stats('Scans before connect (count)', joined.map((v) => v.scansBeforeConnect.toDouble())),
      stats('Time connected per visit', conn.map((v) => v.connectedSeconds(end))),
      stats('Time sending traffic per visit', conn.map((v) => v.activeSeconds)),
      [],
      ['Totals', 'Value'],
      ['Time connected to Spectrum Wi-Fi (s)', connTime.toStringAsFixed(1)],
      ['Time sending traffic over it (s)', active.toStringAsFixed(1)],
      ['Share of connected time with traffic (%)', connTime == 0 ? '' : (100 * active / connTime).toStringAsFixed(1)],
      ['Data down (MB)', (rx / 1e6).toStringAsFixed(2)],
      ['Data up (MB)', (tx / 1e6).toStringAsFixed(2)],
      ['Average Mbps while sending', active == 0 ? '' : ((rx + tx) * 8 / 1e6 / active).toStringAsFixed(2)],
      [],
      ['Notes', 'Times come from Android scan results (when each AP\'s beacon / probe response was heard) and Wi-Fi '
          'connection broadcasts, so they are app-level: a few hundred ms coarser than a sniffer or wpa_supplicant log. '
          'Probe requests sent by the phone are not visible to apps. Traffic = seconds with over '
          '$activeBytesPerSecond bytes/s on Wi-Fi.'],
    ];
  }
}
