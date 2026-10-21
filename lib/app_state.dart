import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:radio_info/radio_info.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app_config.dart';
import 'iperf/iperf_background.dart';
import 'iperf/iperf_client.dart';
import 'iperf/server_pool.dart';
import 'services/xlsx_writer.dart';
import 'latency/latency_probe.dart';
import 'models.dart';
import 'util/file_naming.dart';
import 'util/host_address.dart';
import 'services/data_store.dart';
import 'services/dsds_tracker.dart';
import 'services/geofence_tracker.dart';
import 'services/logcat_recorder.dart';
import 'services/stall_monitor.dart';
import 'services/wifi_join_tracker.dart';
import 'services/session_mailer.dart';
import 'services/pptx_writer.dart';
import 'services/screen_recorder.dart';

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
  bool walkBackToBack; // keep testing (after the minimum gap) while the phone stays on Wi-Fi

  // Email results when a session stops (Gmail SMTP)
  bool emailResults;
  String emailTo;
  String smtpUser; // sender Gmail address
  String smtpPassword; // Gmail app password (16 characters)
  String imeiLast4; // used in file names; auto-filled where Android allows

  // When a test can't start (server busy, down or unreachable), try the next
  // port / public server instead, and keep that failure out of the results.
  bool rotateServers;

  bool recordLogcat; // debug app only: capture logcat during each session
  bool hmnoGeofence; // check the bundled Spectrum HMNO CBRS geofence
  bool spectrumWifi; // Android: log Wi-Fi scans / joins / time on Spectrum Wi-Fi
  String spectrumSsids; // comma-separated; an SSID containing any of these counts
  int wifiScanSeconds; // ask for a Wi-Fi scan this often (0 = only the phone's own scans)
  int logcatPartMb; // rotate logcat files at this size (64 MB gzips to ~6 MB, fits email)
  int logcatParts; // keep this many rotated files (older ones are overwritten)

  // Output file names
  String testEnvironment; // 'auto' | 'field' | 'lab'
  String locationCode; // e.g. DAL; blank = from the site or GPS

  Settings({
    this.host = '54.90.236.69', // first of the project's own iperf3 servers; public servers are the fallback
    this.port = 24101,
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
    this.pingHost = '8.8.8.8',
    this.latencyDuration = 60,
    this.repeatUntilStopped = false,
    this.repeatIntervalSeconds = 60,
    this.driveUdpDirection = 'download',
    this.walkSettleSeconds = 5,
    this.walkMinGapSeconds = 60,
    this.walkTriggerOnRoam = false,
    this.walkBackToBack = true,
    this.emailResults = true,
    this.emailTo = 'rockfordtest7@gmail.com',
    this.smtpUser = '',
    this.smtpPassword = '',
    this.imeiLast4 = '',
    this.rotateServers = true,
    this.recordLogcat = true,
    this.hmnoGeofence = true,
    this.spectrumWifi = true,
    this.spectrumSsids = 'SpectrumWiFi, Spectrum Mobile',
    this.wifiScanSeconds = 30,
    this.logcatPartMb = 64,
    this.logcatParts = 50,
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
        'walkBackToBack': walkBackToBack,
        'emailResults': emailResults,
        'emailTo': emailTo,
        'smtpUser': smtpUser,
        'smtpPassword': smtpPassword,
        'imeiLast4': imeiLast4,
        'rotateServers': rotateServers,
        'recordLogcat': recordLogcat,
        'hmnoGeofence': hmnoGeofence,
        'spectrumWifi': spectrumWifi,
        'spectrumSsids': spectrumSsids,
        'wifiScanSeconds': wifiScanSeconds,
        'logcatPartMb': logcatPartMb,
        'logcatParts': logcatParts,
        'testEnvironment': testEnvironment,
        'locationCode': locationCode,
      };

  static const _labServers = {'96.37.191.0', '2600:6ce6:4406:6006:8b6e:251:99cb:9c38', '10.92.5.100'};

  factory Settings.fromJson(Map<String, dynamic> j) {
    final d = Settings();
    // Repair addresses saved by older versions, e.g. "2600:...:9c38:5201"
    // (port stuck on the end) or with stray spaces: the port moves to its field.
    final (savedHost, hostPort) = splitHostPort((j['host'] as String?) ?? '');
    final (savedTwamp, twampPort) = splitHostPort((j['twampHost'] as String?) ?? d.twampHost);
    // The lab server (no longer used) and the old default (Clouvider Dallas:5200) move to the new default.
    final savedPort = hostPort ?? (j['port'] as num?)?.toInt();
    final oldDefault = savedHost == 'dal.speedtest.clouvider.net' && (savedPort ?? 5200) == 5200;
    final keepSaved = savedHost.isNotEmpty && !_labServers.contains(savedHost) && !oldDefault;
    return Settings(
      host: keepSaved ? savedHost : d.host,
      port: keepSaved ? (savedPort ?? d.port) : d.port,
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
      // 1.1.1.1 was the old default; ICMP to it was blocked on some lab networks, so it moves to 8.8.8.8.
      pingHost: (j['pingHost'] as String?) == null || j['pingHost'] == '1.1.1.1' ? d.pingHost : j['pingHost'] as String,
      latencyDuration: (j['latencyDuration'] as num?)?.toInt() ?? d.latencyDuration,
      repeatUntilStopped: j['repeatUntilStopped'] as bool? ?? d.repeatUntilStopped,
      repeatIntervalSeconds: (j['repeatIntervalSeconds'] as num?)?.toInt() ?? d.repeatIntervalSeconds,
      driveUdpDirection: j['driveUdpDirection'] as String? ?? d.driveUdpDirection,
      walkSettleSeconds: (j['walkSettleSeconds'] as num?)?.toInt() ?? d.walkSettleSeconds,
      walkMinGapSeconds: (j['walkMinGapSeconds'] as num?)?.toInt() ?? d.walkMinGapSeconds,
      walkTriggerOnRoam: j['walkTriggerOnRoam'] as bool? ?? d.walkTriggerOnRoam,
      walkBackToBack: j['walkBackToBack'] as bool? ?? d.walkBackToBack,
      emailResults: j['emailResults'] as bool? ?? d.emailResults,
      emailTo: j['emailTo'] as String? ?? d.emailTo,
      smtpUser: j['smtpUser'] as String? ?? d.smtpUser,
      smtpPassword: j['smtpPassword'] as String? ?? d.smtpPassword,
      imeiLast4: j['imeiLast4'] as String? ?? d.imeiLast4,
      rotateServers: j['rotateServers'] as bool? ?? d.rotateServers,
      recordLogcat: j['recordLogcat'] as bool? ?? d.recordLogcat,
      hmnoGeofence: j['hmnoGeofence'] as bool? ?? d.hmnoGeofence,
      spectrumWifi: j['spectrumWifi'] as bool? ?? d.spectrumWifi,
      spectrumSsids: j['spectrumSsids'] as String? ?? d.spectrumSsids,
      wifiScanSeconds: (j['wifiScanSeconds'] as num?)?.toInt() ?? d.wifiScanSeconds,
      logcatPartMb: (j['logcatPartMb'] as num?)?.toInt() ?? d.logcatPartMb,
      logcatParts: (j['logcatParts'] as num?)?.toInt() ?? d.logcatParts,
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
  // External app folder so the files can also be pulled with adb.
  late final LogcatRecorder logcat = LogcatRecorder(() async =>
      Directory('${((await getExternalStorageDirectory()) ?? store.directory).path}/logcat'));
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
  int noDataNow = 0; // seconds in a row without data on the main stream
  double? lastGoodMbps; // last non-zero second, shown while there is no data
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
    stalls.start();
    settings = Settings.fromJson(await store.loadSettings());
    wifiJoin.patterns = WifiJoinTracker.parsePatterns(settings.spectrumSsids);
    await _loadHmnoGeofence();
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
    if (Platform.isAndroid) {
      // 0.1 s during tests (a transition can be under 2 s), 0.25 s otherwise.
      _dsdsTimer = Timer.periodic(const Duration(milliseconds: 100), (_) => _pollDsds());
      _wifiTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollWifi());
    }
    _trackTimer = Timer.periodic(const Duration(seconds: 1), (_) => _logTrack());
    // Write buffered rows to disk regularly, so a crash or dead battery during
    // a long run loses at most a few seconds of data.
    _flushTimer = Timer.periodic(const Duration(seconds: 10), (_) => store.flush());

    await _checkPreviousExits();
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
      _checkGeofence(p);
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
      final sw = Stopwatch()..start();
      final snap = Map<String, dynamic>.of(await RadioInfo.get());
      for (final e in _cellIp.entries) {
        if ((snap[e.key] ?? '').toString().isEmpty) snap[e.key] = e.value;
      }
      radio = RadioSnapshot(snap);
      final took = sw.elapsedMilliseconds;
      if (took >= 3000) stalls.report('Slow native call', took, 'getRadioInfo (cell / Wi-Fi read)');
      final lag = (radio.raw['mainLagMs'] as num?)?.toInt() ?? 0;
      if (lag >= StallMonitor.thresholdMs) {
        stalls.report('Android main thread blocked', lag, 'touches and screen updates waited $lag ms',
            stack: radio.raw['mainStack'] as String?);
      }
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

  // ------------------------------------------------------------------ geofence

  final geofence = GeofenceTracker();
  GeofenceEvent? lastGeofence;
  static const hmnoGeofenceFile = 'GeoFence_20260708.json';

  /// Loads the bundled Spectrum HMNO CBRS geofence (541 CBSD areas).
  Future<void> _loadHmnoGeofence() async {
    if (!settings.hmnoGeofence) {
      geofence.hmno = null;
      return;
    }
    try {
      final text = await rootBundle.loadString('assets/geofence/$hmnoGeofenceFile');
      geofence.hmno = HmnoGeofence.parse(text, '20260708');
    } catch (e) {
      locationProblem = 'HMNO geofence file could not be loaded: $e';
    }
  }

  /// Every saved site with coordinates is a geofence; logs Entered / Exited.
  void _checkGeofence(Position p) {
    final events = geofence.update(sites, p.latitude, p.longitude, p.accuracy,
        speedMs: p.speed, heading: p.heading);
    for (final e in events) {
      lastGeofence = e;
      crumb('geofence ${e.summary}');
      store.addGeofence([
        e.time.toUtc().toIso8601String(),
        _local(e.time),
        e.event,
        e.source,
        e.fenceId,
        e.fenceName,
        e.radiusM.toStringAsFixed(0),
        e.distanceM.toStringAsFixed(1),
        e.edgeM.toStringAsFixed(1),
        e.source == 'Site' ? null : e.areasInside,
        e.dwellSeconds?.toStringAsFixed(0),
        e.latitude.toStringAsFixed(7),
        e.longitude.toStringAsFixed(7),
        e.accuracyM.toStringAsFixed(1),
        e.speedKmh?.toStringAsFixed(1),
        e.headingDeg?.toStringAsFixed(0),
        running ? profile.label : null,
        running ? 1 : 0,
        running ? phase : null,
        ...radio.csvValues,
      ]);
    }
  }

  // ------------------------------------------------------------------ traffic gaps

  /// User-plane interruptions seen in the traffic itself: gaps > 0.3 s between
  /// UDP download packets (ms precision, across test restarts in continuous
  /// runs), and 2+ latency probes lost in a row (TWAMP 0.1 s / ping 0.2 s
  /// resolution). Used to time Hand In / Hand Out from the data's point of view.
  final sessionGaps = <TrafficGap>[];
  double? _dlLastArrival;
  DateTime? _probeLostStart;
  int _probeLostN = 0;
  final _probeOutcomes = <(DateTime, bool)>[];

  void _trafficGap(DateTime start, DateTime end, String source, String? testType) {
    final secs = end.difference(start).inMilliseconds / 1000;
    if (secs <= 0) return;
    sessionGaps.add(TrafficGap(start, end, source));
    final r = radio;
    final p = position;
    store.addGap([
      start.toUtc().toIso8601String(),
      end.toUtc().toIso8601String(),
      _local(start),
      secs.toStringAsFixed(3),
      source,
      testType,
      running ? profile.label : null,
      r.raw['dataSimSlot'],
      r.raw['dataPlmn'],
      r.raw['cellIpv6'],
      r.raw['cellIpv4'],
      r.connection,
      r.rat,
      geofence.inHmno == null ? null : (geofence.inHmno! ? 'yes' : 'no'),
      p?.latitude.toStringAsFixed(7),
      p?.longitude.toStringAsFixed(7),
      p == null || p.speed < 0 ? null : (p.speed * 3.6).toStringAsFixed(1),
    ]);
  }

  /// Test restart after a network change (detected -> first packet), on the
  /// Traffic gaps sheet as its own source; not counted as a user-plane gap.
  void _logRestart(DateTime start, DateTime end, String testType) {
    final r = radio;
    final p = position;
    store.addGap([
      start.toUtc().toIso8601String(),
      end.toUtc().toIso8601String(),
      _local(start),
      (end.difference(start).inMilliseconds / 1000).toStringAsFixed(3),
      'Test restart (network change detected -> first packet)',
      testType,
      running ? profile.label : null,
      r.raw['dataSimSlot'],
      r.raw['dataPlmn'],
      r.raw['cellIpv6'],
      r.raw['cellIpv4'],
      r.connection,
      r.rat,
      geofence.inHmno == null ? null : (geofence.inHmno! ? 'yes' : 'no'),
      p?.latitude.toStringAsFixed(7),
      p?.longitude.toStringAsFixed(7),
      p == null || p.speed < 0 ? null : (p.speed * 3.6).toStringAsFixed(1),
    ]);
  }

  /// UDP download packets: gaps inside a test, and (continuous runs) from the
  /// last packet of a test to the first of its restart.
  void _onDlArrivals(IperfInterval iv, String testType) {
    DateTime t(double s) => DateTime.fromMicrosecondsSinceEpoch((s * 1e6).round());
    final first = iv.firstArrival;
    if (first == null) return;
    final last = _dlLastArrival;
    if (last != null && first - last > 0.3) _trafficGap(t(last), t(first), 'UDP download packets', testType);
    for (final (a, b) in iv.gaps) {
      _trafficGap(t(a), t(b), 'UDP download packets', testType);
    }
    _dlLastArrival = iv.lastArrival;
  }

  /// Latency probes, in send order, once they are settled: 2+ lost in a row = a gap
  /// from the first lost send to the next answered send.
  void _scanProbeOutcomes(DateTime cutoff, {bool all = false}) {
    final ready = _probeOutcomes.where((o) => all || o.$1.isBefore(cutoff)).toList()..sort((a, b) => a.$1.compareTo(b.$1));
    _probeOutcomes.removeWhere((o) => all || o.$1.isBefore(cutoff));
    for (final (t, ok) in ready) {
      if (!ok) {
        _probeLostStart ??= t;
        _probeLostN++;
      } else {
        if (_probeLostStart != null && _probeLostN >= 2) {
          _trafficGap(_probeLostStart!, t, latencyLabel?.startsWith('TWAMP') == true ? 'TWAMP lost' : 'Ping lost', running ? phase : null);
        }
        _probeLostStart = null;
        _probeLostN = 0;
      }
    }
  }

  // ------------------------------------------------------------------ UI freezes

  late final stalls = StallMonitor(_onStall);

  // ------------------------------------------------------------------ freeze debugging

  /// Recent app events (test start / restart, SIM switch, email, export ...),
  /// written with each UI stall so a freeze can be matched to what was going on.
  final _crumbs = <(DateTime, String)>[];

  void crumb(String what) {
    _crumbs.add((DateTime.now(), what));
    if (_crumbs.length > 60) _crumbs.removeAt(0);
  }

  String _recentEvents(DateTime from, DateTime to) => _crumbs
      .where((c) => !c.$1.isBefore(from) && !c.$1.isAfter(to))
      .map((c) => '${_local(c.$1).split(' ').last} ${c.$2}')
      .join(' | ');

  /// Files with Android's report on earlier runs that ended badly (ANR trace),
  /// attached to the next session's email and kept in runs/_app_exits.
  final _exitFiles = <File>[];

  static const _exitReasonNames = {
    1: 'exited by itself', 2: 'killed by signal', 3: 'killed for low memory', 4: 'crashed',
    5: 'crashed (native)', 6: 'App not responding (ANR)', 7: 'failed to start', 8: 'permission changed',
    9: 'killed for excessive resource use', 10: 'closed by user request', 11: 'stopped by user',
    12: 'dependency died', 13: 'other', 14: 'frozen by Android', 15: 'package state changed', 16: 'app updated',
  };

  /// Android 11+: logs how earlier runs of the app ended (ANR, crash, killed)
  /// on the UI stalls sheet, so a freeze that ended in "App isn't responding"
  /// and a close is recorded even though the app wasn't running to see it.
  Future<void> _checkPreviousExits() async {
    if (!Platform.isAndroid) return;
    try {
      final seenFile = File('${store.directory.path}/exit_seen.txt');
      final since = await seenFile.exists() ? int.tryParse((await seenFile.readAsString()).trim()) ?? 0 : 0;
      final exits = await RadioInfo.exitReasons(since);
      if (exits.isEmpty) return;
      var newest = since;
      final dir = Directory('${(await runsRoot()).path}/_app_exits');
      for (final x in exits) {
        final t = ((x['time'] as num?) ?? 0).toInt();
        if (t > newest) newest = t;
        final reason = (x['reason'] as num?)?.toInt() ?? 0;
        // Normal ends: closed from recents, app updated, stopped by user.
        if (since == 0 || const {1, 10, 11, 15, 16}.contains(reason)) continue;
        final when = DateTime.fromMillisecondsSinceEpoch(t);
        final name = _exitReasonNames[reason] ?? 'reason $reason';
        final trace = x['trace'] as String?;
        String? main;
        if (trace != null) {
          await dir.create(recursive: true);
          final f = File('${dir.path}/exit_${fileSafe(_local(when))}_${fileSafe(name)}.txt');
          await f.writeAsString(trace);
          _exitFiles.add(f);
          // The main thread's stack, the part that explains an ANR.
          final i = trace.indexOf('"main"');
          if (i >= 0) {
            final end = trace.indexOf('\n\n', i);
            main = trace.substring(i, end < 0 ? min(trace.length, i + 3000) : min(end, i + 3000)).replaceAll('\n', ' <- ');
          }
        }
        store.addStall([
          when.toUtc().toIso8601String(),
          _local(when),
          'Previous run ended: $name',
          0,
          '${x['description'] ?? ''}${trace != null ? ' (full Android trace in runs/_app_exits, attached to the next email)' : ''}',
          null, null, null, null, null, null, null, null,
          null,
          'memory at exit: PSS ${(((x['pssKb'] as num?) ?? 0) / 1024).toStringAsFixed(0)} MB, RSS ${(((x['rssKb'] as num?) ?? 0) / 1024).toStringAsFixed(0)} MB',
          main,
          (((x['rssKb'] as num?) ?? 0) / 1024).toStringAsFixed(0),
        ]);
        stalls.previousExits++;
      }
      await seenFile.writeAsString('$newest');
      await store.flush();
      notifyListeners();
    } catch (_) {}
  }

  /// Test screen button: the tester saw a freeze (logged with the last 60 s of events).
  void markFreeze() => stalls.report('Tester marked freeze', 0, 'tapped Mark freeze');

  void _onStall(Stall s) {
    final start = s.time.subtract(Duration(milliseconds: s.ms));
    final lookBack = s.kind == 'Tester marked freeze' ? const Duration(seconds: 60) : const Duration(seconds: 15);
    store.addStall([
      s.time.toUtc().toIso8601String(),
      _local(s.time),
      s.kind,
      s.ms,
      s.detail,
      running ? 1 : 0,
      running ? profile.label : null,
      running ? phase : null,
      _clients.length,
      _probe == null ? null : latencyLabel,
      logcat.running ? 1 : 0,
      radio.connection,
      radio.rat,
      _local(start),
      _recentEvents(start.subtract(lookBack), s.time),
      s.stack,
      (ProcessInfo.currentRss / 1e6).toStringAsFixed(0),
    ]);
    unawaited(store.flush()); // on disk at once, in case the app is closed or killed
    notifyListeners();
  }

  // ------------------------------------------------------------------ dual SIM (DSDS)

  final dsds = DsdsTracker();
  DsdsEvent? lastDsds;
  String? _defaultNet;
  // Cellular interface and IPs from the 4 Hz data-state poll; merged into radio rows so they are logged while on Wi-Fi too.
  Map<String, dynamic> _cellIp = const {};
  DateTime? _netChangeAt; // tests were restarted for a network change at this time
  double? lastRestartSeconds; // network change detected -> first packet of the restarted test
  DateTime? lastRestartAt;
  DateTime _lastDsdsPoll = DateTime.fromMillisecondsSinceEpoch(0);

  /// "Hand In SIM1 -> SIM2, IP already up · traffic stopped 1.8 s" for the Test screen.
  String? get lastDsdsText {
    final e = lastDsds;
    if (e == null) return null;
    if (e.event != 'SIM switch') return e.summary;
    final from = e.started.subtract(const Duration(seconds: 3));
    final to = e.time.add(const Duration(seconds: 10));
    double? up;
    for (final g in sessionGaps) {
      if (g.end.isBefore(from) || g.start.isAfter(to)) continue;
      final s = g.end.difference(g.start).inMilliseconds / 1000;
      if (up == null || s > up) up = s;
    }
    final r = lastRestartAt != null && !lastRestartAt!.isBefore(e.time.subtract(const Duration(seconds: 2)))
        ? ' (test restart ${lastRestartSeconds!.toStringAsFixed(1)} s of it)'
        : '';
    return up == null ? e.summary : '${e.summary} · traffic stopped ${up.toStringAsFixed(1)} s$r';
  }
  Timer? _dsdsTimer;
  bool _dsdsBusy = false;

  /// Android: data SIM and cellular IP 4 times a second; logs SIM switches and IP changes.
  Future<void> _pollDsds() async {
    if (_dsdsBusy) return;
    final pollAt = DateTime.now();
    if (!running && pollAt.difference(_lastDsdsPoll).inMilliseconds < 240) return;
    _lastDsdsPoll = pollAt;
    _dsdsBusy = true;
    try {
      final sw = Stopwatch()..start();
      final state = await RadioInfo.dataState();
      if (sw.elapsedMilliseconds >= 3000) {
        stalls.report('Slow native call', sw.elapsedMilliseconds, 'getDataState (SIM / IP read)');
      }
      _cellIp = {
        for (final k in const ['cellIface', 'cellIpv4', 'cellIpv6'])
          if ((state[k] ?? '').toString().isNotEmpty) k: state[k],
      };
      final events = dsds.update(state, onWifi: radio.isWifi);
      // Default network changed (new data SIM network, Wi-Fi up or down): continuous
      // streams restart on the new one instead of waiting for the old one to die.
      final net = state['defaultNet'] as String?;
      if (net != null) {
        final prev = _defaultNet;
        _defaultNet = net;
        if (prev != null && prev != net && net.isNotEmpty && running && _continuous && !_cancelSequence &&
            !events.any((e) => e.event == 'SIM switch' || e.event == 'SIM switch (late)' || e.event == 'IP change')) {
          _netChangeAt = DateTime.now();
          crumb('default network changed: restart ${_clients.length} streams');
          for (final c in List.of(_clients)) {
            _netChangeStops.add(c);
            c.abandon();
          }
        }
      }
      for (final e in events) {
        lastDsds = e;
        crumb('DSDS ${e.summary}');
        store.addDsds([
          e.time.toUtc().toIso8601String(),
          _local(e.time),
          e.event,
          e.direction,
          e.success == null ? null : (e.success! ? 'yes' : 'no'),
          e.started.toUtc().toIso8601String(),
          e.gapSeconds?.toStringAsFixed(3),
          e.onPreviousSeconds?.toStringAsFixed(1),
          e.from.slot == null ? null : 'SIM${e.from.slot}',
          e.from.carrier,
          e.from.plmn,
          e.from.iface,
          e.from.ipv4,
          e.from.ipv6,
          DsdsEvent.owner(e.from.ipv4, e.from.ipv6),
          e.to.slot == null ? null : 'SIM${e.to.slot}',
          e.to.carrier,
          e.to.plmn,
          e.to.iface,
          e.to.ipv4,
          e.to.ipv6,
          DsdsEvent.owner(e.to.ipv4, e.to.ipv6),
          e.from.dds,
          e.to.dds,
          e.to.sims,
          radio.connection,
          geofence.inHmno == null ? null : (geofence.inHmno! ? 'yes' : 'no'),
          geofence.hmnoInside.isNotEmpty ? geofence.hmnoInside.first.$1.id : geofence.hmnoNearest?.id,
          geofence.hmnoEdgeM.isFinite ? geofence.hmnoEdgeM.toStringAsFixed(0) : null,
          running ? profile.label : null,
          running ? 1 : 0,
          running ? phase : null,
          activeSite?.id,
          ...GpsCsv.values(position),
          ...radio.csvValues,
        ]);
      }
      // While Wi-Fi is the default network the test runs on Wi-Fi: a cellular interface / IP change does not affect it, so no restart.
      if (running && !radio.isWifi && events.any((e) => e.event == 'SIM switch' || e.event == 'SIM switch (late)' || e.event == 'IP change') && !_cancelSequence) {
        // The test sockets belong to the old network; restart them on the new one.
        _netChangeAt = DateTime.now();
        crumb('SIM switch / IP change: restart ${_clients.length} streams');
        for (final c in List.of(_clients)) {
          _netChangeStops.add(c);
          c.abandon();
        }
      }
      if (events.isNotEmpty) notifyListeners();
    } catch (_) {
      // Not available on this phone; ignore.
    } finally {
      _dsdsBusy = false;
    }
  }

  /// This session's DSDS statistics as a one-off CSV for the "DSDS summary" sheet.
  Future<SheetSource?> _dsdsSummarySheet(DateTime end) async {
    if (!Platform.isAndroid) return null;
    String q(Object? v) {
      final s = v?.toString() ?? '';
      return RegExp(r'[",\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    final rows = dsds.summary(end, gaps: sessionGaps);
    final b = StringBuffer()..writeln(dsds.summaryHeader.map(q).join(','));
    for (final r in rows) {
      b.writeln(r.map(q).join(','));
    }
    final f = File('${store.directory.path}/dsds_summary_session.csv');
    await f.writeAsString(b.toString());
    return SheetSource('Transition performance', f.path);
  }

  /// Hand-In / Hand-Out tables (switch time, user-plane interruption) as CSV sheets for the workbook.
  Future<List<SheetSource>> _transitionSheets() async {
    if (!Platform.isAndroid) return [];
    if (!dsds.sessionEvents.any((e) => e.event == 'SIM switch')) return [];
    String q(Object? v) {
      final s = v?.toString() ?? '';
      return RegExp(r'[",\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    final defs = <String, double? Function(DsdsEvent)>{
      'Transition table': (e) => (e.gapSeconds as num?)?.toDouble(),
      'User-plane interruption': (e) => dsds.upInterruption(e, sessionGaps),
    };
    final out = <SheetSource>[];
    for (final d in defs.entries) {
      final t = dsds.transitionTable(d.value);
      final b = StringBuffer();
      for (final r in t) {
        b.writeln(r.map(q).join(','));
      }
      final f = File('${store.directory.path}/${d.key.replaceAll(' ', '_').toLowerCase()}_session.csv');
      await f.writeAsString(b.toString());
      out.add(SheetSource(d.key, f.path));
    }
    return out;
  }

  /// Tables-only PowerPoint of the same two tables, emailed with the workbook.
  Future<File?> _transitionDeck(String prefix, DateTime start, DateTime end) async {
    if (!Platform.isAndroid) return null;
    try {
      final sw = dsds.transitionTable((e) => (e.gapSeconds as num?)?.toDouble());
      if (sw.length < 2 || sw[1].skip(1).every((c) => c.isEmpty || c == '0')) return null;
      final up = dsds.transitionTable((e) => dsds.upInterruption(e, sessionGaps));
      final env = labFor(_sessionProfile) ? 'Lab' : 'Field';
      final f = File('${store.directory.path}/${prefix}_transitions.pptx');
      await writePptx([
        PptxSlide('Dual SIM transitions', subtitle: '$env  |  ${device['make'] ?? ''} ${device['model'] ?? ''}', lines: [
          'Start: ${_local(start)}',
          'End: ${_local(end)}',
          'Profile: ${_sessionProfile.label}',
        ]),
        PptxSlide('Transition table', subtitle: 'Switch time, seconds', table: sw),
        PptxSlide('User-plane interruption',
            subtitle: 'Seconds of traffic gap around each switch (gaps over 30 s ignored)', table: up),
      ], f.path);
      return f;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------ Spectrum Wi-Fi joins

  /// Android: Spectrum Mobile Wi-Fi seen in scans, time to join it, time on it.
  final wifiJoin = WifiJoinTracker(const []);
  Timer? _wifiTimer;
  bool _wifiBusy = false;
  DateTime? _lastScanAsk;
  bool? lastScanAccepted; // false = Android throttled the scan request

  Future<void> _pollWifi() async {
    if (_wifiBusy || !settings.spectrumWifi) return;
    _wifiBusy = true;
    try {
      final now = DateTime.now();
      final every = settings.wifiScanSeconds;
      if (every > 0 && (_lastScanAsk == null || now.difference(_lastScanAsk!).inSeconds >= every)) {
        _lastScanAsk = now;
        wifiJoin.lastScanRequest = now;
        lastScanAccepted = await RadioInfo.startWifiScan();
        if (lastScanAccepted == false) crumb('Wi-Fi scan throttled');
      }
      final raw = await RadioInfo.wifiEvents();
      var changed = false;
      wifiJoin.update(
        raw,
        now: DateTime.now(),
        radioSsid: radio.wifiSsid,
        radioOnWifi: radio.isWifi,
        onOpen: (v) {
          v.contextAtHeard = _wifiContext();
          changed = true;
          return v;
        },
        onScan: (s) {
          String ap(WifiAp a) => '${a.ssid} ${a.bssid} ${a.rssi} dBm ch${a.channel}';
          final best = s.spectrum.first;
          final heardAge = best.heard == null ? null : s.time.difference(best.heard!).inMilliseconds / 1000;
          store.addWifiScan([
            s.time.toUtc().toIso8601String(),
            _local(s.time),
            s.scanNo,
            s.updated ? 'new' : 'cached',
            s.requestedByApp ? 'app' : 'phone',
            s.apsTotal,
            s.spectrum.length,
            s.spectrum.map((a) => a.ssid).toSet().join(' | '),
            best.ssid,
            best.bssid,
            best.rssi,
            best.channel,
            best.band,
            best.passpoint ? 'yes' : 'no',
            best.operator,
            heardAge?.toStringAsFixed(2),
            s.spectrum.take(12).map(ap).join('; '),
            s.connectedSsid,
            s.connectedBssid,
            wifiJoin.isSpectrum(s.connectedSsid) ? 'yes' : 'no',
            s.visit?.id,
            s.visit?.state,
            ..._wifiContext(),
          ]);
          changed = true;
        },
        onState: (e) {
          store.addWifiState([
            e.time.toUtc().toIso8601String(),
            _local(e.time),
            e.source,
            e.state,
            e.error,
            e.ssid,
            e.bssid,
            e.rssi,
            e.freq == null ? null : wifiChannel(e.freq!),
            e.freq == null ? null : wifiBand(e.freq!),
            e.spectrum ? 'yes' : 'no',
            e.visit?.id,
            e.visit?.state,
            running ? profile.label : null,
            running ? 1 : 0,
          ]);
          changed = true;
        },
        onConnected: (v) {
          v.contextAtConnect = _wifiContext();
          changed = true;
        },
        onClosed: (v) {
          _writeVisit(v, DateTime.now());
          changed = true;
        },
      );
      if (changed) notifyListeners();
    } catch (_) {
      // Not available on this phone; ignore.
    } finally {
      _wifiBusy = false;
    }
  }

  /// Profile, test, data SIM, HMNO geofence and GPS for Wi-Fi rows.
  List<Object?> _wifiContext() {
    final p = position;
    return [
      running ? profile.label : null,
      running ? 1 : 0,
      running ? phase : null,
      activeSite?.id,
      radio.connection,
      radio.raw['dataSimSlot'],
      radio.raw['dataPlmn'],
      geofence.inHmno == null ? null : (geofence.inHmno! ? 'yes' : 'no'),
      p?.latitude.toStringAsFixed(7),
      p?.longitude.toStringAsFixed(7),
      p?.accuracy.toStringAsFixed(1),
      p == null || p.speed < 0 ? null : (p.speed * 3.6).toStringAsFixed(1),
    ];
  }

  /// One row per visit on the "Spectrum Wi-Fi visits" sheet.
  void _writeVisit(SpectrumVisit v, DateTime now, {bool open = false}) {
    String? u(DateTime? t) => t?.toUtc().toIso8601String();
    String? s(double? x) => x?.toStringAsFixed(3);
    final conn = v.connectedSeconds(now);
    final mb = (v.rxBytes + v.txBytes) / 1e6;
    store.addVisit([
      v.id,
      open ? (v.connected != null ? 'Still connected at session end' : 'Still heard at session end') : v.endReason,
      v.firstSsid,
      v.connSsid,
      v.passpoint ? 'yes' : 'no',
      u(v.firstHeard),
      _local(v.firstHeard),
      u(v.firstScan),
      v.firstBssid,
      v.firstRssi,
      v.firstFreq == null ? null : wifiChannel(v.firstFreq!),
      v.firstFreq == null ? null : wifiBand(v.firstFreq!),
      v.scansBeforeConnect,
      v.bestRssi,
      u(v.assocStart),
      u(v.authStart),
      u(v.ipStart),
      u(v.connected),
      u(v.validated),
      s(v.timeToConnect),
      s(v.heardToAssoc),
      s(v.assocAuth),
      s(v.ipTime),
      s(v.toValidated),
      v.attempts,
      v.failures,
      v.lastFailure,
      v.connBssid,
      v.connRssi,
      v.connFreq == null ? null : wifiChannel(v.connFreq!),
      v.connFreq == null ? null : wifiBand(v.connFreq!),
      v.roams,
      v.bssids.length,
      u(v.disconnected ?? (open ? null : v.lastSeen)),
      conn?.toStringAsFixed(1),
      v.activeSeconds.toStringAsFixed(1),
      conn == null || conn == 0 ? null : (100 * v.activeSeconds / conn).toStringAsFixed(1),
      (v.rxBytes / 1e6).toStringAsFixed(3),
      (v.txBytes / 1e6).toStringAsFixed(3),
      v.activeSeconds == 0 ? null : (mb * 8 / v.activeSeconds).toStringAsFixed(2),
      v.atStart ? 'yes' : 'no',
      ...v.contextAtHeard.isEmpty ? List<Object?>.filled(12, null) : v.contextAtHeard,
      ...(v.contextAtConnect.isEmpty ? List<Object?>.filled(12, null) : v.contextAtConnect).skip(4),
    ]);
  }

  /// This session's Spectrum Wi-Fi statistics for the "Wi-Fi join performance" sheet.
  Future<SheetSource?> _wifiJoinSummarySheet(DateTime end) async {
    if (!Platform.isAndroid || !settings.spectrumWifi) return null;
    String q(Object? v) {
      final s = v?.toString() ?? '';
      return RegExp(r'[",\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    final b = StringBuffer()..writeln(WifiJoinTracker.summaryHeader.map(q).join(','));
    for (final r in wifiJoin.summary(end)) {
      b.writeln(r.map(q).join(','));
    }
    final f = File('${store.directory.path}/wifi_join_summary_session.csv');
    await f.writeAsString(b.toString());
    return SheetSource('Wi-Fi join performance', f.path);
  }

  // ------------------------------------------------------------------ sites

  /// [latitude]/[longitude] typed in; otherwise the current GPS position.
  Future<void> addSite({required String id, required String name, String notes = '',
      double radiusM = 100, double? latitude, double? longitude}) async {
    final p = position;
    final typed = latitude != null && longitude != null;
    final site = Site(
      id: id.trim(),
      name: name.trim(),
      notes: notes.trim(),
      latitude: typed ? latitude : p?.latitude,
      longitude: typed ? longitude : p?.longitude,
      accuracy: typed ? null : p?.accuracy,
      radiusM: radiusM,
    );
    sites.removeWhere((s) => s.id == site.id);
    sites.insert(0, site);
    activeSite = site;
    await store.saveSites(sites);
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setSiteRadius(Site site, double radiusM) async {
    final i = sites.indexWhere((s) => s.id == site.id);
    if (i < 0) return;
    final updated = Site(
      id: site.id,
      name: site.name,
      notes: site.notes,
      latitude: site.latitude,
      longitude: site.longitude,
      accuracy: site.accuracy,
      radiusM: radiusM,
      created: site.created,
    );
    sites[i] = updated;
    if (activeSite?.id == site.id) activeSite = updated;
    await store.saveSites(sites);
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
    final reloadFence = s.hmnoGeofence != settings.hmnoGeofence;
    settings = s;
    wifiJoin.patterns = WifiJoinTracker.parsePatterns(s.spectrumSsids);
    if (reloadFence) await _loadHmnoGeofence();
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
  /// the upstream uses the next port (e.g. 5201 on Clouvider Dallas). Files are named Lab_..._lab_...
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

  /// UDP stream. Duration 0 = run until Stop: each direction restarts by
  /// itself after a drop or network change, and "both" runs download and
  /// upload at the same time (upload on the next port, like the Lab profile).
  Future<void> runUdpStream(UdpDirection dir) {
    final continuous = settings.udpDuration == 0;
    final up = _udpConfig(IperfDirection.upload);
    return _runSequence([
      if (dir != UdpDirection.upload) _udpConfig(IperfDirection.download),
      if (dir != UdpDirection.download)
        continuous && dir == UdpDirection.both ? _onServer(up, up.host, up.port + 1) : up,
    ]);
  }

  /// All tests of the session run at once and until Stop (Lab profile, or UDP with duration 0).
  bool _continuous = false;
  /// Download and upload at the same time; the upload owns the secondary display.
  bool _duplex = false;

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
  static const networkChangedText = 'Network changed (data SIM switch / new IP); test restarted';

  /// Clients stopped because the data network changed under them.
  final _netChangeStops = <BackgroundIperfClient>{};

  /// A test with no data for this long is ended as failed ("No data for 15 s").
  static const noDataSeconds = 15;

  /// True from Stop until the test has wound down (UI shows "Stopping…").
  bool get stopping => running && _cancelSequence;

  void stop() {
    crumb('Stop pressed');
    _cancelSequence = true;
    waitingText = 'Stopping…';
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
    _continuous = p == TestProfile.lab || configs.every((c) => c.protocol == IperfProtocol.udp && c.durationSeconds == 0);
    _duplex = _continuous && configs.length > 1;
    _keepGoing = p == TestProfile.drive || _continuous || settings.repeatUntilStopped;
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
        if (_continuous) {
          // Each stream at once, each restarting by itself after a drop.
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
  bool get duplex => _duplex;

  Future<void> _streamUntilStopped(IperfConfig cfg) async {
    var fails = 0;
    var quickRestarts = 0;
    while (!_cancelSequence) {
      final before = recent.isEmpty ? null : recent.first;
      await _runOne(cfg);
      if (_cancelSequence) break;
      final last = recent.isNotEmpty && !identical(recent.first, before) ? recent.first : null;
      final netChange = last?.error?.startsWith(networkChangedText) ?? false;
      final ok = last != null && (last.error == null || netChange);
      fails = ok ? 0 : fails + 1;
      // After a network change (data SIM switch / new IP) restart at once on the new network.
      // Several in a row (no network at all yet): 2 s apart, so it doesn't spin.
      quickRestarts = netChange ? quickRestarts + 1 : 0;
      final wait = netChange ? (quickRestarts > 2 ? 2 : 0) : min(15, 3 * (1 << min(max(fails - 1, 0), 3)));
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
    final active = _activeByTest[base.label] ?? (_duplex ? null : _activeServer);
    if (settings.rotateServers && active != null && (!udp || (publicServerFor(active.$1)?.udp ?? true))) {
      cfg = _onServer(base, active.$1, active.$2);
    }
    final tried = <String>{};
    var sameRetries = 0;
    for (var attempt = 0;; attempt++) {
      tried.add('${cfg.host}:${cfg.port}');
      final failed = await _runAttempt(cfg, skipSetupFailure: settings.rotateServers);
      waitingText = null;
      if (failed == null || _cancelSequence) return;
      // Just after a network change the server may still hold the old (dead) test and answer busy:
      // wait a moment and retry the same server before hopping to another one.
      if (sameRetries < 2 && _netChangeAt != null && failed.toLowerCase().contains('busy')) {
        sameRetries++;
        waitingText = '${cfg.host}:${cfg.port} still busy after the network change, retrying ($sameRetries/2)';
        notifyListeners();
        await Future.delayed(const Duration(seconds: 3));
        if (_cancelSequence) return;
        continue;
      }
      final next = attempt < 7 + sameRetries && !_cancelSequence
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
    final secondary = _duplex && cfg.direction == IperfDirection.upload;
    if (secondary) {
      upMbps = 0;
    } else {
      phase = _duplex ? 'UDP down + up' : cfg.label;
      currentMbps = 0;
      noDataNow = 0;
      elapsed = 0;
      plannedSeconds = cfg.durationSeconds;
      liveSeries.clear();
    }
    final samples = <double>[];
    notifyListeners();

    final window = _TestWindow(testId, cfg.label, start);
    _windows.add(window);

    final client = BackgroundIperfClient(cfg);
    crumb('start ${cfg.label} ${cfg.host}:${cfg.port}');
    _client = client;
    _clients.add(client);
    if (!_continuous) _dlLastArrival = null; // separate tests: don't bridge the pause between them
    // A test that moves no data for [noDataSeconds] in a row is ended (the
    // connection is dead); it is recorded as failed with its samples.
    var zeroRun = 0;
    var noDataStop = false;
    final sub = client.intervals.listen((iv) {
      if (samples.isEmpty) waitingText = null; // clear "switching to ..." once data flows
      samples.add(iv.mbps);
      if (cfg.direction == IperfDirection.download && cfg.protocol == IperfProtocol.udp) _onDlArrivals(iv, cfg.label);
      zeroRun = iv.mbps < 0.01 ? zeroRun + 1 : 0;
      if (!secondary) {
        noDataNow = zeroRun;
        if (iv.mbps >= 0.01) lastGoodMbps = iv.mbps;
      }
      final changedAt = _netChangeAt;
      if (changedAt != null && iv.mbps >= 0.01) {
        // First data after a restart for a network change: how long the restart took.
        final first = iv.firstArrival == null
            ? DateTime.now()
            : DateTime.fromMicrosecondsSinceEpoch((iv.firstArrival! * 1e6).round());
        _netChangeAt = null;
        lastRestartSeconds = max(0, first.difference(changedAt).inMilliseconds / 1000);
        lastRestartAt = first;
        _logRestart(changedAt, first, cfg.label);
      }
      if (zeroRun >= noDataSeconds && !noDataStop && !_cancelSequence) {
        noDataStop = true;
        client.stop();
      }
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
      final netChange = _netChangeStops.remove(client);
      if (r.stoppedByUser && samples.isEmpty && !netChange) setupError = 'stopped'; // Stop before any data
      final noData = netChange
          ? networkChangedText
          : noDataStop
              ? 'No data for $noDataSeconds s; test ended'
              : null;
      if (noData != null) lastError = '${cfg.label}: $noData';
      record = TestRecord(
        testId: testId,
        type: cfg.label,
        start: start,
        durationSeconds: r.durationSeconds,
        mbps: r.mbps,
        jitterMs: r.jitterMs,
        lost: r.lostPackets,
        total: r.totalPackets,
        stoppedByUser: r.stoppedByUser && !noDataStop && !netChange,
        error: noData,
        minMbps: stats?.min,
        maxMbps: stats?.max,
        medianMbps: stats?.median,
        p10Mbps: stats?.p10,
        p90Mbps: stats?.p90,
      );
      if (noDataStop && !netChange) {
        _failStreak++;
      } else {
        _failStreak = 0;
        if (_keepGoing) lastError = null;
      }
    } catch (e) {
      final msg = e is IperfException
          ? e.message
          : e is SocketException
              ? 'Network error: ${e.osError?.message ?? e.message}'
              : e.toString();
      // "Network is unreachable" in a continuous run = the network under the test
      // went away (data SIM switch, Wi-Fi left): restart at once like a network change.
      final unreachable = _continuous && !_cancelSequence && RegExp(r'unreachable|errno = 101').hasMatch(msg);
      if (unreachable) _netChangeAt ??= DateTime.now();
      final netChangeErr = _netChangeStops.remove(client) || unreachable;
      final stoppedMidTest = samples.isNotEmpty && (_cancelSequence || noDataStop || netChangeErr);
      if (samples.isEmpty && _cancelSequence && !netChangeErr) {
        setupError = 'stopped'; // you pressed Stop before any data: not a result
      } else if (skipSetupFailure && samples.isEmpty && !netChangeErr) {
        setupError = msg;
      } else if (!stoppedMidTest && !netChangeErr) {
        lastError = '${cfg.label}: $msg';
      }
      final stats = SpeedStats.of(samples);
      record = stoppedMidTest
          // Stopped, and the server didn't send its final numbers within 3 s:
          // keep the test, with throughput from the per-second samples.
          ? TestRecord(
              testId: testId,
              type: cfg.label,
              start: start,
              durationSeconds: DateTime.now().difference(start).inMilliseconds / 1000,
              mbps: samples.reduce((a, b) => a + b) / samples.length,
              stoppedByUser: !noDataStop && !netChangeErr,
              error: netChangeErr
                  ? networkChangedText
                  : noDataStop
                      ? 'No data for $noDataSeconds s; test ended'
                      : null,
              minMbps: stats?.min,
              maxMbps: stats?.max,
              medianMbps: stats?.median,
              p10Mbps: stats?.p10,
              p90Mbps: stats?.p90,
            )
          : TestRecord(
              testId: testId,
              type: cfg.label,
              start: start,
              durationSeconds: DateTime.now().difference(start).inMilliseconds / 1000,
              error: netChangeErr ? networkChangedText : msg,
            );
      if (setupError != null || stoppedMidTest || netChangeErr) {
        // Not a failure: switching server, the user stopped, or the network changed.
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
    if (probe != null && !_cancelSequence) await Future.delayed(probe.timeout);
    _windows.remove(window);
    record = record.withLatency(window.acc.isEmpty ? null : window.acc.stats(), probe == null ? null : latencyLabel,
        apInfo: startRadio.apSummary);

    recent.insert(0, record);
    if (recent.length > 50) recent.removeLast();
    crumb('end ${record.type}: ${record.error ?? '${record.mbps?.toStringAsFixed(1) ?? '-'} Mbps'}');

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
    if (_sessionStart != null) _probeOutcomes.add((r.sentAt, r.rttMs != null));
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
    _scanProbeOutcomes(DateTime.fromMillisecondsSinceEpoch(cutoff * 1000), all: all);
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
    await probe.stop(quick: _cancelSequence); // waits for in-flight packets, reports the rest lost
    await _probeSub?.cancel();
    _probeSub = null;
    _latencyFlushTimer?.cancel();
    _latencyFlushTimer = null;
    _flushLatency(all: true);
    _probe = null;
    await store.flush();
  }

  // ------------------------------------------------------------------ email


  /// File names say Lab only for the Lab profile; everything else is Field.
  bool labFor(TestProfile p) =>
      settings.testEnvironment == 'lab' || (settings.testEnvironment != 'field' && p == TestProfile.lab);

  bool get inLab => labFor(profile);

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
  /// [export]: a Data-tab export of all logs, named ..._all_... instead of a profile.
  String fileName([TestProfile? p, DateTime? at, bool export = false]) {
    final prof = p ?? profile;
    final lab = !export && labFor(prof);
    final profileWord = export ? 'all' : switch (prof) {
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

  /// Data-tab export of everything logged: <env>_..._all_..._date-time, where
  /// <env> follows the tests in it: Lab (all Lab profile), Field (none), Mixed (both).
  String get devicePrefix => fileName(null, null, true);

  Future<String> exportPrefix() async {
    final env = await store.testEnvironments();
    final name = fileName(null, null, true);
    // Settings > File names can force Field or Lab (for example a Manual run in a lab chamber).
    if (settings.testEnvironment == 'lab') return 'Lab${name.substring('Field'.length)}';
    if (settings.testEnvironment == 'field') return name;
    if (env.lab && !env.field) return 'Lab${name.substring('Field'.length)}';
    if (env.lab && env.field) return 'Mixed${name.substring('Field'.length)}';
    return name;
  }

  String? get emailStatus => mailer.lastStatus;
  int get emailPending => mailer.pendingCount();

  Future<void> _beginSession(TestProfile p) async {
    _sessionStart = DateTime.now();
    _sessionProfile = p;
    _activeServer = null;
    _activeByTest.clear();
    dsds.startSession(_sessionStart!);
    wifiJoin.startSession(_sessionStart!);
    lastGoodMbps = null;
    noDataNow = 0;
    sessionGaps.clear();
    _dlLastArrival = null;
    _probeLostStart = null;
    _probeLostN = 0;
    _probeOutcomes.clear();
    stalls.resetSession();
    _sessionOffsets = await mailer.markStart();
    if (kDebugApp && settings.recordLogcat) {
      await logcat.start(fileName(p, _sessionStart), partMb: settings.logcatPartMb, parts: settings.logcatParts);
      notifyListeners();
    }
  }

  Future<void> _endSession() async {
    crumb('session end: building workbook');
    final start = _sessionStart;
    final offsets = _sessionOffsets;
    _sessionStart = null;
    _sessionOffsets = null;
    // A running screen recording ends with the session so the MP4 is complete.
    await ScreenRecorder.instance.stopIfRecording();
    // Debug app: logcat parts stay in the logcat folder (Data > Share logcat)
    // unless they are emailed with the session below.
    final logcatFiles = logcat.running ? await logcat.stop() : <File>[];
    if (start == null || offsets == null) return;
    final end = DateTime.now();
    final prefix = fileName(_sessionProfile, start);
    final recordings = await ScreenRecorder.instance.takeRecordings(start, end);
    final tests = recent.where((r) => !r.start.isBefore(start)).toList().reversed.toList();
    String two(int n) => n.toString().padLeft(2, '0');
    final dur = end.difference(start);
    final b = StringBuffer()
      ..writeln('$kAppName results')
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
      ..writeln('Tests, Speed (per second), Latency (per second), GPS track, Server failures, Geofence,')
      ..writeln('DSDS transitions and Transition performance (Hand In / Hand Out), for this session only.');
    b.writeln('UI freezes: ${stalls.count == 0 ? 'none' : '${stalls.count} (worst ${stalls.worstMs} ms), see the UI stalls sheet'}');
    b.writeln('Geofence: ${lastGeofence == null ? 'no crossings yet' : 'last ${lastGeofence!.summary} at ${_local(lastGeofence!.time)}'}');
    if (recordings.isNotEmpty) {
      b.writeln('Screen recording: ${recordings.map((f) => '${f.uri.pathSegments.last} (${(f.lengthSync() / 1048576).toStringAsFixed(1)} MB)').join(', ')}. '
          'Saved in the run folder, not emailed (too large): Export this run, or adb pull the run folder.');
    }
    if (logcatFiles.isNotEmpty) {
      final off = start.timeZoneOffset;
      b.writeln('Also attached: logcat for this session (${logcatFiles.length} gzip file${logcatFiles.length == 1 ? '' : 's'}, '
          'logcat -b all -v time; times are phone local time, UTC${off.isNegative ? '-' : '+'}${off.inHours.abs().toString().padLeft(2, '0')}:00). '
          'Parts over the email size limit stay on the phone: '
          'adb pull /sdcard/Android/data/com.example.analyticsdebug/files/logcat');
    }
    final dsdsSheet = await _dsdsSummarySheet(end);
    final joinSheet = await _wifiJoinSummarySheet(end);
    final tableSheets = await _transitionSheets();
    final deck = await _transitionDeck(prefix, start, end);
    if (Platform.isAndroid && settings.spectrumWifi) {
      final vs = wifiJoin.visitsForSummary();
      final joined = vs.where((v) => v.timeToConnect != null).map((v) => v.timeToConnect!).toList()..sort();
      b.writeln('Spectrum Wi-Fi: ${wifiJoin.sessionScansWithSpectrum} of ${wifiJoin.sessionScans} scans heard it; '
          '${vs.length} visits, ${joined.length} joined'
          '${joined.isEmpty ? '' : ' (time to connect median ${joined[joined.length ~/ 2].toStringAsFixed(1)} s)'}; '
          'sheets Wi-Fi scans, Spectrum Wi-Fi visits, Wi-Fi join performance.');
      if (wifiJoin.visit != null) _writeVisit(wifiJoin.visit!, end, open: true);
      await store.flush();
    }
    if (deck != null) {
      b.writeln('Also attached: ${deck.uri.pathSegments.last}, the Transition table and User-plane interruption tables as slides (sheets of the same names in the workbook).');
    }
    final dsdsCounts = <String, int>{};
    for (final e in dsds.sessionEvents) {
      final k = e.direction.isEmpty ? e.event : '${e.direction}${e.success == false ? ' failed' : ''}';
      dsdsCounts[k] = (dsdsCounts[k] ?? 0) + 1;
    }
    if (Platform.isAndroid) {
      b.writeln('Dual SIM data: ${dsdsCounts.isEmpty ? 'no SIM switches or IP changes' : dsdsCounts.entries.map((x) => '${x.value} ${x.key}').join(', ')} '
          '(sheets DSDS transitions and Transition performance). SIMs: ${dsds.current?.sims ?? '-'}');
    }
    try {
      final runDir = Directory('${(await runsRoot()).path}/$prefix');
      final queued = await mailer.queueSession(
        runDir: runDir,
        email: settings.emailResults,
        offsets: offsets,
        filePrefix: prefix,
        subject: '$kAppName: $prefix',
        body: b.toString(),
        extraFiles: [...logcatFiles, ..._exitFiles, if (deck != null) deck],
        extraSheets: [if (dsdsSheet != null) dsdsSheet, if (joinSheet != null) joinSheet, ...tableSheets],
      );
      if (queued) {
        _exitFiles.clear(); // ANR traces went out with this session
        if (deck != null) {
          try {
            await deck.delete(); // the copy is in the run folder and the outbox
          } catch (_) {}
        }
        // logcat's session_info.txt belongs with the run too.
        final info = File('${logcat.sessionDir?.path ?? ''}/session_info.txt');
        if (logcatFiles.isNotEmpty && await info.exists()) await info.copy('${runDir.path}/logcat_session_info.txt');
        // ScreenRec move: screen recordings made during this session go into the run folder.
        for (final rec in recordings) {
          try {
            await rec.copy('${runDir.path}/${rec.uri.pathSegments.last}');
            await rec.delete();
          } catch (_) {}
        }
        lastRun = runDir;
        notifyListeners();
        if (settings.emailResults) unawaited(sendPendingEmail());
      }
    } catch (e) {
      mailer.lastStatus = 'Could not prepare email: $e';
      notifyListeners();
    }
  }

  /// One folder per test run: workbook, summary, logcat (debug app). On Android
  /// in the app's external folder so it can be pulled with adb:
  ///   /sdcard/Android/data/<package>/files/runs/<run name>/
  Future<Directory> runsRoot() async {
    Directory? ext;
    if (Platform.isAndroid) {
      try {
        ext = await getExternalStorageDirectory();
      } catch (_) {}
    }
    final d = Directory('${(ext ?? store.directory).path}/runs');
    await d.create(recursive: true);
    return d;
  }

  /// Folder of the last finished test run (Test screen: Export this run).
  Directory? lastRun;

  Future<List<Directory>> testRuns() async {
    final root = await runsRoot();
    final dirs = (await root.list().toList()).whereType<Directory>().toList();
    dirs.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return dirs;
  }

  Future<void> sendPendingEmail() async {
    if (mailer.pendingCount() == 0) return;
    crumb('sending ${mailer.pendingCount()} email(s)');
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
        // Back-to-back: still on Wi-Fi with internet and nothing queued: queue another round.
        // The minimum gap below decides when it actually starts.
        if (settings.walkBackToBack && r.isWifi && r.internetOk && pendingSince == null) {
          pendingSince = now.subtract(Duration(seconds: settings.walkSettleSeconds));
          reason = 'Repeat on Wi-Fi';
        }
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
              // Walk tests measure Wi-Fi: skip (and log) if the phone is on cellular now,
              // or the Wi-Fi has no internet (Android could not validate it, e.g. captive
              // portal or Passpoint sign-in that failed).
              await _pollRadio();
              if (!radio.isWifi || !radio.internetOk) {
                store.addFailure([
                  DateTime.now().toUtc().toIso8601String(),
                  _local(DateTime.now()),
                  configs[i].label,
                  profile.label,
                  configs[i].host,
                  configs[i].port,
                  radio.isWifi
                      ? 'Skipped: Wi-Fi ${radio.wifiSsid ?? ''} has no internet (Android could not validate it)'
                      : 'Skipped: phone is not on Wi-Fi (${radio.connection})',
                  null,
                  null,
                  ...radio.csvValues,
                ]);
                continue;
              }
              await _runOne(configs[i]);
            }
            lastTest = DateTime.now();
            phase = 'Walk test';
            await store.flush();
            continue;
          }
          waitingText = settled
              ? (reason == 'Repeat on Wi-Fi'
                  ? 'Walk: on Wi-Fi ${r.wifiSsid ?? ''}, next speed test in ${gapLeft}s'
                  : 'Wi-Fi joined, next speed test in ${gapLeft}s')
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
    _dsdsTimer?.cancel();
    _wifiTimer?.cancel();
    _trackTimer?.cancel();
    _flushTimer?.cancel();
    stalls.stop();
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
