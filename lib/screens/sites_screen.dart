import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';

class SitesScreen extends StatelessWidget {
  final AppState state;
  const SitesScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _addSite(context),
            icon: const Icon(Icons.add_location_alt),
            label: const Text('Add site here'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Text('Sites', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'The selected site is attached to every test and GPS log row. '
                '"Add site here" saves your current GPS position (or typed coordinates) with the site. '
                'Each site is a geofence: entering and leaving it is logged. Long-press a site to change its radius.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    _tile(context, null),
                    for (final s in state.sites) ...[const Divider(height: 1), _tile(context, s)],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(BuildContext context, Site? site) {
    final selected = state.activeSite?.id == site?.id;
    return ListTile(
      leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: selected ? Theme.of(context).colorScheme.primary : null),
      title: Text(site == null ? 'No site' : '${site.id} · ${site.name}'),
      subtitle: site == null
          ? const Text('Tests are logged without a site')
          : Text([
              if (site.latitude != null)
                '${site.latitude!.toStringAsFixed(6)}, ${site.longitude!.toStringAsFixed(6)}'
                    ' ±${site.accuracy?.toStringAsFixed(0) ?? '?'} m'
              else
                'No GPS when saved',
              if (site.latitude != null)
                'Geofence ${site.radiusM.toStringAsFixed(0)} m${state.geofence.isInside(site.id) ? ' · inside now' : ''}',
              if (site.notes.isNotEmpty) site.notes,
            ].join('\n')),
      isThreeLine: site != null && (site.notes.isNotEmpty || site.latitude != null),
      onLongPress: site == null ? null : () => _editRadius(context, site),
      onTap: () => state.setActiveSite(site),
      trailing: site == null
          ? null
          : IconButton(
              tooltip: 'Delete site',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Delete site?'),
                    content: Text('${site.id} · ${site.name}\nPast test logs keep their site ID.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok == true) await state.deleteSite(site);
              },
            ),
    );
  }

  Future<void> _editRadius(BuildContext context, Site site) async {
    final ctl = TextEditingController(text: site.radiusM.toStringAsFixed(0));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Geofence radius: ${site.id}'),
        content: TextField(
          controller: ctl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Radius (m)', helperText: '10 to 50000'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    final r = double.tryParse(ctl.text.trim());
    if (ok == true && r != null && r >= 10 && r <= 50000) await state.setSiteRadius(site, r);
  }

  Future<void> _addSite(BuildContext context) async {
    final radiusCtl = TextEditingController(text: '100');
    final coordCtl = TextEditingController();
    final idCtl = TextEditingController();
    final nameCtl = TextEditingController();
    final notesCtl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final p = state.position;

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add site at current location'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  p == null
                      ? 'No GPS fix yet. The site will be saved without coordinates.'
                      : 'GPS: ${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)} ±${p.accuracy.toStringAsFixed(0)} m',
                  style: Theme.of(c).textTheme.bodySmall,
                ),
                TextFormField(
                  controller: idCtl,
                  decoration: const InputDecoration(labelText: 'Site ID', hintText: 'e.g. DEN-0421'),
                  textCapitalization: TextCapitalization.characters,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                TextFormField(
                  controller: nameCtl,
                  decoration: const InputDecoration(labelText: 'Site name', hintText: 'e.g. Main St rooftop'),
                ),
                TextFormField(
                  controller: notesCtl,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                  maxLines: 2,
                ),
                TextFormField(
                  controller: radiusCtl,
                  decoration: const InputDecoration(
                      labelText: 'Geofence radius (m)', helperText: 'Entered / Exited is logged at this distance'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final r = double.tryParse((v ?? '').trim());
                    return r == null || r < 10 || r > 50000 ? 'Enter 10 to 50000' : null;
                  },
                ),
                TextFormField(
                  controller: coordCtl,
                  decoration: const InputDecoration(
                      labelText: 'Coordinates (optional)',
                      hintText: '39.600400, -104.891200',
                      helperText: 'Blank = current GPS position'),
                  keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                  validator: (v) => (v ?? '').trim().isEmpty || _parseCoords(v!) != null ? null : 'Use: latitude, longitude',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(c, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final c = _parseCoords(coordCtl.text);
      await state.addSite(
        id: idCtl.text,
        name: nameCtl.text,
        notes: notesCtl.text,
        radiusM: double.tryParse(radiusCtl.text.trim()) ?? 100,
        latitude: c?.$1,
        longitude: c?.$2,
      );
    }
  }

  static (double, double)? _parseCoords(String s) {
    final m = RegExp(r'^\s*(-?\d{1,2}(?:\.\d+)?)\s*[, ]\s*(-?\d{1,3}(?:\.\d+)?)\s*$').firstMatch(s);
    if (m == null) return null;
    final lat = double.parse(m[1]!), lon = double.parse(m[2]!);
    if (lat.abs() > 90 || lon.abs() > 180) return null;
    return (lat, lon);
  }
}
