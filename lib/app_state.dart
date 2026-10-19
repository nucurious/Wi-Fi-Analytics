import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:radio_info/radio_info.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'iperf/iperf_background.dart';
import 'iperf/iperf_client.dart';
import 'iperf/server_pool.dart';
import 'latency/latency_probe.dart';
import 'models.dart';
import 'util/file_naming.dart';
import 'util/host_address.dart';
import 'services/data_store.dart';
import 'services/session_mailer.dart';

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

  // Traffic profiles
  String driveUdpDirection; // 'download' | 'upload'
  int walkSettleSeconds; // wait after joining Wi-Fi before testing
  int walkMinGapSeconds; // minimum time between two walk speed tests
  bool walkTriggerOnRoam; // also test when the phone moves to a new AP (Android)

  // Email results when a session stops (Gmail SMTP)
  bool emailResults;
  String emailTo;
  String smtpUser; // sender Gmail address
  String smtpPassword; // Gmail app password (16 characters)
  String imeiLast4; // used in file names; auto-filled where Android allows

  // When a test can't start (server busy, down or unreachable), try the next
  // port / public server instead, and keep that failure out of the results.
  bool rotateServers;

  // Output file names
  String testEnvironment; // 'auto' | 'field' | 'lab'
  String locationCode; // e.g. DAL; blank = from the site or GPS

  Settings({
    this.host = '96.37.191.0', // lab iperf3 server (Spectrum Business, 1 Gbps)
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
    this.driveUdpDirection = 'download',
    this.walkSettleSeconds = 5,
    this.walkMinGapSeconds = 60,
    this.walkTriggerOnRoam = false,
    this.emailResults = true,
    this.emailTo = 'rockfordtest7@gmail.com',
    this.smtpUser = '',
    this.smtpPassword = '',
    this.imeiLast4 = '',
    this.rotateServers = true,
    this.testEnvironment = 'auto',
    this.locationCode = '',
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
        'driveUdpDirection': driveUdpDirection,
        'walkSettleSeconds': walkSettleSeconds,
        'walkMinGapSeconds': walkMinGapSeconds,
        'walkTriggerOnRoam': walkTriggerOnRoam,
        'emailResults': emailResults,
        'emailTo': emailTo,
        'smtpUser': smtpUser,
        'smtpPassword': smtpPassword,
        'imeiLast4': imeiLast4,
        'rotateServers': rotateServers,
        'testEnvironment': testEnvironment,
        'locationCode': locationCode,
      };

  factory Settings.fromJson(Map<String, dynamic> j) {
    final d = Settings();
    // Repair addresses saved by older versions, e.g. "2600:...:9c38:5201"
    // (port stuck on the end) or with stray spaces: the port moves to its field.
    final (savedHost, hostPort) = splitHostPort((j['host'] as String?) ?? '');
    final (savedTwamp, twampPort) = splitHostPort((j['twampHost'] as String?) ?? d.twampHost);
    return Settings(
      host: savedHost.isNotEmpty ? savedHost : d.host,
      port: hostPort ?? (j['port'] as num?)?.toInt() ?? d.port,
      tcpDuration: (j['tcpDuration'] as num?)?.toInt() ?? d.tcpDuration,
      tcpParallel: (j['tcpParallel'] as num?)?.toInt() ?? d.tcpParallel,
      udpMbps: (j['udpMbps'] as num?)?.toDouble() ?? d.udpMbps,
      udpDuration: (j['udpDuration'] as num?)?.toInt() ?? d.udpDuration,
      udpParallel: (j['udpParallel'] as num?)?.toInt() ?? d.udpParallel,
      udpPacketBytes: (j['udpPacketBytes'] as num?)?.toInt() ?? d.udpPacketBytes,
      keepScreenOn: j['keepScreenOn'] as bool? ?? d.keepScreenOn,
      logGpsTrack: j['logGpsTrack'] as bool? ?? d.logGpsTrack,
      latencyDuringTests: j['latencyDuringTests'] as bool? ?? d.latencyDuringTests,
      twampHost: savedTwamp,
      twampPort: twampPort ?? (j['twampPort'] as num?)?.toInt() ?? d.twampPort,
      latencyRateHz: (j['latencyRateHz'] as num?)?.toInt() ?? d.latencyRateHz,
      twampPacketBytes: (j['twampPacketBytes'] as num?)?.toInt() ?? d.twampPacketBytes,
      pingHost: j['pingHost'] as String? ?? d.pingHost,
      latencyDuration: (j['latencyDuration'] as num?)?.toInt() ?? d.latencyDuration,
      repeatUntilStopped: j['repeatUntilStopped'] as bool? ?? d.repeatUntilStopped,
      repeatIntervalSeconds: (j['repeatIntervalSeconds'] as num?)?.toInt() ?? d.repeatIntervalSeconds,
      driveUdpDirection: j['driveUdpDirection'] as String? ?? d.driveUdpDirection,
      walkSettleSeconds: (j['walkSettleSeconds'] as num?)?.toInt() ?? d.walkSettleSeconds,
      walkMinGapSeconds: (j['walkMinGapSeconds'] as num?)?.toInt() ?? d.walkMinGapSeconds,
      walkTriggerOnRoam: j['walkTriggerOnRoam'] as bool? ?? d.walkTriggerOnRoam,
      emailResults: j['emailResults'] as bool? ?? d.emailResults,
      emailTo: j['emailTo'] as String? ?? d.emailTo,
      smtpUser: j['smtpUser'] as String? ?? d.smtpUser,
      smtpPassword: j['smtpPassword'] as String? ?? d.smtpPassword,
      imeiLast4: j['imeiLast4'] as String? ?? d.imeiLast4,
      rotateServers: j['rotateServers'] as bool? ?? d.rotateServers,
      testEnvironment: j['testEnvironment'] as String? ?? d.testEnvironment,
      locationCode: j['locationCode'] as String? ?? d.locationCode,
    );
  }
}

