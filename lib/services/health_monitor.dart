import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:radio_info/radio_info.dart';

import 'background_keeper.dart';

/// Analytics-Prov: samples the phone's health every [interval] while a session runs and writes one row per sample
/// to a CSV that becomes the "Health" sheet. Also keeps the numbers for the live card and the summary text.
///
/// What it watches: battery (level, charging, temperature), thermal throttling, memory (app and phone),
/// power saving / Doze, whether GPS fixes keep arriving, whether the foreground service is up, and gaps in
/// logging (a gap is a sample that came much later than it should: the phone froze or paused the app).
class HealthMonitor extends ChangeNotifier {
  static const interval = Duration(seconds: 10);
  static const gapSeconds = 25; // a sample this late = the app was not running normally
  static const gpsLostSeconds = 10; // no GPS fix for this long

  static const header = [
    'time_utc', 'time_local', 'since_last_s', 'battery_pct', 'charging', 'plugged', 'battery_temp_c', 'battery_mv',
    'thermal', 'power_save', 'doze', 'screen_on', 'battery_opt_ignored', 'phone_free_mem_mb', 'low_memory',
    'app_pss_mb', 'app_heap_mb', 'gps_age_s', 'service_running', 'logging_gap',
  ];
  static const thermalNames = ['None', 'Light', 'Moderate', 'Severe', 'Critical', 'Emergency', 'Shutdown'];

  static String tn(int v) => thermalNames[v < 0 ? 0 : (v > 6 ? 6 : v)];

  File? file;
  DateTime? _start;
  DateTime? _lastSample;
  Timer? _timer;
  bool _busy = false;
  Map<String, Object?> last = {};

  // session statistics
  int samples = 0;
  double? batteryStart, batteryEnd, batteryMin;
  double? tempMax, tempStart;
  int thermalWorst = 0;
  String thermalWorstAt = '';
  double? freeMemMin, pssMax;
  int lowMemorySamples = 0;
  int powerSaveSamples = 0, dozeSamples = 0;
  int gapCount = 0;
  double gapTotalS = 0, gapWorstS = 0;
  int gpsLostCount = 0;
  double gpsLostTotalS = 0;
  bool _gpsLost = false;
  int serviceDownSamples = 0;
  int chargingSamples = 0;

  bool get active => _timer != null;

  void _reset() {
    samples = 0;
    batteryStart = batteryEnd = batteryMin = tempMax = tempStart = freeMemMin = pssMax = null;
    thermalWorst = 0;
    thermalWorstAt = '';
    lowMemorySamples = powerSaveSamples = dozeSamples = gapCount = gpsLostCount = serviceDownSamples = chargingSamples = 0;
    gapTotalS = gapWorstS = gpsLostTotalS = 0;
    _gpsLost = false;
    _lastSample = null;
    last = {};
  }

