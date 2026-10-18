import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:radio_info/radio_info.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'iperf/iperf_client.dart';
import 'latency/latency_probe.dart';
import 'models.dart';
import 'services/data_store.dart';

class Settings {
  String host;
  int port;
  int tcpDuration;
  int tcpParallel;
  double udpMbps;
  int udpDuration; // 0 = continuous until stopped
  int udpParallel;
  int udpPacketBytes;
  bool keepScreenOn;
  bool logGpsTrack;

  // Latency (TWAMP-Light, or ICMP ping on Android when no reflector is set).
  bool latencyDuringTests; // run the latency probe alongside every test
  String twampHost; // blank = use ping fallback (Android)
  int twampPort;
  int latencyRateHz;
  int twampPacketBytes;
  String pingHost;
  int latencyDuration; // stand-alone latency test, 0 = until stopped

  // Long runs (overnight / weekend)
  bool repeatUntilStopped; // repeat the test, and restart after errors
  int repeatIntervalSeconds; // pause between rounds

  Settings({
    this.host = '',
    this.port = 5201,
    this.tcpDuration = 10,
    this.tcpParallel = 4,
    this.udpMbps = 10,
    this.udpDuration = 30,
    this.udpParallel = 1,
    this.udpPacketBytes = 1200,
    this.keepScreenOn = true,
    this.logGpsTrack = true,
    this.latencyDuringTests = true,
    this.twampHost = '',
    this.twampPort = 862,
    this.latencyRateHz = 10,
    this.twampPacketBytes = 64,
    this.pingHost = '1.1.1.1',
    this.latencyDuration = 60,
    this.repeatUntilStopped = false,
    this.repeatIntervalSeconds = 60,
  });

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'tcpDuration': tcpDuration,
        'tcpParallel': tcpParallel,
        'udpMbps': udpMbps,
        'udpDuration': udpDuration,
        'udpParallel': udpParallel,
        'udpPacketBytes': udpPacketBytes,
        'keepScreenOn': keepScreenOn,
        'logGpsTrack': logGpsTrack,
        'latencyDuringTests': latencyDuringTests,
        'twampHost': twampHost,
        'twampPort': twampPort,
        'latencyRateHz': latencyRateHz,
        'twampPacketBytes': twampPacketBytes,
        'pingHost': pingHost,
        'latencyDuration': latencyDuration,
        'repeatUntilStopped': repeatUntilStopped,
        'repeatIntervalSeconds': repeatIntervalSeconds,
      };

  factory Settings.fromJson(Map<String, dynamic> j) {
    final d = Settings();
    return Settings(
      host: j['host'] as String? ?? d.host,
      port: (j['port'] as num?)?.toInt() ?? d.port,
      tcpDuration: (j['tcpDuration'] as num?)?.toInt() ?? d.tcpDuration,
      tcpParallel: (j['tcpParallel'] as num?)?.toInt() ?? d.tcpParallel,
      udpMbps: (j['udpMbps'] as num?)?.toDouble() ?? d.udpMbps,
      udpDuration: (j['udpDuration'] as num?)?.toInt() ?? d.udpDuration,
      udpParallel: (j['udpParallel'] as num?)?.toInt() ?? d.udpParallel,
      udpPacketBytes: (j['udpPacketBytes'] as num?)?.toInt() ?? d.udpPacketBytes,
      keepScreenOn: j['keepScreenOn'] as bool? ?? d.keepScreenOn,
      logGpsTrack: j['logGpsTrack'] as bool? ?? d.logGpsTrack,
      latencyDuringTests: j['latencyDuringTests'] as bool? ?? d.latencyDuringTests,
      twampHost: j['twampHost'] as String? ?? d.twampHost,
      twampPort: (j['twampPort'] as num?)?.toInt() ?? d.twampPort,
      latencyRateHz: (j['latencyRateHz'] as num?)?.toInt() ?? d.latencyRateHz,
      twampPacketBytes: (j['twampPacketBytes'] as num?)?.toInt() ?? d.twampPacketBytes,
      pingHost: j['pingHost'] as String? ?? d.pingHost,
      latencyDuration: (j['latencyDuration'] as num?)?.toInt() ?? d.latencyDuration,
      repeatUntilStopped: j['repeatUntilStopped'] as bool? ?? d.repeatUntilStopped,
      repeatIntervalSeconds: (j['repeatIntervalSeconds'] as num?)?.toInt() ?? d.repeatIntervalSeconds,
    );
  }
}

