import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../models.dart';
import 'xlsx_writer.dart';

/// Appends rows to CSV files in the app's documents folder.
///
/// Files:
///  - tests.csv      one row per test (summary)
///  - samples.csv    one row per second while a test runs
///  - gps_track.csv  GPS + radio every second while the app is open
///  - twamp.csv      latency (TWAMP or ping) per second while a test runs
///  - sites.csv      saved sites
class DataStore {
  late Directory _dir;
  final Map<String, StringBuffer> _buffers = {};
  Future<void> _flushChain = Future.value();

  static const testsFile = 'tests.csv';
  static const samplesFile = 'samples.csv';
  static const trackFile = 'gps_track.csv';
  static const latencyFile = 'twamp.csv';
  static const failuresFile = 'server_failures.csv';
  static const geofenceFile = 'geofence.csv';
  static const dsdsFile = 'dsds_transitions.csv';
  static const stallsFile = 'ui_stalls.csv';
  static const gapsFile = 'traffic_gaps.csv';
  static const wifiScansFile = 'wifi_scans.csv';
  static const wifiStatesFile = 'wifi_states.csv';
  static const visitsFile = 'spectrum_wifi_visits.csv';
  static const sitesFile = 'sites.csv';
  static const sitesJson = 'sites.json';
  static const settingsJson = 'settings.json';

  static final testsHeader = <String>[
    'test_id', 'test_type', 'start_utc', 'start_local', 'duration_s', 'throughput_mbps',
    'min_mbps', 'max_mbps', 'median_mbps', 'p10_mbps', 'p90_mbps', 'jitter_ms',
    'lost_packets', 'total_packets', 'loss_pct', 'stopped_by_user', 'error',
    'server', 'port', 'parallel_streams', 'udp_target_mbps', 'udp_packet_bytes',
    'site_id', 'site_name', 'device_platform', 'profile', 'trigger',
    'latency_target', 'rtt_avg_ms', 'rtt_min_ms', 'rtt_max_ms', 'rtt_median_ms', 'rtt_jitter_ms',
    'rtt_loss_pct', 'rtt_packets',
    ...GpsCsv.header,
    ...RadioSnapshot.csvHeader,
  ];

  static final geofenceHeader = <String>[
    'time_utc', 'time_local', 'event', 'source', 'fence_id', 'fence_name', 'radius_m', 'distance_m',
    'distance_to_edge_m', 'hmno_areas_inside', 'time_inside_s',
    'latitude', 'longitude', 'gps_accuracy_m', 'speed_kmh', 'heading_deg', 'profile', 'test_running', 'test_type',
    ...RadioSnapshot.csvHeader,
  ];

  static final dsdsHeader = <String>[
    'time_utc', 'time_local', 'event', 'direction', 'success', 'started_utc', 'switch_time_s', 'time_on_previous_s',
    'from_sim', 'from_carrier', 'from_plmn', 'from_iface', 'from_ipv4', 'from_ipv6', 'from_ip_owner',
    'to_sim', 'to_carrier', 'to_plmn', 'to_iface', 'to_ipv4', 'to_ipv6', 'to_ip_owner',
    'sims', 'default_connection', 'in_hmno_geofence', 'hmno_area', 'hmno_edge_m',
    'profile', 'test_running', 'test_type', 'site_id',
    ...GpsCsv.header,
    ...RadioSnapshot.csvHeader,
  ];

  static final gapsHeader = <String>[
    'start_utc', 'end_utc', 'start_local', 'duration_s', 'source', 'test_type', 'profile',
    'data_sim_slot', 'data_plmn', 'cell_ipv6', 'cell_ipv4', 'connection', 'rat', 'in_hmno_geofence',
    'latitude', 'longitude', 'speed_kmh',
  ];

  static final wifiScansHeader = <String>[
    'time_utc', 'time_local', 'scan_no', 'results', 'scan_by', 'aps_in_scan', 'spectrum_aps', 'spectrum_ssids',
    'best_ssid', 'best_bssid', 'best_rssi_dbm', 'best_channel', 'best_band', 'best_passpoint', 'best_operator',
    'best_heard_age_s', 'spectrum_aps_list', 'connected_ssid', 'connected_bssid', 'connected_to_spectrum',
    'visit_id', 'visit_state',
    'profile', 'test_running', 'test_type', 'site_id', 'default_connection', 'data_sim_slot', 'data_plmn', 'in_hmno_geofence', 'latitude', 'longitude', 'gps_accuracy_m', 'speed_kmh',
  ];

