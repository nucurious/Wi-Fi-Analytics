import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import '../app_config.dart';
import 'data_store.dart';
import 'xlsx_writer.dart';

/// Emails the rows written during one test session.
///
/// At session start [markStart] records how long each CSV is. At session end
/// [queueSession] turns only the newer rows into one Excel workbook (a sheet
/// per log) named after the device, in an outbox folder; if it is too big for
/// one email, gzip CSVs are added so they can be split over several emails. [sendOutbox] emails
/// everything in the outbox via Gmail SMTP and deletes what was sent, so a
/// session that ends without signal is sent later.
class SessionMailer {
  final DataStore store;
  SessionMailer(this.store);

  /// Gmail rejects messages over 25 MB; base64 adds about a third.
  static const int maxEmailBytes = 17 * 1024 * 1024;

  static const sessionFiles = [
    DataStore.testsFile,
    DataStore.samplesFile,
    DataStore.latencyFile,
    DataStore.trackFile,
    DataStore.failuresFile,
  ];

  Directory get outbox => Directory('${store.directory.path}/outbox');

  String? lastStatus; // e.g. "Sent 12:40 (2 emails)" or the last error
  bool _sending = false;

  /// File lengths at session start.
  Future<Map<String, int>> markStart() async {
    await store.flush();
    final m = <String, int>{};
    for (final name in sessionFiles) {
      final f = store.file(name);
      m[name] = await f.exists() ? await f.length() : 0;
    }
    return m;
  }

  /// Writes this session's rows to a new outbox folder. Returns false if the
  /// session produced no rows.
  Future<bool> queueSession({
    required Map<String, int> offsets,
    required String filePrefix,
    required String subject,
    required String body,
    List<File> extraFiles = const [], // e.g. logcat .txt.gz parts (always emailed)
  }) async {
    await store.flush();
    // Same name for every session of a day, so each gets its own outbox folder.
    final t = DateTime.now();
    final dir = Directory('${outbox.path}/${filePrefix}__${t.millisecondsSinceEpoch}');
    await dir.create(recursive: true);

    // Byte range of this session in each log (header added back for Excel).
    final sources = <SheetSource>[];
    final slices = <(String, String, int, int, String?)>[]; // name, path, start, end, header
    for (final name in sessionFiles) {
      final src = store.file(name);
      if (!await src.exists()) continue;
      final len = await src.length();
      var start = offsets[name] ?? 0;
      if (start > len) start = 0; // file was rotated during the session
      if (len - start <= 0) continue;
      final header = start > 0 ? await _firstLine(src) : null;
      sources.add(SheetSource(DataStore.sheetNames[name] ?? name, src.path, start: start, end: len, header: header));
      slices.add((name, src.path, start, len, header));
    }
    if (sources.isEmpty) {
      await dir.delete(recursive: true);
      return false;
    }

    // One workbook, built off the UI isolate.
    final xlsx = '${dir.path}/$filePrefix.xlsx';
    final sheets = await Isolate.run(() => writeXlsx(sources, xlsx));
    if (sheets == 0) {
      await dir.delete(recursive: true);
      return false;
    }
    // Too big for one email: also write gzip CSVs that can be split across emails.
    if (await File(xlsx).length() > maxEmailBytes) {
      for (final (name, path, start, end, header) in slices) {
        final out = '${dir.path}/${filePrefix}_$name.gz';
        await Isolate.run(() async {
          Stream<List<int>> rows() async* {
            if (header != null) yield utf8.encode('$header\n');
            yield* File(path).openRead(start, end);
          }

          await rows().transform(gzip.encoder).pipe(File(out).openWrite());
        });
      }
    }
    for (final f in extraFiles) {
      if (await f.exists()) await f.rename('${dir.path}/${f.uri.pathSegments.last}');
    }
    await File('${dir.path}/message.json').writeAsString(jsonEncode({'subject': subject, 'body': body}));
    return true;
  }

  static Future<String> _firstLine(File f) async {
    final raf = await f.open();
    try {
      final head = await raf.read(64 * 1024);
      return utf8.decode(head, allowMalformed: true).split('\n').first.trimRight();
    } finally {
      await raf.close();
    }
  }

  int pendingCount() {
    if (!outbox.existsSync()) return 0;
    return outbox.listSync().whereType<Directory>().length;
  }

