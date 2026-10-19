import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

/// Debug app only: records `adb logcat` on the phone during a test session.
///
/// Android lets an app read other apps' and the radio's logs only with the
/// READ_LOGS permission, which can't be granted on the phone itself. Grant it
/// once per install from a computer:
///   adb shell pm grant com.example.analyticsdebug android.permission.READ_LOGS
/// Without it, logcat only shows this app's own lines.
///
/// Lines are written as `logcat -v threadtime -v year -v UTC` (same as
/// `adb logcat -v threadtime -v year -v UTC`), in parts of [partBytes] so each
/// gzip part fits in an email.
class LogcatRecorder {
  final Directory dir;
  LogcatRecorder(this.dir);

  static const buffers = ['main', 'system', 'radio', 'events', 'crash'];
  static const int partBytes = 64 * 1024 * 1024; // ~5-8 MB once gzipped

  Process? _proc;
  IOSink? _sink;
  File? _current;
  int _bytes = 0;
  int _part = 0;
  String _prefix = 'logcat';
  final List<File> parts = [];
  final _done = <Future<void>>[];
  int lines = 0;
  String? problem;

  bool get running => _proc != null;

  /// True when READ_LOGS is granted (logcat can see the radio buffer).
  static Future<bool> hasFullAccess() async {
    if (!Platform.isAndroid) return false;
    try {
      final r = await Process.run('logcat', ['-d', '-t', '20', '-b', 'radio']);
      final out = (r.stdout as String).trim();
      return r.exitCode == 0 && out.isNotEmpty && !out.contains('Permission denied');
    } catch (_) {
      return false;
    }
  }

  Future<void> start(String prefix) async {
    if (_proc != null || !Platform.isAndroid) return;
    problem = null;
    _prefix = prefix;
    _part = 0;
    parts.clear();
    lines = 0;
    await dir.create(recursive: true);
    if (!await hasFullAccess()) {
      problem = 'Logcat: only this app\'s own lines. Grant full access once from a computer: '
          'adb shell pm grant <package> android.permission.READ_LOGS';
    }
    try {
      // -T 1: start from now (not the whole ring buffer).
      final proc = await Process.start('logcat', [
        for (final b in buffers) ...['-b', b],
        '-v', 'threadtime', '-v', 'year', '-v', 'UTC',
        '-T', '1',
      ]);
      _proc = proc;
      _openPart();
      _done.add(proc.stdout.listen(_write).asFuture<void>().catchError((_) {}));
      _done.add(proc.stderr.transform(utf8.decoder).listen((e) {
        if (e.trim().isNotEmpty) problem = 'Logcat: ${e.trim()}';
      }).asFuture<void>().catchError((_) {}));
    } catch (e) {
      problem = 'Logcat could not start: $e';
      _proc = null;
    }
  }

  void _openPart() {
    _part++;
    final f = File('${dir.path}/${_prefix}_logcat_${_part.toString().padLeft(2, '0')}.txt');
    _current = f;
    _sink = f.openWrite();
    _bytes = 0;
    parts.add(f);
  }

  void _write(List<int> data) {
    final sink = _sink;
    if (sink == null) return;
    sink.add(data);
    _bytes += data.length;
    for (final b in data) {
      if (b == 10) lines++;
    }
    if (_bytes >= partBytes) {
      final old = sink;
      _openPart();
      unawaited(old.close());
    }
  }

  /// Stops logcat and gzips each part off the UI thread. Returns the .gz files.
  Future<List<File>> stop() async {
    final proc = _proc;
    _proc = null;
    if (proc == null) return [];
    proc.kill();
    try {
      await Future.wait(_done).timeout(const Duration(seconds: 5));
    } catch (_) {}
    _done.clear();
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    _current = null;
    final out = <File>[];
    for (final f in List.of(parts)) {
      if (!await f.exists() || await f.length() == 0) continue;
      final src = f.path, dst = '${f.path}.gz';
      await Isolate.run(() async {
        await File(src).openRead().transform(gzip.encoder).pipe(File(dst).openWrite());
        await File(src).delete();
      });
      out.add(File(dst));
    }
    parts.clear();
    return out;
  }
}