  static final wifiStatesHeader = <String>[
    'time_utc', 'time_local', 'source', 'state', 'error', 'ssid', 'bssid', 'rssi_dbm', 'channel', 'band',
    'spectrum', 'visit_id', 'visit_state', 'profile', 'test_running',
  ];

  static final visitsHeader = <String>[
    'visit_id', 'end_reason', 'first_ssid', 'connected_ssid', 'passpoint',
    'first_heard_utc', 'first_heard_local', 'first_scan_utc', 'first_bssid', 'first_rssi_dbm', 'first_channel', 'first_band',
    'scans_before_connect', 'best_rssi_before_connect',
    'join_start_utc', 'auth_start_utc', 'ip_request_utc', 'connected_utc', 'validated_utc',
    'time_to_connect_s', 'heard_to_join_start_s', 'assoc_auth_s', 'ip_dhcp_s', 'connected_to_validated_s',
    'join_attempts', 'failed_attempts', 'last_failure',
    'connected_bssid', 'connected_rssi_dbm', 'connected_channel', 'connected_band', 'roams', 'bssids_used',
    'left_utc', 'connected_time_s', 'traffic_time_s', 'traffic_pct', 'down_mb', 'up_mb', 'avg_mbps_while_sending',
    'connected_at_start',
    'profile', 'test_running', 'test_type', 'site_id', 'default_connection', 'data_sim_slot', 'data_plmn', 'in_hmno_geofence',
    'latitude', 'longitude', 'gps_accuracy_m', 'speed_kmh',
    'connect_default_connection', 'connect_data_sim_slot', 'connect_data_plmn', 'connect_in_hmno_geofence',
    'connect_latitude', 'connect_longitude', 'connect_gps_accuracy_m', 'connect_speed_kmh',
  ];

  static final stallsHeader = <String>[
    'time_utc', 'time_local', 'kind', 'duration_ms', 'detail', 'test_running', 'profile', 'test_type',
    'iperf_streams', 'latency', 'logcat_running', 'connection', 'rat',
    'freeze_start_local', 'recent_events', 'android_main_stack', 'app_memory_mb',
  ];

  static final failuresHeader = <String>[
    'time_utc', 'time_local', 'test_type', 'profile', 'server', 'port', 'error', 'switched_to', 'switched_port',
    ...RadioSnapshot.csvHeader,
  ];

  static final latencyHeader = <String>[
    'time_utc', 'time_local', 'test_id', 'test_type', 'method', 'target',
    'sent', 'received', 'lost', 'loss_pct', 'rtt_min_ms', 'rtt_avg_ms', 'rtt_max_ms', 'rtt_median_ms',
    'jitter_ms', 'outbound_avg_ms', 'inbound_avg_ms', 'site_id', 'profile',
    ...GpsCsv.header,
    ...RadioSnapshot.csvHeader,
  ];

  static final samplesHeader = <String>[
    'test_id', 'test_type', 'time_utc', 'time_local', 'elapsed_s', 'interval_mbps', 'site_id', 'profile',
    ...GpsCsv.header,
    ...RadioSnapshot.csvHeader,
  ];

  static final trackHeader = <String>[
    'time_utc', 'time_local', 'site_id', 'test_running', 'profile',
    ...GpsCsv.header,
    ...RadioSnapshot.csvHeader,
  ];

  static final sitesHeader = <String>[
    'site_id', 'site_name', 'notes', 'latitude', 'longitude', 'gps_accuracy_m', 'created_utc', 'geofence_radius_m',
  ];

