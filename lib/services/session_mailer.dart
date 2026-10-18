import 'dart:convert';
import 'dart:io';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import 'data_store.dart';

/// Emails the rows written during one test session.
///
/// At session start [markStart] records how long each CSV is. At session end
/// [queueSession] copies only the newer rows (plus the header) into gzip
/// files named after the device, in an outbox folder. [sendOutbox] emails
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
  }) async {
    await store.flush();
    final dir = Directory('${outbox.path}/$filePrefix');
    await dir.create(recursive: true);
    var any = false;
    for (final name in sessionFiles) {
      final src = store.file(name);
      if (!await src.exists()) continue;
      final len = await src.length();
      var start = offsets[name] ?? 0;
      if (start > len) start = 0; // file was rotated during the session
      if (len - start <= 0) continue;
      final header = start > 0 ? await _firstLine(src) : null;
      final out = File('${dir.path}/${filePrefix}_${name}.gz');
      Stream<List<int>> rows() async* {
        if (header != null) yield utf8.encode('$header\n');
        yield* src.openRead(start, len);
      }

      await rows().transform(gzip.encoder).pipe(out.openWrite());
      any = true;
    }
    if (!any) {
      await dir.delete(recursive: true);
      return false;
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

  /// Sends every queued session. Returns the number of emails sent.
  Future<int> sendOutbox({required String to, required String user, required String appPassword}) async {
    if (_sending) return 0;
    if (to.trim().isEmpty || user.trim().isEmpty || appPassword.trim().isEmpty) {
      lastStatus = 'Email not sent: set the sender Gmail and app password in Settings';
      return 0;
    }
    if (!await outbox.exists()) return 0;
    _sending = true;
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
        final files = (await dir.list().toList()).whereType<File>().where((f) => f.path.endsWith('.gz')).toList()
          ..sort((a, b) => a.path.compareTo(b.path));

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
          var text = meta['body'] as String;
          if (tooBig.isNotEmpty) {
            text += '\n\nToo large to email (kept on the phone, export from the Data tab):\n  ${tooBig.join('\n  ')}';
          }
          final message = Message()
            ..from = Address(user.trim(), 'WiFi Analytics')
            ..recipients.add(to.trim())
            ..subject = '${meta['subject']}$suffix'
            ..text = text
            ..attachments = [
              for (final f in parts[i])
                FileAttachment(f, contentType: 'application/gzip', fileName: f.uri.pathSegments.last),
            ];
          await send(message, server, timeout: const Duration(minutes: 5));
          sent++;
        }
        await dir.delete(recursive: true);
      }
      final t = DateTime.now();
      lastStatus = 'Sent ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} '
          '($sent email${sent == 1 ? '' : 's'} to ${to.trim()})';
    } on MailerException catch (e) {
      lastStatus = 'Email failed, will retry: ${e.problems.map((p) => p.msg).join('; ')}';
    } catch (e) {
      lastStatus = 'Email failed, will retry: $e';
    } finally {
      _sending = false;
    }
    return sent;
  }
}
