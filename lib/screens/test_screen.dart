import 'dart:math';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';

class TestScreen extends StatefulWidget {
  final AppState state;
  const TestScreen({super.key, required this.state});

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  UdpDirection _udpDir = UdpDirection.download;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final s = widget.state;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text('WiFi Analytics', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (s.locationProblem != null)
              _Banner(
                icon: Icons.location_off,
                text: s.locationProblem!,
                action: 'Fix',
                onAction: () async {
                  await s.openLocationSettings();
                  await s.startLocation();
                },
              ),
            if (s.lastError != null)
              _Banner(icon: Icons.error_outline, text: s.lastError!, error: true),
            _StatusCard(state: s),
            const SizedBox(height: 12),
            _LiveCard(state: s),
            const SizedBox(height: 12),
            _controls(context, s),
            const SizedBox(height: 16),
            if (s.recent.isNotEmpty) ...[
              Text('Results this session', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              ...s.recent.map((r) => _ResultTile(record: r)),
            ],
          ],
        );
      },
    );
  }

  Widget _controls(BuildContext context, AppState s) {
    if (s.running) {
      return SizedBox(
        height: 56,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: s.stop,
          icon: const Icon(Icons.stop),
          label: const Text('Stop test', style: TextStyle(fontSize: 18)),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Speed test (TCP)', style: Theme.of(context).textTheme.titleMedium),
            Text(
              'Download then upload, ${s.settings.tcpDuration}s each, ${s.settings.tcpParallel} streams',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: s.runSpeedTest,
                icon: const Icon(Icons.speed),
                label: const Text('Run speed test', style: TextStyle(fontSize: 16)),
              ),
            ),
            const Divider(height: 32),
            Text('UDP stream', style: Theme.of(context).textTheme.titleMedium),
            Text(
              '${_fmtNum(s.settings.udpMbps)} Mbps, '
              '${s.settings.udpDuration == 0 ? 'continuous until stopped' : '${s.settings.udpDuration}s'}, '
              '${s.settings.udpPacketBytes}-byte packets',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SegmentedButton<UdpDirection>(
              segments: const [
                ButtonSegment(value: UdpDirection.download, label: Text('Down'), icon: Icon(Icons.south)),
                ButtonSegment(value: UdpDirection.upload, label: Text('Up'), icon: Icon(Icons.north)),
                ButtonSegment(value: UdpDirection.both, label: Text('Both'), icon: Icon(Icons.swap_vert)),
              ],
              selected: {_udpDir},
              onSelectionChanged: (v) => setState(() => _udpDir = v.first),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: FilledButton.tonalIcon(
                onPressed: () => s.runUdpStream(_udpDir),
                icon: const Icon(Icons.stream),
                label: const Text('Start UDP stream', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _fmtNum(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

class _Banner extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;
  final bool error;
  const _Banner({required this.icon, required this.text, this.action, this.onAction, this.error = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: error ? cs.errorContainer : cs.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: error ? cs.onErrorContainer : cs.onTertiaryContainer),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
            if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final AppState state;
  const _StatusCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final p = state.position;
    final r = state.radio;
    final rows = <Widget>[
      _row(context, Icons.place, 'Site', state.activeSite == null ? 'None selected' : '${state.activeSite!.id} · ${state.activeSite!.name}'),
      _row(
        context,
        Icons.gps_fixed,
        'GPS',
        p == null
            ? 'Waiting for fix…'
            : '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}  ±${p.accuracy.toStringAsFixed(0)} m'
                '${p.speed > 0.5 ? '  ·  ${(p.speed * 3.6).toStringAsFixed(0)} km/h' : ''}',
      ),
      _row(context, r.isWifi ? Icons.wifi : Icons.cell_tower, 'Network',
          '${r.connection}  ·  ${r.rat}${r.operatorName != null && r.operatorName!.isNotEmpty ? '  ·  ${r.operatorName}' : ''}'),
    ];

    if (r.isWifi && (r.wifiRssi != null || r.wifiSsid != null)) {
      rows.add(_row(context, Icons.wifi, 'Wi-Fi', [
        if (r.wifiSsid != null) r.wifiSsid!,
        if (r.wifiRssi != null) '${r.wifiRssi} dBm',
        if (r.wifiChannel != null) 'ch ${r.wifiChannel}',
        if (r.wifiBand != null) r.wifiBand!,
      ].join('  ·  ')));
    }
    final cell = <String>[
      if (r.lteRsrp != null) 'LTE RSRP ${r.lteRsrp}',
      if (r.lteSinr != null) 'SINR ${r.lteSinr}',
      if (r.nrRsrp != null) 'NR RSRP ${r.nrRsrp}',
      if (r.nrSinr != null) 'SINR ${r.nrSinr}',
      if (r.band != null) r.band!,
      if (r.pci != null) 'PCI ${r.pci}',
    ];
    if (cell.isNotEmpty) rows.add(_row(context, Icons.signal_cellular_alt, 'Cell', cell.join('  ·  ')));

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(children: rows),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: muted),
          const SizedBox(width: 8),
          SizedBox(width: 64, child: Text(label, style: TextStyle(color: muted))),
          Expanded(child: Text(value, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]))),
        ],
      ),
    );
  }
}

