import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models.dart';

/// Appends rows to CSV files in the app's documents folder.
///
/// Files:
///  - tests.csv      one row per test (summary)
///  - samples.csv    one row per second while a test runs
///  - gps_track.csv  GPS + radio every second while the app is open
///  - sites.csv      saved sites
class DataStore {
  late Directory _dir;
  final Map<String, IOSink> _sinks = {};

  static const testsFile = 'tests.csv';
  static const samplesFile = 'samples.csv';
  static const trackFile = 'gps_track.csv';
  static const sitesFile = 'sites.csv';
  static const sitesJson = 'sites.json';
  static const settingsJson = 'settings.json';

  static final testsHeader = <String>[
    'test_id', 'test_type', 'start_utc', 'start_local', 'duration_s', 'throughput_mbps',
    'min_mbps', 'max_mbps', 'median_mbps', 'p10_mbps', 'p90_mbps', 'jitter_ms',
    'lost_packets', 'total_packets', 'loss_pct', 'stopped_by_user', 'error',
    'server', 'port', 'parallel_streams', 'udp_target_mbps', 'udp_packet_bytes',
    'site_id', 'site_name', 'device_platform',
    ...GpsCsv.header,
    ...RadioSnapshot.csvHeader,
  ];

  static final samplesHeader = <String>[
    'test_id', 'test_type', 'time_utc', 'time_local', 'elapsed_s', 'interval_mbps', 'site_id',
    ...GpsCsv.header,
    ...RadioSnapshot.csvHeader,
  ];

  static final trackHeader = <String>[
    'time_utc', 'time_local', 'site_id', 'test_running',
    ...GpsCsv.header,
    ...RadioSnapshot.csvHeader,
  ];

  static final sitesHeader = <String>[
    'site_id', 'site_name', 'notes', 'latitude', 'longitude', 'gps_accuracy_m', 'created_utc',
  ];

  Directory get directory => _dir;

  Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    _dir = Directory('${docs.path}/wifi_analytics');
    await _dir.create(recursive: true);
  }

  File file(String name) => File('${_dir.path}/$name');

  void _append(String name, List<String> header, List<Object?> row) {
    var sink = _sinks[name];
    if (sink == null) {
      final f = file(name);
      _rotateIfHeaderChanged(f, header);
      final isNew = !f.existsSync() || f.lengthSync() == 0;
      sink = f.openWrite(mode: FileMode.append);
      if (isNew) sink.writeln(_csvLine(header));
      _sinks[name] = sink;
    }
    sink.writeln(_csvLine(row));
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

  Future<void> flush() async {
    for (final s in _sinks.values) {
      await s.flush();
    }
  }

  Future<void> _closeAll() async {
    for (final s in _sinks.values) {
      await s.flush();
      await s.close();
    }
    _sinks.clear();
  }

  /// Rewrites sites.csv / sites.json from the full list.
  Future<void> saveSites(List<Site> sites) async {
    await file(sitesJson).writeAsString(jsonEncode(sites.map((s) => s.toJson()).toList()));
    final b = StringBuffer()..writeln(_csvLine(sitesHeader));
    for (final s in sites) {
      b.writeln(_csvLine([
        s.id, s.name, s.notes, s.latitude?.toStringAsFixed(7), s.longitude?.toStringAsFixed(7),
        s.accuracy?.toStringAsFixed(1), s.created.toUtc().toIso8601String(),
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

  /// CSV files that currently exist (for sharing).
  Future<List<File>> exportFiles() async {
    await flush();
    final out = <File>[];
    for (final name in [testsFile, samplesFile, trackFile, sitesFile]) {
      final f = file(name);
      if (await f.exists() && await f.length() > 0) out.add(f);
    }
    return out;
  }

  Future<int> rowCount(String name) async {
    await flush();
    final f = file(name);
    if (!await f.exists()) return 0;
    var lines = 0;
    await for (final _ in f.openRead().transform(utf8.decoder).transform(const LineSplitter())) {
      lines++;
    }
    return lines > 0 ? lines - 1 : 0;
  }

  /// Deletes test, sample and track logs. Sites are kept.
  Future<void> clearLogs() async {
    await _closeAll();
    for (final name in [testsFile, samplesFile, trackFile]) {
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
