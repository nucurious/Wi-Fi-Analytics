import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
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

  Future<void> _export(BuildContext buttonContext) async {
    setState(() => _busy = true);
    try {
      final files = await widget.state.store.exportFiles();
      if (files.isEmpty) {
        _snack('Nothing to export yet. Run a test first.');
        return;
      }
      final box = buttonContext.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(ShareParams(
        files: files.map((f) => XFile(f.path, mimeType: 'text/csv')).toList(),
        subject: 'WiFi Analytics export',
        text: 'WiFi Analytics test data (CSV)',
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
          const SizedBox(height: 16),
          Builder(
            builder: (buttonContext) => SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _export(buttonContext),
                icon: const Icon(Icons.ios_share),
                label: const Text('Export CSV files', style: TextStyle(fontSize: 16)),
              ),
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
