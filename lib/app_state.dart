import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:radio_info/radio_info.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'iperf/iperf_client.dart';
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
  final List<double> liveSeries = [];
  final List<TestRecord> recent = [];
  String? lastError;

  IperfClient? _client;
  bool _cancelSequence = false;
  StreamSubscription<Position>? _positionSub;
  Timer? _radioTimer;
  Timer? _trackTimer;
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
    try {
      for (var i = 0; i < configs.length; i++) {
        if (_cancelSequence) break;
        if (i > 0) await Future.delayed(const Duration(milliseconds: 1500));
        if (_cancelSequence) break;
        await _runOne(configs[i]);
      }
    } finally {
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
      _cancelSequence = true; // don't keep hammering a failing server
    } finally {
      await sub.cancel();
      await client.dispose();
    }

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
      ...GpsCsv.values(startPos ?? position),
      ...startRadio.csvValues,
    ]);
    await store.flush();
    notifyListeners();
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
    _client?.stop();
    super.dispose();
  }
}
