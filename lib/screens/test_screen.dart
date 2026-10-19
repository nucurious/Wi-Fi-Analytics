import 'dart:math';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../app_config.dart';
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
            Text(kAppName, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
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
          onPressed: s.stopping ? null : s.stop,
          icon: s.stopping
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.stop),
          label: Text(s.stopping ? 'Stopping…' : 'Stop test', style: const TextStyle(fontSize: 18)),
        ),
      );
    }
    final latencyBy = s.settings.twampHost.isNotEmpty ? 'TWAMP' : 'ping';
    final profiles = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Traffic profiles', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: s.startDriveTest,
                icon: const Icon(Icons.directions_car),
                label: const Text('Start drive test', style: TextStyle(fontSize: 16)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              child: Text(
                'Latency ($latencyBy) + continuous UDP ${s.settings.driveUdpDirection} at ${_fmtNum(s.settings.udpMbps)} Mbps until you stop. Restarts by itself after drops.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: s.startWalkTest,
                icon: const Icon(Icons.directions_walk),
                label: const Text('Start walk test', style: TextStyle(fontSize: 16)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Latency ($latencyBy) all the time + a speed test each time the phone joins Wi-Fi'
                '${s.settings.walkTriggerOnRoam ? ' or moves to a new AP' : ''}. Runs until you stop.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: s.startLabTest,
                icon: const Icon(Icons.science),
                label: const Text('Start lab test', style: TextStyle(fontSize: 16)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Latency ($latencyBy) + one UDP downstream and one UDP upstream at the same time, '
                '${_fmtNum(s.settings.udpMbps)} Mbps each, until you stop. Upstream uses the next port '
                '(${s.settings.port + 1}). Files are named Lab_…',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
    final manual = Card(
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
            Text('Latency test', style: Theme.of(context).textTheme.titleMedium),
            Text(
              '${s.settings.twampHost.isNotEmpty ? 'TWAMP to ${s.settings.twampHost}:${s.settings.twampPort}' : 'Ping to ${s.settings.pingHost} (no TWAMP reflector set)'}, '
              '${s.settings.latencyDuration == 0 ? 'until stopped' : '${s.settings.latencyDuration}s'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: s.runLatencyTest,
                icon: const Icon(Icons.timer_outlined),
                label: const Text('Start latency test', style: TextStyle(fontSize: 16)),
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [profiles, const SizedBox(height: 12), manual]);
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
      final gen = r.wifiGeneration;
      if (gen != null || r.wifiBssid != null) {
        rows.add(_row(context, Icons.router, 'AP', [
          if (gen != null) gen,
          r.wifiBssid ?? 'BSSID hidden (allow Location)',
        ].join('  ·  ')));
      }
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
    // Dual SIM: which SIM carries data, its IP owner, last transition.
    final d = state.dsds.current;
    if (d != null && d.known) {
      final ip = d.ipv6.isNotEmpty ? d.ipv6.split(',').first : d.ipv4.split(',').first;
      rows.add(_row(context, Icons.sim_card, 'Data SIM', [
        d.label,
        if (d.plmn.isNotEmpty) d.plmn,
        if (ip.isNotEmpty) ip else 'no IP',
        if (state.lastDsds != null) 'last: ${state.lastDsds!.summary}',
      ].join('  ·  ')));
    }
    if (state.stalls.count > 0) {
      rows.add(_row(context, Icons.hourglass_bottom, 'UI freezes',
          '${state.stalls.count} this session, worst ${(state.stalls.worstMs / 1000).toStringAsFixed(1)} s (UI stalls sheet)'));
    }
    final hs = state.geofence.hmnoStatus();
    if (hs.isNotEmpty) rows.add(_row(context, Icons.layers, 'HMNO fence', hs));
    final g = state.lastGeofence;
    if (g != null) {
      final t = g.time;
      String two(int n) => n.toString().padLeft(2, '0');
      rows.add(_row(context, Icons.fence, 'Geofence', '${g.summary}  ·  ${two(t.hour)}:${two(t.minute)}:${two(t.second)}'));
    }

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
    final title = !s.running
        ? 'Ready'
        : '${s.profile != TestProfile.manual ? '${s.profile.label} · ' : ''}'
            '${s.waitingText ?? s.phase ?? 'Starting…'}'
            '${s.profile == TestProfile.walk ? '  ·  ${s.walkTests} speed test${s.walkTests == 1 ? '' : 's'}' : (s.round > 1 ? '  ·  round ${s.round}' : '')}';
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
                  !s.running
                      ? '--'
                      : s.latencyPhase
                          ? (s.latencyLive?.avgMs?.toStringAsFixed(1) ?? '--')
                          : s.currentMbps.toStringAsFixed(s.currentMbps >= 100 ? 0 : 1),
                  style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
                ),
                const SizedBox(width: 8),
                Text(s.latencyPhase ? 'ms' : 'Mbps', style: const TextStyle(fontSize: 18)),
              ],
            ),
            if (s.running && s.upMbps != null)
              Text('Down ${s.currentMbps.toStringAsFixed(1)} Mbps  ·  Up ${s.upMbps!.toStringAsFixed(1)} Mbps',
                  style: Theme.of(context).textTheme.titleSmall),
            if (s.running && s.latencyLive != null) _latencyLine(context, s),
            if (s.running && s.latencyProblem != null)
              Text(s.latencyProblem!, style: TextStyle(color: cs.error, fontSize: 13)),
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

Widget _latencyLine(BuildContext context, AppState s) {
  final l = s.latencyLive!;
  String f(double? v) => v == null ? '--' : v.toStringAsFixed(1);
  return Padding(
    padding: const EdgeInsets.only(top: 2, bottom: 4),
    child: Text(
      'Latency ${f(l.avgMs)} ms (min ${f(l.minMs)} / max ${f(l.maxMs)})  ·  jitter ${f(l.jitterMs)} ms  ·  '
      'loss ${l.lossPercent?.toStringAsFixed(1) ?? '--'}%  ·  ${s.latencyLabel ?? ''}',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    ),
  );
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
    final l = r.latency;
    final latencyText = l?.avgMs == null
        ? null
        : 'RTT ${l!.avgMs!.toStringAsFixed(1)} ms (min ${l.minMs!.toStringAsFixed(1)} / max ${l.maxMs!.toStringAsFixed(1)}), '
            'jitter ${l.jitterMs?.toStringAsFixed(1) ?? '--'} ms, loss ${l.lossPercent?.toStringAsFixed(1) ?? '--'}%';
    String subtitle;
    if (r.error != null) {
      subtitle = r.error!;
    } else {
      subtitle = [
        '${r.durationSeconds.toStringAsFixed(0)} s',
        if (r.minMbps != null && r.maxMbps != null)
          'min ${r.minMbps!.toStringAsFixed(1)} / max ${r.maxMbps!.toStringAsFixed(1)} / median ${r.medianMbps!.toStringAsFixed(1)} Mbps',
        if (r.jitterMs != null) 'jitter ${r.jitterMs!.toStringAsFixed(2)} ms',
        if (r.lossPercent != null) 'loss ${r.lossPercent!.toStringAsFixed(2)}% (${r.lost}/${r.total})',
        if (latencyText != null) latencyText,
        if (r.apInfo != null) r.apInfo!,
        if (r.stoppedByUser) 'stopped',
      ].join('  ·  ');
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(
          r.error != null
              ? Icons.error_outline
              : r.type.startsWith('Latency')
                  ? Icons.timer_outlined
                  : r.type.contains('Download')
                      ? Icons.south
                      : Icons.north,
          color: r.error != null ? Theme.of(context).colorScheme.error : null,
        ),
        title: Text(r.error != null
            ? '${r.type} failed'
            : r.mbps == null
                ? '${r.type}: ${r.latency?.avgMs?.toStringAsFixed(1) ?? '--'} ms'
                : '${r.type}: ${r.mbps!.toStringAsFixed(1)} Mbps'),
        subtitle: Text(subtitle),
        trailing: Text(time, style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }
}
