import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_config.dart';
import '../app_state.dart';
import '../services/logcat_recorder.dart';
import '../services/data_store.dart';

class DataScreen extends StatefulWidget {
  final AppState state;
  const DataScreen({super.key, required this.state});

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  Map<String, int> _counts = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final store = widget.state.store;
    if (!widget.state.initialized) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) _refresh();
      return;
    }
    final counts = <String, int>{};
    for (final f in [DataStore.testsFile, DataStore.samplesFile, DataStore.latencyFile, DataStore.trackFile, DataStore.sitesFile]) {
      counts[f] = await store.rowCount(f);
    }
    if (mounted) setState(() => _counts = counts);
  }

  /// Excel workbook (one sheet per log) or compressed CSVs, via the share sheet.
  Future<void> _export(BuildContext buttonContext, {required bool excel}) async {
    setState(() => _busy = true);
    try {
      final prefix = widget.state.devicePrefix;
      final List<File> files;
      if (excel) {
        final x = await widget.state.store.exportXlsx(prefix);
        files = x == null ? <File>[] : [x];
      } else {
        files = await widget.state.store.exportCompressed(prefix);
      }
      if (files.isEmpty) {
        _snack('Nothing to export yet. Run a test first.');
        return;
      }
      var total = 0;
      for (final f in files) {
        total += await f.length();
      }
      final mb = total / 1048576;
      if (mb > 20) {
        _snack('Export is ${mb.toStringAsFixed(0)} MB, too big for most email. Share to Drive or Files, '
            'or clear the logs after exporting.');
      }
      final box = buttonContext.findRenderObject() as RenderBox?;
      String mime(File f) => f.path.endsWith('.xlsx')
          ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
          : f.path.endsWith('.gz')
              ? 'application/gzip'
              : 'text/csv';
      await SharePlus.instance.share(ShareParams(
        files: files.map((f) => XFile(f.path, mimeType: mime(f))).toList(),
        subject: 'WiFi Analytics export: $prefix',
        text: 'WiFi Analytics test data from $prefix (${mb.toStringAsFixed(1)} MB)',
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ));
    } catch (e) {
      _snack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clear logged data?'),
        content: const Text('Deletes tests.csv, samples.csv, twamp.csv and gps_track.csv from this phone. '
            'Saved sites are kept. Export first if you need the data.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) {
      await widget.state.store.clearLogs();
      widget.state.recent.clear();
      await _refresh();
      _snack('Logs cleared.');
    }
  }

  bool? _logcatAccess;

  Future<void> _checkLogcat() async {
    final ok = await LogcatRecorder.hasFullAccess();
    if (mounted) setState(() => _logcatAccess = ok);
  }

  Future<void> _shareLogcat(BuildContext buttonContext) async {
    final dir = await widget.state.logcat.root();
    final files = !await dir.exists()
        ? <File>[]
        : (await dir.list(recursive: true).toList()).whereType<File>().where((f) => f.path.endsWith('.txt.gz')).toList();
    if (files.isEmpty) {
      _snack('No saved logcat yet. It is recorded during each test session.');
      return;
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    final box = buttonContext.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(ShareParams(
      files: files.map((f) => XFile(f.path, mimeType: 'application/gzip')).toList(),
      subject: '$kAppName logcat',
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ));
  }

  Widget _logcatCard(BuildContext context) {
    final rec = widget.state.logcat;
    final pkg = 'com.example.analyticsdebug';
    final access = _logcatAccess;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Logcat (debug app)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(rec.running
                ? 'Recording to ${rec.sessionDir?.path ?? ''}'
                : 'Recorded during every test session (logcat -b all -v time, rotating files). '
                    'Emailed with the results, shared from here, or: '
                    'adb pull /sdcard/Android/data/com.example.analyticsdebug/files/logcat'),
            if (rec.problem != null) Text(rec.problem!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 6),
            Text(
              access == null
                  ? 'Full access (radio and other apps\' logs) not checked yet.'
                  : access
                      ? 'Full access granted: radio and system logs are included.'
                      : 'Only this app\'s own lines. Connect to a computer once and run:\n'
                          'adb shell pm grant $pkg android.permission.READ_LOGS',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              OutlinedButton(onPressed: _checkLogcat, child: const Text('Check access')),
              Builder(
                builder: (c) => OutlinedButton.icon(
                  onPressed: () => _shareLogcat(c),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Share logcat'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final running = widget.state.running;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Data', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh), tooltip: 'Refresh counts'),
            ],
          ),
          const SizedBox(height: 8),
          if (kDebugApp) ...[_logcatCard(context), const SizedBox(height: 8)],
          Card(
            child: Column(
              children: [
                _fileTile(DataStore.testsFile, 'One row per test: throughput, jitter, loss, GPS, site, radio'),
                const Divider(height: 1),
                _fileTile(DataStore.samplesFile, 'Every second during a test: Mbps, GPS, radio'),
                const Divider(height: 1),
                _fileTile(DataStore.latencyFile, 'Every second during a test: latency, jitter, loss (TWAMP or ping), GPS, radio'),
                const Divider(height: 1),
                _fileTile(DataStore.trackFile, 'Every second while the app is open: GPS + radio'),
                const Divider(height: 1),
                _fileTile(DataStore.sitesFile, 'Saved sites with coordinates'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ListenableBuilder(
            listenable: widget.state,
            builder: (context, _) {
              final s = widget.state;
              final pending = s.emailPending;
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: Text(s.settings.emailResults ? 'Email to ${s.settings.emailTo}' : 'Emailing results is off'),
                  subtitle: Text([
                    if (pending > 0) '$pending session${pending == 1 ? '' : 's'} waiting to send',
                    s.emailStatus ?? (pending == 0 ? 'Nothing waiting' : ''),
                  ].where((t) => t.isNotEmpty).join('\n')),
                  trailing: pending > 0
                      ? TextButton(
                          onPressed: () async {
                            await s.sendPendingEmail();
                            _refresh();
                          },
                          child: const Text('Send now'),
                        )
                      : null,
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Builder(
            builder: (buttonContext) => SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _export(buttonContext, excel: true),
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.ios_share),
                label: const Text('Export Excel workbook', style: TextStyle(fontSize: 16)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Builder(
            builder: (buttonContext) => OutlinedButton.icon(
              onPressed: _busy ? null : () => _export(buttonContext, excel: false),
              icon: const Icon(Icons.folder_zip_outlined),
              label: const Text('Export compressed CSV files'),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: running ? null : _clear,
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Clear logs'),
          ),
          const SizedBox(height: 16),
          Text(
            'Export opens your phone\'s share sheet so you can email the files, save them to Files / Drive, '
            'or AirDrop them. Files open in Excel or Google Sheets; latitude/longitude columns import into '
            'Google My Maps or Google Earth.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _fileTile(String name, String description) {
    final n = _counts[name];
    return ListTile(
      leading: const Icon(Icons.description_outlined),
      title: Text(name),
      subtitle: Text(description),
      trailing: Text(n == null ? '…' : '$n rows'),
    );
  }
}
