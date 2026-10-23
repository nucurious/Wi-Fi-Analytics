import 'package:flutter/material.dart';

import '../app_state.dart';

/// Analytics-Prov: live phone health on the Test screen.
class HealthCard extends StatelessWidget {
  final AppState state;
  const HealthCard({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: state.health,
      builder: (context, _) {
        final h = state.health;
        final l = h.last;
        if (l.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Phone health: starts with the next test.', style: Theme.of(context).textTheme.bodyMedium),
            ),
          );
        }
        String f(Object? v, [int d = 0]) => v is num ? v.toStringAsFixed(d) : '-';
        final bad = <String>[
          if (h.thermalWorst >= 2) 'throttled',
          if (h.gapCount > 0) '${h.gapCount} gaps',
          if (h.gpsLostCount > 0) 'GPS lost ${h.gpsLostCount}x',
          if (l['service'] == false) 'service down',
          if (h.lowBatterySamples > 0) 'low battery',
        ];
        Widget row(String a, String b) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                SizedBox(width: 92, child: Text(a, style: TextStyle(color: cs.onSurfaceVariant))),
                Expanded(child: Text(b)),
              ]),
            );
        return Card(
          color: bad.isEmpty ? null : cs.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('Phone health', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  Text(bad.isEmpty ? 'OK' : bad.join(' · '), style: TextStyle(fontWeight: FontWeight.w600, color: bad.isEmpty ? null : cs.error)),
                ]),
                const SizedBox(height: 4),
                row('Battery', '${f(l['battery'])}%${l['charging'] == true ? ' charging' : ''}  ·  ${f(l['temp'], 1)} C  ·  ${l['thermal'] ?? '-'}'),
                row('Memory', 'app ${f(l['pss'])} MB  ·  phone free ${f(l['free'])} MB'),
                row('GPS', l['gpsAge'] == null ? 'no fix yet' : 'last fix ${f(l['gpsAge'], 0)} s ago'),
                row('Service', l['service'] == null ? 'not used in this build' : (l['service'] == true ? 'running' : 'NOT running')),
                row('Logging', '${h.samples} samples  ·  ${h.gapCount} gap${h.gapCount == 1 ? '' : 's'}  ·  ${h.recoveries} auto-recover${h.recoveries == 1 ? 'y' : 'ies'}  ·  updated ${l['time']}'),
              ],
            ),
          ),
        );
      },
    );
  }
}