  Directory get directory => _dir;

  Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    _dir = Directory('${docs.path}/wifi_analytics');
    await _dir.create(recursive: true);
  }

  File file(String name) => File('${_dir.path}/$name');

  void _append(String name, List<String> header, List<Object?> row) {
    var buf = _buffers[name];
    if (buf == null) {
      // First write this run: rotate an old-format file, start a new one with a header.
      final f = file(name);
      _rotateIfHeaderChanged(f, header);
      final isNew = !f.existsSync() || f.lengthSync() == 0;
      buf = _buffers[name] = StringBuffer();
      if (isNew) buf.writeln(_csvLine(header));
    }
    buf.writeln(_csvLine(row));
  }

  /// If a log was written by an older app version with different columns,
  /// keep it as e.g. tests_old_20261018-070000.csv and start a fresh file.
  void _rotateIfHeaderChanged(File f, List<String> header) {
    if (!f.existsSync() || f.lengthSync() == 0) return;
    try {
      final raf = f.openSync();
      final List<int> head;
      try {
        head = raf.readSync(64 * 1024);
      } finally {
        raf.closeSync();
      }
      final text = utf8.decode(head, allowMalformed: true);
      final existing = text.split('\n').first.trim();
      if (existing == _csvLine(header)) return;
      final t = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final stamp = '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}';
      final base = f.path.endsWith('.csv') ? f.path.substring(0, f.path.length - 4) : f.path;
      f.renameSync('${base}_old_$stamp.csv');
    } catch (_) {
      // If anything goes wrong, keep appending to the existing file.
    }
  }

  void addTest(List<Object?> row) => _append(testsFile, testsHeader, row);
  void addSample(List<Object?> row) => _append(samplesFile, samplesHeader, row);
  void addTrack(List<Object?> row) => _append(trackFile, trackHeader, row);
  void addLatency(List<Object?> row) => _append(latencyFile, latencyHeader, row);
  void addFailure(List<Object?> row) => _append(failuresFile, failuresHeader, row);
  void addGeofence(List<Object?> row) => _append(geofenceFile, geofenceHeader, row);
  void addDsds(List<Object?> row) => _append(dsdsFile, dsdsHeader, row);
  void addStall(List<Object?> row) => _append(stallsFile, stallsHeader, row);
  void addGap(List<Object?> row) => _append(gapsFile, gapsHeader, row);
  void addWifiScan(List<Object?> row) => _append(wifiScansFile, wifiScansHeader, row);
  void addWifiState(List<Object?> row) => _append(wifiStatesFile, wifiStatesHeader, row);
  void addVisit(List<Object?> row) => _append(visitsFile, visitsHeader, row);

  /// Appends buffered rows to the files. Flushes run one after another, and
  /// new rows go into the buffer meanwhile, so writes never collide (the old
  /// IOSink threw "StreamSink is bound to a stream" when a row arrived during
  /// a flush, losing that row).
  Future<void> flush() {
    _flushChain = _flushChain.then((_) async {
      for (final e in _buffers.entries) {
        if (e.value.isEmpty) continue;
        final text = e.value.toString();
        e.value.clear();
        await file(e.key).writeAsString(text, mode: FileMode.append);
      }
    }).catchError((Object _) {});
    return _flushChain;
  }

  Future<void> _closeAll() async {
    await flush();
    _buffers.clear();
  }

  /// Rewrites sites.csv / sites.json from the full list.
  Future<void> saveSites(List<Site> sites) async {
    await file(sitesJson).writeAsString(jsonEncode(sites.map((s) => s.toJson()).toList()));
    final b = StringBuffer()..writeln(_csvLine(sitesHeader));
    for (final s in sites) {
      b.writeln(_csvLine([
        s.id, s.name, s.notes, s.latitude?.toStringAsFixed(7), s.longitude?.toStringAsFixed(7),
        s.accuracy?.toStringAsFixed(1), s.created.toUtc().toIso8601String(), s.radiusM.toStringAsFixed(0),
      ]));
    }
    await file(sitesFile).writeAsString(b.toString());
  }

  Future<List<Site>> loadSites() async {
    try {
      final f = file(sitesJson);
      if (!await f.exists()) return [];
      final list = jsonDecode(await f.readAsString()) as List;
      return list.map((e) => Site.fromJson((e as Map).cast<String, dynamic>())).toList();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> loadSettings() async {
    try {
      final f = file(settingsJson);
      if (!await f.exists()) return {};
      return (jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  Future<void> saveSettings(Map<String, dynamic> settings) =>
      file(settingsJson).writeAsString(jsonEncode(settings));

  /// Gzip-compressed copies of the logs for sharing, named
  /// `<prefix>_<file>.csv.gz` (CSV shrinks about 10x, so a day of logs fits
  /// under email size limits). Sites stay plain CSV.
  Future<List<File>> exportCompressed(String prefix) async {
    final files = await exportFiles();
    final out = Directory('${_dir.path}/export');
    if (await out.exists()) await out.delete(recursive: true);
    await out.create(recursive: true);
    final result = <File>[];
    for (final f in files) {
      final name = f.uri.pathSegments.last;
      if (name == sitesFile) {
        result.add(await f.copy('${out.path}/${prefix}_$name'));
        continue;
      }
      final src = f.path;
      final dst = '${out.path}/${prefix}_$name.gz';
      await Isolate.run(() => File(src).openRead().transform(gzip.encoder).pipe(File(dst).openWrite()));
      result.add(File(dst));
    }
    return result;
  }

  /// CSV files that currently exist (for sharing).
  Future<List<File>> exportFiles() async {
    await flush();
    final out = <File>[];
    for (final name in [testsFile, samplesFile, latencyFile, trackFile, failuresFile, geofenceFile, dsdsFile, stallsFile, gapsFile, visitsFile, wifiScansFile, wifiStatesFile, sitesFile]) {
      final f = file(name);
      if (await f.exists() && await f.length() > 0) out.add(f);
    }
    return out;
  }

  /// Whether tests.csv has Lab-profile tests and/or other (field) tests.
  Future<({bool lab, bool field})> testEnvironments() async {
    await flush();
    final path = file(testsFile).path;
    return Isolate.run(() {
      final f = File(path);
      if (!f.existsSync()) return (lab: false, field: false);
      final lines = f.readAsLinesSync();
      if (lines.length < 2) return (lab: false, field: false);
      final col = lines.first.split(',').indexOf('profile');
      var lab = false, field = false;
      for (final l in lines.skip(1)) {
        // profile is a plain word; quoted fields before it can hold commas, so
        // look for the Lab profile's trigger too.
        final cells = l.split(',');
        final isLab = (col >= 0 && col < cells.length && cells[col] == 'Lab') || l.contains(',Lab profile,');
        if (isLab) {
          lab = true;
        } else if (l.trim().isNotEmpty) {
          field = true;
        }
        if (lab && field) break;
      }
      return (lab: lab, field: field);
    });
  }

  Future<int> rowCount(String name) async {
    await flush();
    final path = file(name).path;
    return Isolate.run(() => _countRows(path));
  }

  static int _countRows(String path) {
    final f = File(path);
    if (!f.existsSync()) return 0;
    final raf = f.openSync();
    var lines = 0;
    try {
      final buf = Uint8List(1 << 20);
      while (true) {
        final n = raf.readIntoSync(buf);
        if (n <= 0) break;
        for (var i = 0; i < n; i++) {
          if (buf[i] == 10) lines++;
        }
      }
    } finally {
      raf.closeSync();
    }
    return lines > 0 ? lines - 1 : 0;
  }

  /// One Excel workbook with a sheet per log: Tests, Speed, Latency, GPS track, Sites.
  /// Built on a background isolate. Returns null if there is nothing to export.
  Future<File?> exportXlsx(String prefix) async {
    await flush();
    final outDir = Directory('${_dir.path}/export');
    if (await outDir.exists()) await outDir.delete(recursive: true);
    await outDir.create(recursive: true);
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final out = '${outDir.path}/$prefix.xlsx';
    final sources = [
      for (final e in sheetNames.entries) SheetSource(e.value, file(e.key).path),
    ];
    final n = await Isolate.run(() => writeXlsx(sources, out));
    return n == 0 ? null : File(out);
  }

  /// Worksheet name for each log file.
  static const sheetNames = {
    testsFile: 'Tests',
    samplesFile: 'Speed (per second)',
    latencyFile: 'Latency (per second)',
    trackFile: 'GPS track',
    failuresFile: 'Server failures',
    geofenceFile: 'Geofence',
    dsdsFile: 'DSDS transitions',
    gapsFile: 'Traffic gaps',
    visitsFile: 'Spectrum Wi-Fi visits',
    wifiScansFile: 'Wi-Fi scans',
    wifiStatesFile: 'Wi-Fi connection steps',
    stallsFile: 'UI stalls',
    sitesFile: 'Sites',
  };

  /// Deletes test, sample and track logs. Sites are kept.
  Future<void> clearLogs() async {
    await _closeAll();
    for (final name in [testsFile, samplesFile, latencyFile, trackFile, failuresFile, geofenceFile, dsdsFile, stallsFile, gapsFile, visitsFile, wifiScansFile, wifiStatesFile]) {
      final f = file(name);
      if (await f.exists()) await f.delete();
    }
  }

  static String _csvLine(List<Object?> values) => values.map(_csvField).join(',');

  static String _csvField(Object? v) {
    if (v == null) return '';
    final s = v.toString();
    if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }
}