class _LiveCard extends StatelessWidget {
  final AppState state;
  const _LiveCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = state;
    final title = s.running ? s.phase ?? 'Starting…' : 'Ready';
    final timing = !s.running
        ? (s.settings.host.isEmpty ? 'Set your server in Settings' : 'Server ${s.settings.host}:${s.settings.port}')
        : s.plannedSeconds > 0
            ? '${s.elapsed.toStringAsFixed(0)} / ${s.plannedSeconds} s'
            : '${s.elapsed.toStringAsFixed(0)} s (continuous)';
    return Card(
      color: s.running ? cs.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text(timing, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  s.running ? s.currentMbps.toStringAsFixed(s.currentMbps >= 100 ? 0 : 1) : '--',
                  style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
                ),
                const SizedBox(width: 8),
                const Text('Mbps', style: TextStyle(fontSize: 18)),
              ],
            ),
            if (s.running && s.plannedSeconds > 0)
              LinearProgressIndicator(value: min(1.0, s.elapsed / s.plannedSeconds)),
            const SizedBox(height: 8),
            SizedBox(
              height: 64,
              width: double.infinity,
              child: CustomPaint(painter: _Sparkline(List.of(s.liveSeries), cs.primary)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sparkline extends CustomPainter {
  final List<double> values;
  final Color color;
  _Sparkline(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxV = values.reduce(max);
    final top = maxV <= 0 ? 1.0 : maxV * 1.1;
    final dx = size.width / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * dx;
      final y = size.height - (values[i] / top) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.15));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _Sparkline old) => true;
}

class _ResultTile extends StatelessWidget {
  final TestRecord record;
  const _ResultTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final r = record;
    final t = r.start;
    final time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
    String subtitle;
    if (r.error != null) {
      subtitle = r.error!;
    } else {
      subtitle = [
        '${r.durationSeconds.toStringAsFixed(0)} s',
        if (r.jitterMs != null) 'jitter ${r.jitterMs!.toStringAsFixed(2)} ms',
        if (r.lossPercent != null) 'loss ${r.lossPercent!.toStringAsFixed(2)}% (${r.lost}/${r.total})',
        if (r.stoppedByUser) 'stopped',
      ].join('  ·  ');
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(
          r.error != null
              ? Icons.error_outline
              : r.type.contains('Download')
                  ? Icons.south
                  : Icons.north,
          color: r.error != null ? Theme.of(context).colorScheme.error : null,
        ),
        title: Text(r.error != null ? '${r.type} failed' : '${r.type}: ${r.mbps!.toStringAsFixed(1)} Mbps'),
        subtitle: Text(subtitle),
        trailing: Text(time, style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }
}
