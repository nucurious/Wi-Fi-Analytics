import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_config.dart';
import '../app_state.dart';
import '../iperf/server_pool.dart';
import '../util/host_address.dart';


/// Error text for an address that can't be right, or null if it looks fine.
String? hostProblem(String raw, {bool required = true}) {
  final (host, _) = splitHostPort(raw);
  if (host.isEmpty) return required ? 'Required' : null;
  if (':'.allMatches(host).length >= 2 && InternetAddress.tryParse(host) == null) {
    return 'Not a valid IPv6 address. Check for a typo, and leave the port out';
  }
  if (RegExp(r'[^A-Za-z0-9.:%_-]').hasMatch(host)) return 'Address has characters that do not belong in it';
  return null;
}

/// Known test servers, offered as one-tap presets under the address fields.
/// Tapping one fills the fields; they stay editable.
const serverPresets = <(String, String, int)>[
  ('Lab (public IPv4)', '96.37.191.0', 5201),
  ('Lab (IPv6)', '2600:6ce6:4406:6006:8b6e:251:99cb:9c38', 5201),
  ('Lab (on lab Wi-Fi)', '10.92.5.100', 5201),
  ('Clouvider Dallas', 'dal.speedtest.clouvider.net', 5200),
];

class SettingsScreen extends StatefulWidget {
  final AppState state;
  const SettingsScreen({super.key, required this.state});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _host, _port, _tcpDur, _tcpPar, _udpMbps, _udpDur, _udpPar, _udpPkt;
  late TextEditingController _twHost, _twPort, _latRate, _twPkt, _pingHost, _latDur, _repeatGap, _walkSettle, _walkGap;
  late bool _keepOn, _logTrack, _latOn, _repeat, _walkRoam, _email, _rotate, _logcat;
  late TextEditingController _emailTo, _smtpUser, _smtpPass, _imei, _locCode;
  late String _env;
  bool _showPass = false;
  late String _driveDir;
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
    _rotate = s.rotateServers;
    _logcat = s.recordLogcat;
    _repeatGap = TextEditingController(text: '${s.repeatIntervalSeconds}');
    _driveDir = s.driveUdpDirection;
    _walkSettle = TextEditingController(text: '${s.walkSettleSeconds}');
    _walkGap = TextEditingController(text: '${s.walkMinGapSeconds}');
    _walkRoam = s.walkTriggerOnRoam;
    _email = s.emailResults;
    _emailTo = TextEditingController(text: s.emailTo);
    _smtpUser = TextEditingController(text: s.smtpUser);
    _smtpPass = TextEditingController(text: s.smtpPassword);
    _imei = TextEditingController(text: s.imeiLast4);
    _locCode = TextEditingController(text: s.locationCode);
    _env = s.testEnvironment;
    setState(() => _loaded = true);
  }

  static String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // Accept "address:port" / "[IPv6]:port": move the port to its own field.
    final (host, typedPort) = splitHostPort(_host.text);
    final port = typedPort ?? int.parse(_port.text);
    final (twHost, typedTwPort) = splitHostPort(_twHost.text);
    final twPort = typedTwPort ?? int.parse(_twPort.text);
    setState(() {
      _host.text = host;
      _port.text = '$port';
      _twHost.text = twHost;
      _twPort.text = '$twPort';
    });
    await widget.state.updateSettings(Settings(
      host: host,
      port: port,
      tcpDuration: int.parse(_tcpDur.text),
      tcpParallel: int.parse(_tcpPar.text),
      udpMbps: double.parse(_udpMbps.text),
      udpDuration: int.parse(_udpDur.text),
      udpParallel: int.parse(_udpPar.text),
      udpPacketBytes: int.parse(_udpPkt.text),
      keepScreenOn: _keepOn,
      logGpsTrack: _logTrack,
      latencyDuringTests: _latOn,
      twampHost: twHost,
      twampPort: twPort,
      latencyRateHz: int.parse(_latRate.text),
      twampPacketBytes: int.parse(_twPkt.text),
      pingHost: _pingHost.text.trim(),
      latencyDuration: int.parse(_latDur.text),
      repeatUntilStopped: _repeat,
      repeatIntervalSeconds: int.parse(_repeatGap.text),
      driveUdpDirection: _driveDir,
      walkSettleSeconds: int.parse(_walkSettle.text),
      walkMinGapSeconds: int.parse(_walkGap.text),
      walkTriggerOnRoam: _walkRoam,
      emailResults: _email,
      emailTo: _emailTo.text.trim(),
      smtpUser: _smtpUser.text.trim(),
      smtpPassword: _smtpPass.text.trim(),
      imeiLast4: _imei.text.trim(),
      rotateServers: _rotate,
      recordLogcat: _logcat,
      testEnvironment: _env,
      locationCode: _locCode.text.trim().toUpperCase(),
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
            decoration: const InputDecoration(
              labelText: 'Server address',
              hintText: '203.0.113.10, 2600:1234::10 or iperf.example.com',
              helperText: 'Address only; the port goes below (address:port is also accepted)',
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            validator: (v) => hostProblem(v ?? ''),
          ),
          _intField(_port, 'Port', min: 1, max: 65535, helper: 'iperf3 default is 5201'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final (label, host, port) in serverPresets)
                ActionChip(
                  label: Text(label),
                  onPressed: () => setState(() {
                    _host.text = host;
                    _port.text = '$port';
                  }),
                ),
              for (final p in publicServers)
                ActionChip(
                  label: Text(p.udp ? p.name : '${p.name} · no UDP'),
                  onPressed: () => setState(() {
                    _host.text = p.host;
                    _port.text = '${p.firstPort}';
                  }),
                ),
            ],
          ),
          Text('Tap to fill in, then Save settings. You can still edit the fields. '
              '"no UDP" servers work for speed tests and Walk, not for UDP streams or Drive.',
              style: Theme.of(context).textTheme.bodySmall),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Switch servers when a test can\'t start'),
            subtitle: const Text('If the server is busy, down or unreachable, tries its next port, then the next '
                'public server (Dallas, Chicago, Atlanta, Boston). Those failures are left out of the results '
                'and listed on a separate "Server failures" sheet.'),
            value: _rotate,
            onChanged: (v) => setState(() => _rotate = v),
          ),
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
            validator: (v) => hostProblem(v ?? '', required: false),
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
          _section('Drive profile'),
          const Text('Latency + one continuous UDP stream (bitrate and packet size from UDP stream above).'),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'download', label: Text('UDP download'), icon: Icon(Icons.south)),
              ButtonSegment(value: 'upload', label: Text('UDP upload'), icon: Icon(Icons.north)),
            ],
            selected: {_driveDir},
            onSelectionChanged: (v) => setState(() => _driveDir = v.first),
          ),
          const SizedBox(height: 16),
          _section('Walk profile'),
          _intField(_walkSettle, 'Wait after joining Wi-Fi (seconds)', min: 0, max: 120,
              helper: 'Lets Wi-Fi finish connecting before the speed test'),
          _intField(_walkGap, 'Minimum time between speed tests (seconds)', min: 0, max: 3600),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Also test when moving to a new AP'),
            subtitle: const Text('Roams between APs on the same Wi-Fi network (Android only)'),
            value: _walkRoam,
            onChanged: (v) => setState(() => _walkRoam = v),
          ),
          const SizedBox(height: 16),
          _section('Email results'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Email results when a session stops'),
            subtitle: const Text('Only that session\'s rows, gzip-compressed. Queued and retried if there is no signal'),
            value: _email,
            onChanged: (v) => setState(() => _email = v),
          ),
          TextFormField(
            controller: _emailTo,
            decoration: const InputDecoration(labelText: 'Send to'),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
          ),
          TextFormField(
            controller: _smtpUser,
            decoration: const InputDecoration(labelText: 'Sender Gmail address', hintText: 'a Gmail account used only for sending'),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
          ),
          TextFormField(
            controller: _smtpPass,
            obscureText: !_showPass,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Gmail app password',
              helperText: 'Google Account > Security > App passwords (needs 2-Step Verification). Stored on this phone',
              helperMaxLines: 2,
              suffixIcon: IconButton(
                icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showPass = !_showPass),
              ),
            ),
          ),
          TextFormField(
            controller: _imei,
            decoration: InputDecoration(
              labelText: 'IMEI last 4 digits (for file names)',
              helperText: 'Dial *#06# to see the IMEI. It is the last part of the file name.',
              helperMaxLines: 2,
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
          ),
          const SizedBox(height: 16),
          _section('File names'),
          Text('Now: ${widget.state.fileName()}', style: Theme.of(context).textTheme.bodyMedium),
          Text('Field/Lab _ make _ model _ build (last 4) _ profile _ location _ IMEI (last 4) _ date-time',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _env,
            decoration: const InputDecoration(labelText: 'Field or Lab'),
            items: const [
              DropdownMenuItem(value: 'auto', child: Text('Auto (Lab on lab Wi-Fi, lab site or at the lab)')),
              DropdownMenuItem(value: 'field', child: Text('Field')),
              DropdownMenuItem(value: 'lab', child: Text('Lab')),
            ],
            onChanged: (v) => setState(() => _env = v ?? 'auto'),
          ),
          TextFormField(
            controller: _locCode,
            decoration: const InputDecoration(
              labelText: 'Location code (optional)',
              hintText: 'DAL, HEN, ATL, CLT, MAC, DEN ...',
              helperText: 'Blank = nearest market to the site, else to GPS',
            ),
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')), LengthLimitingTextInputFormatter(6)],
          ),
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
          if (kDebugApp)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Record logcat during tests'),
              subtitle: const Text('Saved per session (gzip) and emailed with the results. See the Data tab for access.'),
              value: _logcat,
              onChanged: (v) => setState(() => _logcat = v),
            ),
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