  /// Sends every queued session on a background isolate (base64-encoding
  /// large attachments would otherwise freeze the screen). Returns emails sent.
  Future<int> sendOutbox({required String to, required String user, required String appPassword}) async {
    if (_sending) return 0;
    if (to.trim().isEmpty || user.trim().isEmpty || appPassword.trim().isEmpty) {
      lastStatus = 'Email not sent: set the sender Gmail and app password in Settings';
      return 0;
    }
    if (!await outbox.exists()) return 0;
    _sending = true;
    final outboxPath = outbox.path;
    try {
      final (sent, status) = await Isolate.run(() => _sendAll(outboxPath, to, user, appPassword));
      lastStatus = status;
      return sent;
    } catch (e) {
      lastStatus = 'Email failed, will retry: $e';
      return 0;
    } finally {
      _sending = false;
    }
  }

  static Future<(int, String)> _sendAll(String outboxPath, String to, String user, String appPassword) async {
    final outbox = Directory(outboxPath);
    var sent = 0;
    try {
      final server = gmail(user.trim(), appPassword.replaceAll(' ', ''));
      final sessions = (await outbox.list().toList()).whereType<Directory>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final dir in sessions) {
        final metaFile = File('${dir.path}/message.json');
        if (!await metaFile.exists()) {
          await dir.delete(recursive: true);
          continue;
        }
        final meta = jsonDecode(await metaFile.readAsString()) as Map;
        final all = (await dir.list().toList()).whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path));
        final workbooks = all.where((f) => f.path.endsWith('.xlsx')).toList();
        final logcat = all.where((f) => f.path.endsWith('.txt.gz')).toList();
        final gzips = all.where((f) => f.path.endsWith('.gz') && !f.path.endsWith('.txt.gz')).toList();
        // The Excel workbook if it fits in one email, else the CSVs split over several.
        final files = [
          ...(workbooks.isNotEmpty && (gzips.isEmpty || await workbooks.first.length() <= maxEmailBytes))
              ? workbooks
              : gzips,
          ...logcat,
        ];
        final note = gzips.isNotEmpty && files.contains(gzips.first) && workbooks.isNotEmpty
            ? '\n\nThis session\'s Excel workbook is too large for email, so its data is attached as '
                'gzip-compressed CSVs, split across emails if needed (open with 7-Zip on Windows, or double-click on a Mac). '
                'Data tab > Export Excel workbook on the phone still makes the workbook.'
            : '';

        // Group attachments into emails under Gmail's size limit.
        final parts = <List<File>>[];
        final tooBig = <String>[];
        var current = <File>[];
        var size = 0;
        for (final f in files) {
          final n = await f.length();
          if (n > maxEmailBytes) {
            tooBig.add('${f.uri.pathSegments.last} (${(n / 1048576).toStringAsFixed(1)} MB)');
            continue;
          }
          if (size + n > maxEmailBytes && current.isNotEmpty) {
            parts.add(current);
            current = <File>[];
            size = 0;
          }
          current.add(f);
          size += n;
        }
        if (current.isNotEmpty || parts.isEmpty) parts.add(current);

        for (var i = 0; i < parts.length; i++) {
          final suffix = parts.length > 1 ? ' (part ${i + 1} of ${parts.length})' : '';
          var text = (meta['body'] as String) + note;
          if (tooBig.isNotEmpty) {
            text += '\n\nToo large to email (kept on the phone, export from the Data tab):\n  ${tooBig.join('\n  ')}';
          }
          final message = Message()
            ..from = Address(user.trim(), kAppName)
            ..recipients.add(to.trim())
            ..subject = '${meta['subject']}$suffix'
            ..text = text
            ..attachments = [
              for (final f in parts[i])
                FileAttachment(f,
                    contentType: f.path.endsWith('.xlsx')
                        ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
                        : 'application/gzip',
                    fileName: f.uri.pathSegments.last),
            ];
          await send(message, server, timeout: const Duration(minutes: 5));
          sent++;
        }
        await dir.delete(recursive: true);
      }
      final t = DateTime.now();
      return (
        sent,
        'Sent ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} '
            '($sent email${sent == 1 ? '' : 's'} to ${to.trim()})'
      );
    } on MailerException catch (e) {
      return (sent, 'Email failed, will retry: ${e.problems.map((p) => p.msg).join('; ')}');
    } catch (e) {
      return (sent, 'Email failed, will retry: $e');
    }
  }
}
