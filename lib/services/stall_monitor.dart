import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:flutter/scheduler.dart';

/// One UI freeze, from whichever layer saw it.
class Stall {
  final DateTime time;
  final String kind; // App thread blocked, Slow frame, Android main thread blocked, Slow native call
  final int ms;
  final String detail;
  Stall(this.time, this.kind, this.ms, this.detail);
}

/// Records UI freezes so testers' runs show when and why the screen stopped
/// responding:
///  - App thread blocked: the Dart UI isolate didn't run a 200 ms timer on time
///    (heavy work on the UI thread).
///  - Slow frame: a frame took too long to build or draw.
///  - Android main thread blocked: reported by the native watchdog (touches
///    and platform messages wait while it is blocked).
///  - Slow native call: a radio / SIM read took too long to answer.
class StallMonitor {
  static const thresholdMs = 700;
  final void Function(Stall) onStall;
  StallMonitor(this.onStall);

  Timer? _tick;
  DateTime? _last;
  int count = 0;
  int worstMs = 0;

  void start() {
    _last = DateTime.now();
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final now = DateTime.now();
      final late = now.difference(_last!).inMilliseconds - 200;
      _last = now;
      if (late >= thresholdMs) report('App thread blocked', late, 'Dart UI isolate did not run for ${late + 200} ms');
    });
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final total = t.totalSpan.inMilliseconds;
      if (total >= thresholdMs) {
        report('Slow frame', total, 'build ${t.buildDuration.inMilliseconds} ms, raster ${t.rasterDuration.inMilliseconds} ms');
      }
    }
  }

  void report(String kind, int ms, String detail) {
    count++;
    if (ms > worstMs) worstMs = ms;
    onStall(Stall(DateTime.now(), kind, ms, detail));
  }

  void resetSession() {
    count = 0;
    worstMs = 0;
  }

  void stop() {
    _tick?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }
}