  static String _q(Object? v) {
    final s = v?.toString() ?? '';
    return RegExp(r'[",\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  Future<void> start(Directory dir, DateTime Function() now, DateTime? Function() lastGpsFix, String Function(DateTime) local) async {
    stop();
    _reset();
    _start = now();
    _lastSample = _start;
    file = File('${dir.path}/health_session.csv');
    await file!.writeAsString('${header.join(',')}\n');
    await _sample(lastGpsFix, local);
    _timer = Timer.periodic(interval, (_) => _sample(lastGpsFix, local));
    notifyListeners();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _sample(DateTime? Function() lastGpsFix, String Function(DateTime) local) async {
    if (_busy) return;
    _busy = true;
    try {
      final h = await RadioInfo.health();
      final t = DateTime.now();
      final since = _lastSample == null ? 0.0 : t.difference(_lastSample!).inMilliseconds / 1000.0;
      _lastSample = t;
      final gap = samples > 0 && since > gapSeconds;
      if (gap) {
        gapCount++;
        gapTotalS += since - interval.inSeconds;
        if (since > gapWorstS) gapWorstS = since;
      }
      double? n(String k) => (h[k] as num?)?.toDouble();
      final pct = n('batteryPct');
      final status = (h['batteryStatus'] as num?)?.toInt() ?? -1;
      final charging = status == 2 || status == 5;
      final plugged = (h['plugged'] as num?)?.toInt() ?? 0;
      final temp = n('batteryTempC');
      final th = (h['thermalStatus'] as num?)?.toInt();
      final free = n('availMemMb');
      final pss = n('appPssMb');
      final gpsAt = lastGpsFix();
      final gpsAge = gpsAt == null ? null : t.difference(gpsAt).inMilliseconds / 1000.0;
      final svc = await BackgroundKeeper.running(); // null = this build has no service
      samples++;
      if (pct != null) {
        batteryStart ??= pct;
        batteryEnd = pct;
        if (batteryMin == null || pct < batteryMin!) batteryMin = pct;
      }
      if (temp != null) {
        tempStart ??= temp;
        if (tempMax == null || temp > tempMax!) tempMax = temp;
      }
      if (th != null && th > thermalWorst) {
        thermalWorst = th;
        thermalWorstAt = local(t).split(' ').last;
      }
      if (free != null && (freeMemMin == null || free < freeMemMin!)) freeMemMin = free;
      if (pss != null && (pssMax == null || pss > pssMax!)) pssMax = pss;
      if (h['lowMemory'] == true) lowMemorySamples++;
      if (h['powerSave'] == true) powerSaveSamples++;
      if (h['doze'] == true) dozeSamples++;
      if (charging) chargingSamples++;
      if (svc == false) serviceDownSamples++;
      final lost = gpsAge == null || gpsAge > gpsLostSeconds;
      if (lost) {
        gpsLostTotalS += interval.inSeconds;
        if (!_gpsLost) gpsLostCount++;
      }
      _gpsLost = lost;
      last = {
        'time': local(t).split(' ').last,
        'battery': pct,
        'charging': charging,
        'temp': temp,
        'thermal': th == null ? null : tn(th),
        'free': free,
        'pss': pss,
        'gpsAge': gpsAge,
        'service': svc,
        'powerSave': h['powerSave'],
        'doze': h['doze'],
        'gaps': gapCount,
      };
      final row = [
        t.toUtc().toIso8601String(),
        local(t),
        since.toStringAsFixed(1),
        pct?.toStringAsFixed(0),
        status == -1 ? '' : (charging ? 'charging' : (status == 5 ? 'full' : 'discharging')),
        plugged == 0 ? '' : (plugged == 1 ? 'AC' : plugged == 2 ? 'USB' : plugged == 4 ? 'wireless' : '$plugged'),
        temp?.toStringAsFixed(1),
        h['batteryMv'],
        th == null ? '' : tn(th),
        h['powerSave'] == null ? '' : (h['powerSave'] == true ? 'yes' : 'no'),
        h['doze'] == null ? '' : (h['doze'] == true ? 'yes' : 'no'),
        h['screenOn'] == null ? '' : (h['screenOn'] == true ? 'on' : 'off'),
        h['ignoringBatteryOpt'] == null ? '' : (h['ignoringBatteryOpt'] == true ? 'yes' : 'no'),
        free?.toStringAsFixed(0),
        h['lowMemory'] == null ? '' : (h['lowMemory'] == true ? 'yes' : 'no'),
        pss?.toStringAsFixed(0),
        n('heapMb')?.toStringAsFixed(0),
        gpsAge?.toStringAsFixed(1),
        svc == null ? '' : (svc ? 'yes' : 'NO'),
        gap ? 'yes' : '',
      ];
      await file?.writeAsString('${row.map(_q).join(',')}\n', mode: FileMode.append);
      notifyListeners();
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  /// Lines for the session summary (email body).
  List<String> summaryLines() {
    if (samples == 0) return ['Health: no samples (sheet Health).'];
    String f(double? v, [int d = 0]) => v == null ? '-' : v.toStringAsFixed(d);
    final dropped = batteryStart != null && batteryEnd != null ? batteryStart! - batteryEnd! : null;
    final out = <String>[
      'Health ($samples samples, sheet Health): battery ${f(batteryStart)}% to ${f(batteryEnd)}%'
          '${dropped != null && chargingSamples < samples ? ' (${dropped >= 0 ? '-' : '+'}${f(dropped.abs())} points)' : ''}'
          '${chargingSamples > 0 ? ', charging in $chargingSamples samples' : ''}; '
          'battery temperature max ${f(tempMax, 1)} C; '
          'thermal ${tn(thermalWorst)}${thermalWorst >= 2 ? ' at $thermalWorstAt' : ''}; '
          'phone free memory min ${f(freeMemMin)} MB, app memory max ${f(pssMax)} MB.',
    ];
    final problems = <String>[
      if (thermalWorst >= 2) 'phone ran hot enough to be throttled (thermal ${tn(thermalWorst)})',
      if (gapCount > 0) '$gapCount logging gap${gapCount == 1 ? '' : 's'} (worst ${f(gapWorstS)} s, total ${f(gapTotalS)} s): the app was paused or the phone froze',
      if (gpsLostCount > 0) 'GPS fixes stopped $gpsLostCount time${gpsLostCount == 1 ? '' : 's'} (${f(gpsLostTotalS)} s in all)',
      if (serviceDownSamples > 0) 'foreground service was not running in $serviceDownSamples samples',
      if (lowMemorySamples > 0) 'phone reported low memory in $lowMemorySamples samples',
      if (powerSaveSamples > 0) 'battery saver was on in $powerSaveSamples samples',
      if (dozeSamples > 0) 'Doze (idle mode) in $dozeSamples samples',
    ];
    out.add(problems.isEmpty ? 'Health flags: none.' : 'Health flags: ${problems.join('; ')}.');
    return out;
  }
}