enum UdpDirection { download, upload, both }

/// How a test session was started.
enum TestProfile { manual, drive, walk, lab }

extension TestProfileLabel on TestProfile {
  String get label => switch (this) { TestProfile.manual => 'Manual', TestProfile.drive => 'Drive', TestProfile.walk => 'Walk', TestProfile.lab => 'Lab' };
}

class AppState extends ChangeNotifier {
  final DataStore store = DataStore();
  late final SessionMailer mailer = SessionMailer(store);
  Map<String, dynamic> device = {}; // make, model, osVersion, imeiLast4 (if readable)
  DateTime? _sessionStart;
  Map<String, int>? _sessionOffsets;
  TestProfile _sessionProfile = TestProfile.manual;
  Timer? _emailTimer;
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
  TestProfile profile = TestProfile.manual; // profile of the running session
  bool _keepGoing = false; // repeat / drive / walk: errors don't end the session
  String _trigger = 'Manual'; // why the current test started (tests.csv)
  int walkTests = 0; // speed tests triggered in this walk session
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

  BackgroundIperfClient? _client;
  final _clients = <BackgroundIperfClient>{};
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

    device = await RadioInfo.deviceInfo();
    final imei = device['imeiLast4'] as String?;
    if (imei != null && settings.imeiLast4.isEmpty) {
      settings.imeiLast4 = imei;
      await _saveSettings();
    }
    // Send anything left from sessions that ended without signal.
    unawaited(sendPendingEmail());
    _emailTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      if (!running && mailer.pendingCount() > 0) sendPendingEmail();
    });
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
      running ? profile.label : null,
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

  /// Drive profile: TWAMP (or ping) + one continuous UDP stream until Stop.
  /// Restarts within seconds after a network change or server drop.
  Future<void> startDriveTest() => _runSequence([
        _udpConfig(settings.driveUdpDirection == 'upload' ? IperfDirection.upload : IperfDirection.download, duration: 0),
      ], p: TestProfile.drive);

  /// Lab profile: latency all the time + one UDP downstream and one UDP
  /// upstream at the same time, until Stop. iperf3 runs one test per port, so
  /// the upstream uses the next port (5202 on the lab server). Files are named Lab_..._lab_...
  Future<void> startLabTest() {
    final up = _udpConfig(IperfDirection.upload, duration: 0);
    return _runSequence([
      _udpConfig(IperfDirection.download, duration: 0),
      _onServer(up, up.host, up.port + 1),
    ], p: TestProfile.lab);
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

  IperfConfig _udpConfig(IperfDirection d, {int? duration}) => IperfConfig(
        host: settings.host.trim(),
        port: settings.port,
        protocol: IperfProtocol.udp,
        direction: d,
        durationSeconds: duration ?? settings.udpDuration,
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
    for (final c in List.of(_clients)) {
      c.stop();
    }
    notifyListeners();
  }

  Future<void> _runSequence(List<IperfConfig> configs, {TestProfile p = TestProfile.manual}) async {
    if (running) return;
    final problem = validateServer();
    if (problem != null) {
      lastError = problem;
      notifyListeners();
      return;
    }
    running = true;
    profile = p;
    _keepGoing = p == TestProfile.drive || p == TestProfile.lab || settings.repeatUntilStopped;
    _trigger = switch (p) {
      TestProfile.drive => 'Drive profile',
      TestProfile.lab => 'Lab profile',
      _ => settings.repeatUntilStopped ? 'Repeat' : 'Manual',
    };
    _cancelSequence = false;
    lastError = null;
    notifyListeners();
    if (settings.keepScreenOn) {
      try {
        await WakelockPlus.enable();
      } catch (_) {}
    }
    await _beginSession(p);
    if (settings.latencyDuringTests || p != TestProfile.manual) await _startLatency();
    round = 0;
    _failStreak = 0;
    try {
      while (true) {
        round++;
        if (p == TestProfile.lab) {
          // Both directions at once, each restarting by itself after a drop.
          await Future.wait([for (final c in configs) _streamUntilStopped(c)]);
          break;
        }
        for (var i = 0; i < configs.length; i++) {
          if (_cancelSequence) break;
          if (i > 0) await Future.delayed(const Duration(milliseconds: 1500));
          if (_cancelSequence) break;
          await _runOne(configs[i]);
        }
        if (_cancelSequence || !_keepGoing) break;
        await store.flush();
        if (_failStreak > 0) {
          // Back off after errors (network change, server busy/down): 10 s, 20 s, 40 s ... max 2 min.
          // On a drive, retry fast (3, 6, 12 ... max 15 s) so little of the route is missed.
          final s = p == TestProfile.drive
              ? min(15, 3 * (1 << min(_failStreak - 1, 3)))
              : min(120, 10 * (1 << min(_failStreak - 1, 4)));
          await _countdown(s, 'Retrying');
        } else {
          await _countdown(
              switch (p) {
                TestProfile.drive => 1,
                _ => settings.repeatIntervalSeconds,
              },
              'Next round');
        }
        if (_cancelSequence) break;
      }
    } finally {
      waitingText = null;
      await _stopLatency();
      running = false;
      profile = TestProfile.manual;
      _keepGoing = false;
      phase = null;
      _client = null;
      await store.flush();
      try {
        await WakelockPlus.disable();
      } catch (_) {}
      notifyListeners();
      await _endSession();
    }
  }

  /// Public server in use after a switch; later tests in the session start there.
  (String, int)? _activeServer;
  final _activeByTest = <String, (String, int)>{}; // per test type (Lab runs two at once)

  /// Lab profile upstream rate while both directions run (null otherwise).
  double? upMbps;

  /// Runs one continuous stream until Stop, restarting after drops.
  Future<void> _streamUntilStopped(IperfConfig cfg) async {
    var fails = 0;
    while (!_cancelSequence) {
      final before = recent.isEmpty ? null : recent.first;
      await _runOne(cfg);
      if (_cancelSequence) break;
      final ok = recent.isNotEmpty && !identical(recent.first, before) && recent.first.error == null;
      fails = ok ? 0 : fails + 1;
      final wait = min(15, 3 * (1 << min(max(fails - 1, 0), 3)));
      for (var i = 0; i < wait && !_cancelSequence; i++) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  static IperfConfig _onServer(IperfConfig c, String host, int port) => IperfConfig(
        host: host,
        port: port,
        protocol: c.protocol,
        direction: c.direction,
        durationSeconds: c.durationSeconds,
        parallel: c.parallel,
        udpBandwidthBps: c.udpBandwidthBps,
        udpPacketLength: c.udpPacketLength,
      );

  /// Runs one test. With "Switch servers" on, a test that can't start (busy,
  /// down, unreachable, timed out before any data) is retried on the next
  /// port / public server; those failures go to the Server failures log, not
  /// to the results.
  Future<void> _runOne(IperfConfig base) async {
    final udp = base.protocol == IperfProtocol.udp;
    var cfg = base;
    final active = _activeByTest[base.label] ?? (profile == TestProfile.lab ? null : _activeServer);
    if (settings.rotateServers && active != null && (!udp || (publicServerFor(active.$1)?.udp ?? true))) {
      cfg = _onServer(base, active.$1, active.$2);
    }
    final tried = <String>{};
    for (var attempt = 0;; attempt++) {
      tried.add('${cfg.host}:${cfg.port}');
      final failed = await _runAttempt(cfg, skipSetupFailure: settings.rotateServers);
      waitingText = null;
      if (failed == null) return;
      final next = attempt < 7 && !_cancelSequence
          ? nextServer(cfg.host, cfg.port,
              busy: failed.toLowerCase().contains('busy'),
              refused: failed.toLowerCase().contains('refused'),
              udp: udp,
              tried: tried)
          : null;
      store.addFailure([
        DateTime.now().toUtc().toIso8601String(),
        _local(DateTime.now()),
        cfg.label,
        profile.label,
        cfg.host,
        cfg.port,
        failed,
        next?.$1,
        next?.$2,
        ...radio.csvValues,
      ]);
      if (next == null) {
        _activeServer = null; // next round starts from the configured server again
        _activeByTest.remove(base.label);
        lastError = _cancelSequence ? null : '${cfg.label}: $failed (no other server could run the test)';
        if (_keepGoing) {
          _failStreak++;
        } else {
          _cancelSequence = true;
        }
        notifyListeners();
        return;
      }
      _activeServer = next;
      _activeByTest[base.label] = next;
      waitingText = '${cfg.host}:${cfg.port} could not run the test, switching to ${next.$1}:${next.$2}';
      notifyListeners();
      cfg = _onServer(cfg, next.$1, next.$2);
      await Future.delayed(const Duration(milliseconds: 500));
      if (_cancelSequence) return;
    }
  }

  /// One test on one server. Returns null when the test ran (or failed after
  /// data started) and was recorded; returns the error, without recording,
  /// when [skipSetupFailure] and the test never got going.
  Future<String?> _runAttempt(IperfConfig cfg, {required bool skipSetupFailure}) async {
    final start = DateTime.now();
    final testId = '${_compact(start)}-${cfg.label.replaceAll(' ', '').toLowerCase()}';
    final startPos = position;
    await _pollRadio();
    final startRadio = radio;
    final site = activeSite;

    // Lab profile: the upstream runs alongside the downstream, which owns the main display.
    final secondary = profile == TestProfile.lab && cfg.direction == IperfDirection.upload;
    if (secondary) {
      upMbps = 0;
    } else {
      phase = profile == TestProfile.lab ? 'UDP down + up' : cfg.label;
      currentMbps = 0;
      elapsed = 0;
      plannedSeconds = cfg.durationSeconds;
      liveSeries.clear();
    }
    final samples = <double>[];
    notifyListeners();

    final window = _TestWindow(testId, cfg.label, start);
    _windows.add(window);

    final client = BackgroundIperfClient(cfg);
    _client = client;
    _clients.add(client);
    final sub = client.intervals.listen((iv) {
      if (samples.isEmpty) waitingText = null; // clear "switching to ..." once data flows
      samples.add(iv.mbps);
      if (secondary) {
        upMbps = iv.mbps;
      } else {
        currentMbps = iv.mbps;
        elapsed = iv.elapsedSeconds;
        liveSeries.add(iv.mbps);
        if (liveSeries.length > 600) liveSeries.removeAt(0);
      }
      final now = DateTime.now();
      store.addSample([
        testId,
        cfg.label,
        now.toUtc().toIso8601String(),
        _local(now),
        iv.elapsedSeconds.toStringAsFixed(1),
        iv.mbps.toStringAsFixed(2),
        site?.id,
        profile.label,
        ...GpsCsv.values(position),
        ...radio.csvValues,
      ]);
      notifyListeners();
    });

    TestRecord record;
    String? setupError;
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
      if (_keepGoing) lastError = null;
    } catch (e) {
      final msg = e is IperfException
          ? e.message
          : e is SocketException
              ? 'Network error: ${e.osError?.message ?? e.message}'
              : e.toString();
      if (skipSetupFailure && samples.isEmpty && !_cancelSequence) {
        setupError = msg;
      } else {
        lastError = '${cfg.label}: $msg';
      }
      record = TestRecord(
        testId: testId,
        type: cfg.label,
        start: start,
        durationSeconds: DateTime.now().difference(start).inMilliseconds / 1000,
        error: msg,
      );
      if (setupError != null) {
        // The caller switches server; this attempt is not a result.
      } else if (_keepGoing) {
        _failStreak++; // keep going: retry with back-off
      } else {
        _cancelSequence = true; // don't keep hammering a failing server
      }
    } finally {
      await sub.cancel();
      await client.dispose();
      _clients.remove(client);
      if (secondary) upMbps = null;
    }
    if (setupError != null) {
      _windows.remove(window);
      return setupError;
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
      profile.label,
      _trigger,
      ...latencyCsv(record),
      ...GpsCsv.values(startPos ?? position),
      ...startRadio.csvValues,
    ]);
    await store.flush();
    notifyListeners();
    return null;
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
        profile.label,
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

  // ------------------------------------------------------------------ email

  /// Lab when chosen in Settings, or (Auto) when on a Wi-Fi network or site
  /// with "lab" in its name, or within 300 m of the Denver lab.
  bool get inLab {
    switch (settings.testEnvironment) {
      case 'lab':
        return true;
      case 'field':
        return false;
    }
    if ((radio.wifiSsid ?? '').toLowerCase().contains('lab')) return true;
    if ((activeSite?.name ?? '').toLowerCase().contains('lab')) return true;
    final p = position;
    return p != null && (p.latitude - 39.6004).abs() < 0.0027 && (p.longitude - -104.8912).abs() < 0.0035;
  }

  /// Market code: Settings override, else nearest city to the site, else to GPS.
  String get locationLabel {
    final o = settings.locationCode.trim();
    if (o.isNotEmpty) return o.toUpperCase();
    final s = activeSite;
    if (s?.latitude != null && s?.longitude != null) {
      final c = marketCode(s!.latitude!, s.longitude!);
      if (c != null) return c;
    }
    final p = position;
    if (p != null) {
      final c = marketCode(p.latitude, p.longitude);
      if (c != null) return c;
    }
    final n = (s?.name ?? '').replaceAll(RegExp(r'[^A-Za-z]'), '');
    return n.length >= 3 ? n.substring(0, 3).toUpperCase() : 'NOLOC';
  }

  /// Output file name, e.g. Field_Samsung_S25_ylz1_walk_DAL_3245_20261019-1123 (session start).
  String fileName([TestProfile? p, DateTime? at]) {
    final prof = p ?? profile;
    final lab = prof == TestProfile.lab || inLab;
    final profileWord = switch (prof) {
      TestProfile.drive => 'drive',
      TestProfile.walk => 'walk',
      TestProfile.lab => 'lab',
      TestProfile.manual => 'stationary',
    };
    final t = at ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}';
    final imei = settings.imeiLast4.trim().isNotEmpty
        ? settings.imeiLast4.trim()
        : (device['imeiLast4'] ?? 'xxxx').toString();
    return [
      lab ? 'Lab' : 'Field',
      makeLabel(device),
      modelLabel(device),
      buildLabel(device).toLowerCase(),
      profileWord,
      locationLabel,
      imei,
      stamp,
    ].map(fileSafe).join('_');
  }

  String get devicePrefix => fileName();

  String? get emailStatus => mailer.lastStatus;
  int get emailPending => mailer.pendingCount();

  Future<void> _beginSession(TestProfile p) async {
    _sessionStart = DateTime.now();
    _sessionProfile = p;
    _activeServer = null;
    _activeByTest.clear();
    _sessionOffsets = await mailer.markStart();
  }

  Future<void> _endSession() async {
    final start = _sessionStart;
    final offsets = _sessionOffsets;
    _sessionStart = null;
    _sessionOffsets = null;
    if (start == null || offsets == null || !settings.emailResults) return;
    final end = DateTime.now();
    final prefix = fileName(_sessionProfile, start);
    final tests = recent.where((r) => !r.start.isBefore(start)).toList().reversed.toList();
    String two(int n) => n.toString().padLeft(2, '0');
    final dur = end.difference(start);
    final b = StringBuffer()
      ..writeln('WiFi Analytics results')
      ..writeln()
      ..writeln('Device:   ${device['make'] ?? ''} ${device['model'] ?? ''}  (IMEI last 4: ${settings.imeiLast4.isEmpty ? 'not set' : settings.imeiLast4})  ${device['osVersion'] ?? ''}')
      ..writeln('Profile:  ${_sessionProfile.label}')
      ..writeln('Start:    ${_local(start)}')
      ..writeln('End:      ${_local(end)}  (${dur.inHours}h ${two(dur.inMinutes % 60)}m ${two(dur.inSeconds % 60)}s)')
      ..writeln('Site:     ${activeSite == null ? '-' : '${activeSite!.id} ${activeSite!.name}'}')
      ..writeln('Server:   ${settings.host}:${settings.port}')
      ..writeln('Latency:  ${latencyLabel ?? 'off'}')
      ..writeln()
      ..writeln('Tests (${tests.length}${tests.length >= 50 ? ', last 50 shown' : ''}):');
    for (final r in tests) {
      final what = r.error != null
          ? 'FAILED: ${r.error}'
          : r.mbps != null
              ? '${r.mbps!.toStringAsFixed(1)} Mbps (min ${r.minMbps?.toStringAsFixed(1) ?? '-'} / max ${r.maxMbps?.toStringAsFixed(1) ?? '-'})'
              : '';
      final lat = r.latency?.avgMs == null ? '' : ', RTT ${r.latency!.avgMs!.toStringAsFixed(1)} ms';
      b.writeln('  ${_local(r.start)}  ${r.type}  $what$lat${r.apInfo != null ? '  [${r.apInfo}]' : ''}');
    }
    b
      ..writeln()
      ..writeln('Attached: $prefix.xlsx, one Excel workbook with a sheet each for')
      ..writeln('Tests, Speed (per second), Latency (per second) and GPS track, for this session only.');
    try {
      final queued = await mailer.queueSession(
        offsets: offsets,
        filePrefix: prefix,
        subject: 'WiFi Analytics: $prefix',
        body: b.toString(),
      );
      if (queued) unawaited(sendPendingEmail());
    } catch (e) {
      mailer.lastStatus = 'Could not prepare email: $e';
      notifyListeners();
    }
  }

  Future<void> sendPendingEmail() async {
    if (mailer.pendingCount() == 0) return;
    await mailer.sendOutbox(to: settings.emailTo, user: settings.smtpUser, appPassword: settings.smtpPassword);
    notifyListeners();
  }

  /// Walk profile: latency runs the whole time; a TCP speed test starts
  /// automatically each time the phone joins Wi-Fi (and, if enabled, when it
  /// moves to a new AP). Runs until Stop.
  Future<void> startWalkTest() async {
    if (running) return;
    final problem = validateServer();
    if (problem != null) {
      lastError = problem;
      notifyListeners();
      return;
    }
    running = true;
    profile = TestProfile.walk;
    _keepGoing = true;
    _cancelSequence = false;
    lastError = null;
    walkTests = 0;
    round = 0;
    phase = 'Walk test';
    notifyListeners();
    if (settings.keepScreenOn) {
      try {
        await WakelockPlus.enable();
      } catch (_) {}
    }
    await _beginSession(TestProfile.walk);
    try {
      await _startLatency();
      String? lastConn = radio.connection;
      String? lastBssid = radio.wifiBssid;
      DateTime? lastTest;
      // Already on Wi-Fi when the walk starts: test right away.
      DateTime? pendingSince = radio.isWifi ? DateTime.now() : null;
      String reason = radio.isWifi ? 'Walk start on Wi-Fi' : '';
      while (!_cancelSequence) {
        await Future.delayed(const Duration(seconds: 1));
        if (_cancelSequence) break;
        final r = radio;
        final now = DateTime.now();
        if (r.isWifi && lastConn != 'WIFI') {
          pendingSince = now;
          reason = 'Joined Wi-Fi ${r.wifiSsid ?? ''} ${r.wifiBssid ?? ''}'.trim();
        } else if (settings.walkTriggerOnRoam && r.isWifi && r.wifiBssid != null &&
            lastBssid != null && r.wifiBssid != lastBssid) {
          pendingSince = now;
          reason = 'AP change $lastBssid -> ${r.wifiBssid}';
        }
        if (!r.isWifi) pendingSince = null; // left Wi-Fi before the test began
        lastConn = r.connection;
        if (r.wifiBssid != null) lastBssid = r.wifiBssid;

        if (pendingSince != null) {
          final settled = now.difference(pendingSince).inSeconds >= settings.walkSettleSeconds;
          final gapLeft = lastTest == null
              ? 0
              : settings.walkMinGapSeconds - now.difference(lastTest).inSeconds;
          if (settled && gapLeft <= 0) {
            pendingSince = null;
            walkTests++;
            round = walkTests;
            _trigger = reason;
            waitingText = null;
            final configs = [_tcpConfig(IperfDirection.download), _tcpConfig(IperfDirection.upload)];
            for (var i = 0; i < configs.length && !_cancelSequence; i++) {
              if (i > 0) await Future.delayed(const Duration(milliseconds: 1500));
              if (_cancelSequence) break;
              await _runOne(configs[i]);
            }
            lastTest = DateTime.now();
            phase = 'Walk test';
            await store.flush();
            continue;
          }
          waitingText = settled
              ? 'Wi-Fi joined, next speed test in ${gapLeft}s'
              : 'Wi-Fi joined, testing in ${settings.walkSettleSeconds - now.difference(pendingSince).inSeconds}s';
        } else {
          waitingText = r.isWifi
              ? 'Walk: on Wi-Fi ${r.wifiSsid ?? ''}, waiting for next Wi-Fi join'
              : 'Walk: on ${r.rat}, waiting for Wi-Fi';
        }
        notifyListeners();
      }
    } finally {
      waitingText = null;
      await _stopLatency();
      running = false;
      profile = TestProfile.manual;
      _keepGoing = false;
      phase = null;
      _client = null;
      await store.flush();
      try {
        await WakelockPlus.disable();
      } catch (_) {}
      notifyListeners();
      await _endSession();
    }
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
    await _beginSession(TestProfile.manual);
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
        profile.label,
        'Manual',
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
      await _endSession();
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
    _emailTimer?.cancel();
    _client?.stop();
    for (final c in List.of(_clients)) {
      c.stop();
    }
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