enum UdpDirection { download, upload, both }

class AppState extends ChangeNotifier {
  final DataStore store = DataStore();
  Settings settings = Settings();

  List<Site> sites = [];
  Site? activeSite;

  Position? position;
  String? locationProblem;
  RadioSnapshot radio = RadioSnapshot.empty();

  // Live test state.
  bool running = false;
  String? phase; // e.g. "TCP Download"
  double currentMbps = 0;
  double elapsed = 0;
  int plannedSeconds = 0;
  int round = 0; // repeat mode: current round (1-based)
  String? waitingText; // repeat mode: countdown between rounds
  int _failStreak = 0;
  final List<double> liveSeries = [];
  final List<TestRecord> recent = [];
  String? lastError;

  // Latency probe: runs for the whole test session (TWAMP-Light or ping).
  LatencyProbe? _probe;
  StreamSubscription<ProbeResult>? _probeSub;
  Timer? _latencyFlushTimer;
  String? latencyProblem; // shown as a note; never stops a throughput test
  String? latencyLabel; // e.g. "TWAMP 203.0.113.5:862"
  LatencyStats? latencyLive; // most recent completed second
  bool latencyPhase = false; // true during a stand-alone latency test
  final Map<int, _LatencySecond> _latencySeconds = {};
  final List<_TestWindow> _windows = [];

  IperfClient? _client;
  bool _cancelSequence = false;
  StreamSubscription<Position>? _positionSub;
  Timer? _radioTimer;
  Timer? _trackTimer;
  Timer? _flushTimer;
  bool _radioBusy = false;
  bool _initialized = false;

  bool get initialized => _initialized;

