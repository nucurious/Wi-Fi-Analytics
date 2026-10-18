import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';

class SettingsScreen extends StatefulWidget {
  final AppState state;
  const SettingsScreen({super.key, required this.state});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _host, _port, _tcpDur, _tcpPar, _udpMbps, _udpDur, _udpPar, _udpPkt;
  late TextEditingController _twHost, _twPort, _latRate, _twPkt, _pingHost, _latDur, _repeatGap;
  late bool _keepOn, _logTrack, _latOn, _repeat;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_maybeLoad);
    _maybeLoad();
  }

  @override
  void dispose() {
    widget.state.removeListener(_maybeLoad);
    super.dispose();
  }

  void _maybeLoad() {
    if (_loaded || !widget.state.initialized) return;
    final s = widget.state.settings;
    _host = TextEditingController(text: s.host);
    _port = TextEditingController(text: '${s.port}');
    _tcpDur = TextEditingController(text: '${s.tcpDuration}');
    _tcpPar = TextEditingController(text: '${s.tcpParallel}');
    _udpMbps = TextEditingController(text: _num(s.udpMbps));
    _udpDur = TextEditingController(text: '${s.udpDuration}');
    _udpPar = TextEditingController(text: '${s.udpParallel}');
    _udpPkt = TextEditingController(text: '${s.udpPacketBytes}');
    _keepOn = s.keepScreenOn;
    _logTrack = s.logGpsTrack;
    _latOn = s.latencyDuringTests;
    _twHost = TextEditingController(text: s.twampHost);
    _twPort = TextEditingController(text: '${s.twampPort}');
    _latRate = TextEditingController(text: '${s.latencyRateHz}');
    _twPkt = TextEditingController(text: '${s.twampPacketBytes}');
    _pingHost = TextEditingController(text: s.pingHost);
    _latDur = TextEditingController(text: '${s.latencyDuration}');
    _repeat = s.repeatUntilStopped;
    _repeatGap = TextEditingController(text: '${s.repeatIntervalSeconds}');
    setState(() => _loaded = true);
  }

  static String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await widget.state.updateSettings(Settings(
      host: _host.text.trim(),
      port: int.parse(_port.text),
      tcpDuration: int.parse(_tcpDur.text),
      tcpParallel: int.parse(_tcpPar.text),
      udpMbps: double.parse(_udpMbps.text),
      udpDuration: int.parse(_udpDur.text),
      udpParallel: int.parse(_udpPar.text),
      udpPacketBytes: int.parse(_udpPkt.text),
      keepScreenOn: _keepOn,
      logGpsTrack: _logTrack,
      latencyDuringTests: _latOn,
      twampHost: _twHost.text.trim(),
      twampPort: int.parse(_twPort.text),
      latencyRateHz: int.parse(_latRate.text),
      twampPacketBytes: int.parse(_twPkt.text),
      pingHost: _pingHost.text.trim(),
      latencyDuration: int.parse(_latDur.text),
      repeatUntilStopped: _repeat,
      repeatIntervalSeconds: int.parse(_repeatGap.text),
    ));
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text('Settings', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          _section('iperf3 server'),
          TextFormField(
            controller: _host,
            decoration: const InputDecoration(labelText: 'Server address', hintText: 'iperf.example.com or 203.0.113.10'),
            keyboardType: TextInputType.url,
            autocorrect: false,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          _intField(_port, 'Port', min: 1, max: 65535, helper: 'iperf3 default is 5201'),
          const SizedBox(height: 16),
          _section('Speed test (TCP)'),
          _intField(_tcpDur, 'Duration per direction (seconds)', min: 3, max: 120),
          _intField(_tcpPar, 'Parallel streams', min: 1, max: 16, helper: '4–8 gives the most accurate cellular speeds'),
          const SizedBox(height: 16),
          _section('UDP stream'),
          TextFormField(
            controller: _udpMbps,
            decoration: const InputDecoration(labelText: 'Target bitrate (Mbps)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) {
              final d = double.tryParse(v ?? '');
              if (d == null || d <= 0 || d > 2000) return 'Enter 0.1 to 2000';
              return null;
            },
          ),
          _intField(_udpDur, 'Duration (seconds, 0 = run until stopped)', min: 0, max: 86400),
          _intField(_udpPar, 'Parallel streams', min: 1, max: 8),
          _intField(_udpPkt, 'Packet size (bytes)', min: 64, max: 1472, helper: '1200 avoids fragmentation on most networks'),
          const SizedBox(height: 16),
          _section('Latency (TWAMP)'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Measure latency during every test'),
            subtitle: const Text('Runs alongside speed and UDP tests; writes twamp.csv'),
            value: _latOn,
            onChanged: (v) => setState(() => _latOn = v),
          ),
          TextFormField(
            controller: _twHost,
            decoration: const InputDecoration(
              labelText: 'TWAMP reflector address',
              hintText: 'Leave blank to use ping (Android)',
              helperText: 'TWAMP-Light / STAMP reflector, e.g. twampy responder',
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          _intField(_twPort, 'Reflector UDP port', min: 1, max: 65535, helper: 'TWAMP default is 862'),
          _intField(_latRate, 'Packets per second', min: 1, max: 50, helper: 'Ping is limited to 5 per second'),
          _intField(_twPkt, 'TWAMP packet size (bytes)', min: 41, max: 1472),
          TextFormField(
            controller: _pingHost,
            decoration: const InputDecoration(
              labelText: 'Ping host (fallback, Android only)',
              helperText: 'Used when no reflector is set. Not available on iPhone',
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          _intField(_latDur, 'Latency test duration (seconds, 0 = until stopped)', min: 0, max: 86400),
          const SizedBox(height: 16),
          _section('Long runs (overnight / weekend)'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Repeat until stopped'),
            subtitle: const Text('Runs the test again and again, and restarts it after errors or network changes'),
            value: _repeat,
            onChanged: (v) => setState(() => _repeat = v),
          ),
          _intField(_repeatGap, 'Pause between rounds (seconds)', min: 0, max: 86400,
              helper: 'e.g. 900 = a speed test every 15 minutes'),
          const SizedBox(height: 16),
          _section('Logging'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Keep screen on during tests'),
            subtitle: const Text('Recommended: tests and GPS pause if the phone locks'),
            value: _keepOn,
            onChanged: (v) => setState(() => _keepOn = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Log GPS track every second'),
            subtitle: const Text('Writes gps_track.csv while the app is open'),
            value: _logTrack,
            onChanged: (v) => setState(() => _logTrack = v),
          ),
          const SizedBox(height: 16),
          SizedBox(height: 52, child: FilledButton(onPressed: _save, child: const Text('Save settings'))),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );

  Widget _intField(TextEditingController c, String label, {required int min, required int max, String? helper}) {
    return TextFormField(
      controller: c,
      decoration: InputDecoration(labelText: label, helperText: helper),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validator: (v) {
        final n = int.tryParse(v ?? '');
        if (n == null || n < min || n > max) return 'Enter $min to $max';
        return null;
      },
    );
  }
}
