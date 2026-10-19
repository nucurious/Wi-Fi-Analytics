import 'dart:async';
import 'dart:io';
import 'dart:isolate';

/// Debug app only: records logcat on the phone during each test session,
/// the same way as On-Device_AdbLogging.bat:
///   logcat -b all -v time -f logcat_output.txt -r <KB> -n <count>
/// logcat itself writes and rotates the files (logcat_output.txt, .01, .02 ...,
/// higher number = older), one folder per session:
///   /sdcard/Android/data/<package>/files/logcat/<session file name>/
/// so they can also be pulled with adb:
///   adb pull /sdcard/Android/data/com.example.analyticsdebug/files/logcat
///
/// Reading other apps' and the radio's logs needs READ_LOGS, granted once per
/// install from a computer:
///   adb shell pm grant com.example.analyticsdebug android.permission.READ_LOGS
/// (Android 13+ also asks "Allow access to all device logs?" on the phone.)
class LogcatRecorder {
  /// Parent folder; each session gets a sub-folder.
  final Future<Directory> Function() root;
  LogcatRecorder(this.root);

  Process? _proc;
  Directory? sessionDir;
  String _prefix = 'logcat';
  DateTime? _started;
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

  /// Bytes written so far in this session (all rotated files).
  Future<int> bytesSoFar() async {
    final d = sessionDir;
    if (d == null || !await d.exists()) return 0;
    var n = 0;
    await for (final e in d.list()) {
      if (e is File && e.path.contains('logcat_output.txt')) n += await e.length();
    }
    return n;
  }

  Future<void> start(String prefix, {int partMb = 64, int parts = 50}) async {
    if (_proc != null || !Platform.isAndroid) return;
    problem = null;
    _prefix = prefix;
    _started = DateTime.now();
    final dir = Directory('${(await root()).path}/$prefix');
    await dir.create(recursive: true);
    sessionDir = dir;
    if (!await hasFullAccess()) {
      problem = 'Logcat: only this app\'s own lines. Grant full access once from a computer: '
          'adb shell pm grant com.example.analyticsdebug android.permission.READ_LOGS';
    }
    final t = _started!;
    final off = t.timeZoneOffset;
    String two(int n) => n.abs().toString().padLeft(2, '0');
    await File('${dir.path}/session_info.txt').writeAsString(
        'session: $prefix\n'
        'started (phone local): $t\n'
        'started (UTC): ${t.toUtc().toIso8601String()}\n'
        'logcat times are phone local time (-v time), UTC${off.isNegative ? '-' : '+'}${two(off.inHours)}:${two(off.inMinutes % 60)} (${t.timeZoneName})\n'
        'command: logcat -b all -v time -T 1 -f logcat_output.txt -r ${partMb * 1024} -n $parts\n');
    try {
      // -T 1: start from now instead of dumping the whole buffer (the .bat
      // clears the buffer instead, which would wipe other apps' logs).
      _proc = await Process.start('logcat', [
        '-b', 'all',
        '-v', 'time',
        '-T', '1',
        '-f', '${dir.path}/logcat_output.txt',
        '-r', '${partMb * 1024}',
        '-n', '$parts',
      ]);
      unawaited(_proc!.exitCode.then((code) {
        if (_proc != null && code != 0) problem = 'Logcat stopped by itself (exit code $code)';
      }));
    } catch (e) {
      problem = 'Logcat could not start: $e';
      _proc = null;
    }
  }

  /// Stops logcat and gzips each file off the UI thread, oldest first:
  /// <session>_logcat_output.txt.20.gz ... <session>_logcat_output.txt.gz.
  /// The .gz files stay in the session folder (Data > Share logcat, adb pull).
  Future<List<File>> stop() async {
    final proc = _proc;
    _proc = null;
    if (proc == null) return [];
    proc.kill();
    try {
      await proc.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {}
    final dir = sessionDir;
    if (dir == null || !await dir.exists()) return [];
    final raw = (await dir.list().toList())
        .whereType<File>()
        .where((f) => RegExp(r'logcat_output\.txt(\.\d+)?$').hasMatch(f.path))
        .toList();
    int age(File f) => int.tryParse(RegExp(r'\.(\d+)$').firstMatch(f.path)?[1] ?? '') ?? 0;
    raw.sort((a, b) => age(b).compareTo(age(a))); // oldest first
    final out = <File>[];
    for (final f in raw) {
      if (await f.length() == 0) continue;
      final name = f.uri.pathSegments.last; // logcat_output.txt.01
      final dst = '${dir.path}/${_prefix}_${name.replaceFirst('logcat_output.txt', 'logcat_output')}.txt.gz';
      final src = f.path;
      await Isolate.run(() async {
        await File(src).openRead().transform(gzip.encoder).pipe(File(dst).openWrite());
        await File(src).delete();
      });
      out.add(File(dst));
    }
    return out;
  }
}