  Future<void> init() async {
    await store.init();
    settings = Settings.fromJson(await store.loadSettings());
    sites = await store.loadSites();
    final activeId = (await store.loadSettings())['activeSiteId'] as String?;
    if (activeId != null) {
      for (final s in sites) {
        if (s.id == activeId) activeSite = s;
      }
    }
    _initialized = true;
    notifyListeners();

    await startLocation();
    await RadioInfo.requestPhonePermission();
    await _pollRadio();
    _radioTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollRadio());
    _trackTimer = Timer.periodic(const Duration(seconds: 1), (_) => _logTrack());
    // Write buffered rows to disk regularly, so a crash or dead battery during
    // a long run loses at most a few seconds of data.
    _flushTimer = Timer.periodic(const Duration(seconds: 10), (_) => store.flush());
  }

  // ------------------------------------------------------------------ GPS

  Future<void> startLocation() async {
    locationProblem = null;
    if (!await Geolocator.isLocationServiceEnabled()) {
      locationProblem = 'Location services are off. Turn on Location in your phone settings.';
      notifyListeners();
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      locationProblem = 'Location permission is denied. Allow location for WiFi Analytics in Settings.';
      notifyListeners();
      return;
    }
    await _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 0),
    ).listen((p) {
      position = p;
      notifyListeners();
    }, onError: (Object e) {
      locationProblem = 'GPS error: $e';
      notifyListeners();
    });
  }

  Future<void> openLocationSettings() async {
    if (locationProblem?.contains('services') == true) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  // ------------------------------------------------------------------ radio

  Future<void> _pollRadio() async {
    if (_radioBusy) return;
    _radioBusy = true;
    try {
      radio = RadioSnapshot(await RadioInfo.get());
      notifyListeners();
    } finally {
      _radioBusy = false;
    }
  }

  void _logTrack() {
    if (!settings.logGpsTrack || position == null) return;
    final now = DateTime.now();
    store.addTrack([
      now.toUtc().toIso8601String(),
      _local(now),
      activeSite?.id,
      running ? 1 : 0,
      ...GpsCsv.values(position),
      ...radio.csvValues,
    ]);
  }

  // ------------------------------------------------------------------ sites

  Future<void> addSite({required String id, required String name, String notes = ''}) async {
    final p = position;
    final site = Site(
      id: id.trim(),
      name: name.trim(),
      notes: notes.trim(),
      latitude: p?.latitude,
      longitude: p?.longitude,
      accuracy: p?.accuracy,
    );
    sites.removeWhere((s) => s.id == site.id);
    sites.insert(0, site);
    activeSite = site;
    await store.saveSites(sites);
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setActiveSite(Site? site) async {
    activeSite = site;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> deleteSite(Site site) async {
    sites.removeWhere((s) => s.id == site.id);
    if (activeSite?.id == site.id) activeSite = null;
    await store.saveSites(sites);
    await _saveSettings();
    notifyListeners();
  }

  // ------------------------------------------------------------------ settings

  Future<void> updateSettings(Settings s) async {
    settings = s;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> _saveSettings() =>
      store.saveSettings({...settings.toJson(), 'activeSiteId': activeSite?.id});

  // ------------------------------------------------------------------ tests

  String? validateServer() {
    if (settings.host.trim().isEmpty) {
      return 'Enter your iperf3 server address in Settings first.';
    }
    return null;
  }

  /// TCP download then upload.
  Future<void> runSpeedTest() => _runSequence([
        _tcpConfig(IperfDirection.download),
        _tcpConfig(IperfDirection.upload),
      ]);

  Future<void> runUdpStream(UdpDirection dir) => _runSequence([
        if (dir != UdpDirection.upload) _udpConfig(IperfDirection.download),
        if (dir != UdpDirection.download) _udpConfig(IperfDirection.upload),
      ]);

  IperfConfig _tcpConfig(IperfDirection d) => IperfConfig(
        host: settings.host.trim(),
        port: settings.port,
        protocol: IperfProtocol.tcp,
        direction: d,
        durationSeconds: settings.tcpDuration,
        parallel: settings.tcpParallel,
      );

  IperfConfig _udpConfig(IperfDirection d) => IperfConfig(
        host: settings.host.trim(),
        port: settings.port,
        protocol: IperfProtocol.udp,
        direction: d,
        durationSeconds: settings.udpDuration,
        parallel: settings.udpParallel,
        udpBandwidthBps: (settings.udpMbps * 1e6).round(),
        udpPacketLength: settings.udpPacketBytes,
      );

  /// Waits [seconds] between repeat rounds, showing a countdown; returns early on Stop.
  Future<void> _countdown(int seconds, String label) async {
    for (var left = seconds; left > 0 && !_cancelSequence; left--) {
      waitingText = '$label in $left s';
      notifyListeners();
      await Future.delayed(const Duration(seconds: 1));
    }
    waitingText = null;
    notifyListeners();
  }

  /// Stops the running test and any remaining tests in the sequence.
  void stop() {
    _cancelSequence = true;
    _client?.stop();
    notifyListeners();
  }

  Future<void> _runSequence(List<IperfConfig> configs) async {
    if (running) return;
    final problem = validateServer();
    if (problem != null) {
      lastError = problem;
      notifyListeners();
      return;
    }
    running = true;
    _cancelSequence = false;
    lastError = null;
    notifyListeners();
    if (settings.keepScreenOn) {
      try {
        await WakelockPlus.enable();
      } catch (_) {}
    }
    if (settings.latencyDuringTests) await _startLatency();
    round = 0;
    _failStreak = 0;
    try {
      while (true) {
        round++;
        for (var i = 0; i < configs.length; i++) {
          if (_cancelSequence) break;
          if (i > 0) await Future.delayed(const Duration(milliseconds: 1500));
          if (_cancelSequence) break;
          await _runOne(configs[i]);
        }
        if (_cancelSequence || !settings.repeatUntilStopped) break;
        await store.flush();
        if (_failStreak > 0) {
          // Back off after errors (network change, server busy/down): 10 s, 20 s, 40 s ... max 2 min.
          final s = min(120, 10 * (1 << min(_failStreak - 1, 4)));
          await _countdown(s, 'Retrying');
        } else {
          await _countdown(settings.repeatIntervalSeconds, 'Next round');
        }
        if (_cancelSequence) break;
      }
    } finally {
      waitingText = null;
      await _stopLatency();
      running = false;
      phase = null;
      _client = null;
      await store.flush();
      try {
        await WakelockPlus.disable();
      } catch (_) {}
      notifyListeners();
    }
  }

  Future<void> _runOne(IperfConfig cfg) async {
    final start = DateTime.now();
    final testId = '${_compact(start)}-${cfg.label.replaceAll(' ', '').toLowerCase()}';
    final startPos = position;
    await _pollRadio();
    final startRadio = radio;
    final site = activeSite;

    phase = cfg.label;
    currentMbps = 0;
    elapsed = 0;
    plannedSeconds = cfg.durationSeconds;
    liveSeries.clear();
    final samples = <double>[];
    notifyListeners();

    final window = _TestWindow(testId, cfg.label, start);
    _windows.add(window);

    final client = IperfClient(cfg);
    _client = client;
    final sub = client.intervals.listen((iv) {
      currentMbps = iv.mbps;
      elapsed = iv.elapsedSeconds;
      liveSeries.add(iv.mbps);
      samples.add(iv.mbps);
      if (liveSeries.length > 600) liveSeries.removeAt(0);
      final now = DateTime.now();
      store.addSample([
        testId,
        cfg.label,
        now.toUtc().toIso8601String(),
        _local(now),
        iv.elapsedSeconds.toStringAsFixed(1),
        iv.mbps.toStringAsFixed(2),
        site?.id,
        ...GpsCsv.values(position),
        ...radio.csvValues,
      ]);
      notifyListeners();
    });

    TestRecord record;
    try {
      final r = await client.run();
      final stats = SpeedStats.of(samples);
      record = TestRecord(
        testId: testId,
        type: cfg.label,
        start: start,
        durationSeconds: r.durationSeconds,
        mbps: r.mbps,
        jitterMs: r.jitterMs,
        lost: r.lostPackets,
        total: r.totalPackets,
        stoppedByUser: r.stoppedByUser,
        minMbps: stats?.min,
        maxMbps: stats?.max,
        medianMbps: stats?.median,
        p10Mbps: stats?.p10,
        p90Mbps: stats?.p90,
      );
      _failStreak = 0;
      if (settings.repeatUntilStopped) lastError = null;
    } catch (e) {
      final msg = e is IperfException
          ? e.message
          : e is SocketException
              ? 'Network error: ${e.osError?.message ?? e.message}'
              : e.toString();
      lastError = '${cfg.label}: $msg';
      record = TestRecord(
        testId: testId,
        type: cfg.label,
        start: start,
        durationSeconds: DateTime.now().difference(start).inMilliseconds / 1000,
        error: msg,
      );
      if (settings.repeatUntilStopped) {
        _failStreak++; // keep going: retry with back-off
      } else {
        _cancelSequence = true; // don't keep hammering a failing server
      }
    } finally {
      await sub.cancel();
      await client.dispose();
    }

    // Latency under load for this test (packets still in flight settle first).
    window.end = DateTime.now();
    final probe = _probe;
    if (probe != null) await Future.delayed(probe.timeout);
    _windows.remove(window);
    record = record.withLatency(window.acc.isEmpty ? null : window.acc.stats(), probe == null ? null : latencyLabel,
        apInfo: startRadio.apSummary);

    recent.insert(0, record);
    if (recent.length > 50) recent.removeLast();

    store.addTest([
      record.testId,
      record.type,
      start.toUtc().toIso8601String(),
      _local(start),
      record.durationSeconds.toStringAsFixed(1),
      record.mbps?.toStringAsFixed(2),
      record.minMbps?.toStringAsFixed(2),
      record.maxMbps?.toStringAsFixed(2),
      record.medianMbps?.toStringAsFixed(2),
      record.p10Mbps?.toStringAsFixed(2),
      record.p90Mbps?.toStringAsFixed(2),
      record.jitterMs?.toStringAsFixed(3),
      record.lost,
      record.total,
      record.lossPercent?.toStringAsFixed(3),
      record.stoppedByUser ? 1 : 0,
      record.error,
      cfg.host,
      cfg.port,
      cfg.parallel,
      cfg.protocol == IperfProtocol.udp ? (cfg.udpBandwidthBps / 1e6).toStringAsFixed(2) : null,
      cfg.protocol == IperfProtocol.udp ? cfg.udpPacketLength : null,
      site?.id,
      site?.name,
      Platform.operatingSystem,
      ...latencyCsv(record),
      ...GpsCsv.values(startPos ?? position),
      ...startRadio.csvValues,
    ]);
    await store.flush();
    notifyListeners();
  }

  static List<Object?> latencyCsv(TestRecord r) {
    final l = r.latency;
    String? f(double? v) => v?.toStringAsFixed(2);
    return [
      r.latencyTarget,
      f(l?.avgMs),
      f(l?.minMs),
      f(l?.maxMs),
      f(l?.medianMs),
      f(l?.jitterMs),
      l?.lossPercent?.toStringAsFixed(2),
      l?.sent,
    ];
  }

  // ------------------------------------------------------------------ latency

  /// Picks TWAMP when a reflector is set, else ping (Android only).
  LatencyProbe? _makeProbe() {
    final reflector = settings.twampHost.trim();
    if (reflector.isNotEmpty) {
      return TwampLightProbe(
        host: reflector,
        port: settings.twampPort,
        rateHz: settings.latencyRateHz,
        packetBytes: settings.twampPacketBytes,
      );
    }
    if (PingProbe.supported && settings.pingHost.trim().isNotEmpty) {
      return PingProbe(host: settings.pingHost.trim(), rateHz: min(settings.latencyRateHz, 5));
    }
    latencyProblem = Platform.isIOS
        ? 'Latency not measured: iPhone needs a TWAMP reflector (Settings > Latency).'
        : 'Latency not measured: set a TWAMP reflector or ping host in Settings.';
    return null;
  }

  Future<void> _startLatency() async {
    if (_probe != null) return;
    latencyProblem = null;
    latencyLive = null;
    final probe = _makeProbe();
    if (probe == null) {
      notifyListeners();
      return;
    }
    try {
      await probe.start();
    } catch (e) {
      latencyProblem = 'Latency not measured: $e';
      notifyListeners();
      return;
    }
    _probe = probe;
    latencyLabel = '${probe.method.label} ${probe.target}';
    _probeSub = probe.results.listen(_onProbeResult, onError: (Object e) {
      latencyProblem = e.toString();
      notifyListeners();
    });
    _latencyFlushTimer = Timer.periodic(const Duration(seconds: 1), (_) => _flushLatency());
    notifyListeners();
  }

  void _onProbeResult(ProbeResult r) {
    final key = r.sentAt.millisecondsSinceEpoch ~/ 1000;
    final second = _latencySeconds.putIfAbsent(key, () {
      final w = _windowAt(r.sentAt);
      return _LatencySecond(DateTime.fromMillisecondsSinceEpoch(key * 1000), w?.testId, w?.type, position, radio);
    });
    second.acc.add(r);
    _windowAt(r.sentAt)?.acc.add(r);
  }

  _TestWindow? _windowAt(DateTime t) {
    for (final w in _windows) {
      if (!t.isBefore(w.start) && (w.end == null || !t.isAfter(w.end!))) return w;
    }
    return null;
  }

  /// Writes each finished second to twamp.csv. A second is finished once every
  /// packet sent in it has either come back or timed out.
  void _flushLatency({bool all = false}) {
    final probe = _probe;
    final lagSeconds = (probe?.timeout.inSeconds ?? 2) + 1;
    final cutoff = DateTime.now().millisecondsSinceEpoch ~/ 1000 - lagSeconds;
    final keys = _latencySeconds.keys.where((k) => all || k <= cutoff).toList()..sort();
    if (keys.isEmpty) return;
    for (final k in keys) {
      final s = _latencySeconds.remove(k)!;
      final st = s.acc.stats();
      latencyLive = st;
      if (latencyPhase) {
        liveSeries.add(st.avgMs ?? 0);
        if (liveSeries.length > 600) liveSeries.removeAt(0);
      }
      String? f(double? v) => v?.toStringAsFixed(2);
      store.addLatency([
        s.time.toUtc().toIso8601String(),
        _local(s.time),
        s.testId,
        s.testType,
        probe?.method.label ?? latencyLabel?.split(' ').first,
        probe?.target ?? latencyLabel?.split(' ').last,
        st.sent,
        st.received,
        st.lost,
        st.lossPercent?.toStringAsFixed(2),
        f(st.minMs),
        f(st.avgMs),
        f(st.maxMs),
        f(st.medianMs),
        f(st.jitterMs),
        f(st.outboundAvgMs),
        f(st.inboundAvgMs),
        activeSite?.id,
        ...GpsCsv.values(s.position),
        ...s.radio.csvValues,
      ]);
    }
    notifyListeners();
  }

  Future<void> _stopLatency() async {
    final probe = _probe;
    if (probe == null) return;
    await probe.stop(); // waits for in-flight packets, reports the rest lost
    await _probeSub?.cancel();
    _probeSub = null;
    _latencyFlushTimer?.cancel();
    _latencyFlushTimer = null;
    _flushLatency(all: true);
    _probe = null;
    await store.flush();
  }

  /// Stand-alone latency test (no throughput traffic).
  Future<void> runLatencyTest() async {
    if (running) return;
    running = true;
    latencyPhase = true;
    _cancelSequence = false;
    lastError = null;
    phase = 'Latency';
    elapsed = 0;
    plannedSeconds = settings.latencyDuration;
    liveSeries.clear();
    notifyListeners();
    if (settings.keepScreenOn) {
      try {
        await WakelockPlus.enable();
      } catch (_) {}
    }
    final start = DateTime.now();
    Timer? ticker;
    try {
      await _startLatency();
      final probe = _probe;
      if (probe == null) {
        lastError = latencyProblem;
        return;
      }
      final type = 'Latency ${probe.method.label}';
      phase = type;
      final testId = '${_compact(start)}-latency${probe.method.label.toLowerCase()}';
      final startPos = position;
      final startRadio = radio;
      final site = activeSite;
      final window = _TestWindow(testId, type, start);
      _windows.add(window);
      final done = Completer<void>();
      ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        elapsed = DateTime.now().difference(start).inMilliseconds / 1000;
        if (_cancelSequence || (plannedSeconds > 0 && elapsed >= plannedSeconds)) {
          if (!done.isCompleted) done.complete();
        }
        notifyListeners();
      });
      await done.future;
      ticker.cancel();
      window.end = DateTime.now();
      await _stopLatency();
      _windows.remove(window);
      final stats = window.acc.isEmpty ? null : window.acc.stats();
      final record = TestRecord(
        testId: testId,
        type: type,
        start: start,
        durationSeconds: window.end!.difference(start).inMilliseconds / 1000,
        stoppedByUser: _cancelSequence,
        error: (stats == null || stats.received == 0) ? (latencyProblem ?? 'No replies') : null,
      ).withLatency(stats, latencyLabel, apInfo: startRadio.apSummary);
      recent.insert(0, record);
      if (recent.length > 50) recent.removeLast();
      store.addTest([
        record.testId,
        record.type,
        start.toUtc().toIso8601String(),
        _local(start),
        record.durationSeconds.toStringAsFixed(1),
        null, null, null, null, null, null, // throughput columns
        stats?.jitterMs?.toStringAsFixed(3),
        stats?.lost,
        stats?.sent,
        stats?.lossPercent?.toStringAsFixed(3),
        record.stoppedByUser ? 1 : 0,
        record.error,
        probe.target,
        null, null, null,
        probe is TwampLightProbe ? probe.packetBytes : null,
        site?.id,
        site?.name,
        Platform.operatingSystem,
        ...latencyCsv(record),
        ...GpsCsv.values(startPos ?? position),
        ...startRadio.csvValues,
      ]);
    } finally {
      ticker?.cancel();
      await _stopLatency();
      running = false;
      latencyPhase = false;
      phase = null;
      await store.flush();
      try {
        await WakelockPlus.disable();
      } catch (_) {}
      notifyListeners();
    }
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _compact(DateTime t) =>
      '${t.year}${_two(t.month)}${_two(t.day)}-${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';

  static String _local(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

  @override
  void dispose() {
    _positionSub?.cancel();
    _radioTimer?.cancel();
    _trackTimer?.cancel();
    _flushTimer?.cancel();
    _client?.stop();
    _probe?.stop();
    _latencyFlushTimer?.cancel();
    super.dispose();
  }
}

/// Probe results for one wall-clock second, with GPS/radio from that moment.
class _LatencySecond {
  final DateTime time;
  final String? testId;
  final String? testType;
  final Position? position;
  final RadioSnapshot radio;
  final LatencyAccumulator acc = LatencyAccumulator();
  _LatencySecond(this.time, this.testId, this.testType, this.position, this.radio);
}

/// Time span of one test, used to attach latency-under-load to that test.
class _TestWindow {
  final String testId;
  final String type;
  final DateTime start;
  DateTime? end;
  final LatencyAccumulator acc = LatencyAccumulator();
  _TestWindow(this.testId, this.type, this.start);
}
