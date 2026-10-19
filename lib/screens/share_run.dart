import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_config.dart';

/// Android package of this app (for the adb pull path shown to testers).
String get appPackage => kDebugApp ? 'com.example.analyticsdebug' : 'com.example.wifianalytics';

/// Shares every file of one test-run folder (workbook, summary, logcat) via
/// the phone's share sheet: Drive, email, Files, Teams ...
Future<void> shareRun(BuildContext buttonContext, Directory dir) async {
  final files = !await dir.exists()
      ? <File>[]
      : (await dir.list().toList()).whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    if (buttonContext.mounted) {
      ScaffoldMessenger.of(buttonContext).showSnackBar(const SnackBar(content: Text('This run folder is empty.')));
    }
    return;
  }
  String mime(File f) => f.path.endsWith('.xlsx')
      ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      : f.path.endsWith('.gz')
          ? 'application/gzip'
          : 'text/plain';
  final box = buttonContext.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(ShareParams(
    files: files.map((f) => XFile(f.path, mimeType: mime(f))).toList(),
    subject: '$kAppName run: ${dir.uri.pathSegments.where((s) => s.isNotEmpty).last}',
    sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
  ));
}

String folderName(Directory d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last;

/// Size of a folder's files, e.g. "3 files, 4.2 MB".
String folderSummary(Directory d) {
  try {
    final files = d.listSync().whereType<File>().toList();
    final bytes = files.fold<int>(0, (a, f) => a + f.lengthSync());
    final size = bytes >= 1048576 ? '${(bytes / 1048576).toStringAsFixed(1)} MB' : '${(bytes / 1024).ceil()} KB';
    return '${files.length} file${files.length == 1 ? '' : 's'}, $size';
  } catch (_) {
    return '';
  }
}
