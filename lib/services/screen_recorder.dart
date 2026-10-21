import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screen_record/screen_record.dart';

/// Screen recording for the tester (Android only). The phone shows its own
/// "Start recording?" prompt every time; recording cannot start silently.
///
/// Files are written to <app external files>/recordings/ScreenRec_yyyymmdd-hhmmss.mp4.
/// When a test session ends they are moved into that session's run folder
/// (see takeRecordings) and listed in summary.txt. They are not emailed.
class ScreenRecorder extends ChangeNotifier {
  ScreenRecorder._();
  static final ScreenRecorder instance = ScreenRecorder._();

  bool recording = false;
  DateTime? startedAt;
  String? currentPath;
  String? error;
  Timer? _poll;

  bool get supported => Platform.isAndroid;

  Duration get elapsed => startedAt == null ? Duration.zero : DateTime.now().difference(startedAt!);

  Future<Directory> _dir() async {
    Directory? ext;
    try {
      ext = await getExternalStorageDirectory();
    } catch (_) {}
    final base = ext ?? await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/recordings');
    await d.create(recursive: true);
    return d;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// Asks Android for permission, then starts recording. False if declined.
  Future<bool> start() async {
    if (!supported || recording) return recording;
    error = null;
    final t = DateTime.now();
    final name = 'ScreenRec_${t.year}${_two(t.month)}${_two(t.day)}-${_two(t.hour)}${_two(t.minute)}${_two(t.second)}.mp4';
    final path = '${(await _dir()).path}/$name';
    final ok = await ScreenRecord.start(path);
    if (!ok) {
      final st = await ScreenRecord.status();
      error = (st['error'] as String?) ?? 'Screen recording was not started';
      notifyListeners();
      return false;
    }
    // The service starts a moment after the prompt is accepted.
    for (var i = 0; i < 20; i++) {
      final st = await ScreenRecord.status();
      if (st['recording'] == true) break;
      if (st['error'] != null) {
        error = st['error'] as String;
        notifyListeners();
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final st = await ScreenRecord.status();
    if (st['recording'] != true) {
      error = (st['error'] as String?) ?? 'Screen recording did not start';
      notifyListeners();
      return false;
    }
    recording = true;
    startedAt = DateTime.now();
    currentPath = path;
    // Detects the phone ending the recording by itself (system UI, another app).
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
      final s = await ScreenRecord.status();
      if (s['recording'] != true) {
        _finished();
      } else {
        notifyListeners(); // refresh the elapsed time
      }
    });
    notifyListeners();
    return true;
  }

  Future<String?> stop() async {
    if (!recording) return null;
    final p = await ScreenRecord.stop();
    _finished();
    return p ?? currentPath;
  }

  Future<void> stopIfRecording() async {
    if (recording) await stop();
  }

  void _finished() {
    _poll?.cancel();
    _poll = null;
    recording = false;
    startedAt = null;
    notifyListeners();
  }

  /// Finished recordings that overlap the session [start]..[end]: removed from
  /// the recordings folder's list by the caller after copying into the run folder.
  Future<List<File>> takeRecordings(DateTime start, DateTime end) async {
    if (!supported) return const [];
    final out = <File>[];
    try {
      final dir = await _dir();
      for (final e in await dir.list().toList()) {
        if (e is! File || !e.path.endsWith('.mp4')) continue;
        if (e.path == currentPath && recording) continue;
        final m = RegExp(r'ScreenRec_(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})\.mp4$').firstMatch(e.path);
        if (m == null) continue;
        final rs = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), int.parse(m[4]!), int.parse(m[5]!), int.parse(m[6]!));
        final re = e.lastModifiedSync();
        if (rs.isBefore(end) && re.isAfter(start)) out.add(e);
      }
    } catch (_) {}
    out.sort((a, b) => a.path.compareTo(b.path));
    return out;
  }
}
