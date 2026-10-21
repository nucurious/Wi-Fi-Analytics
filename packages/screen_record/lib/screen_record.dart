import 'package:flutter/services.dart';

/// Android screen recording through MediaProjection. The phone always shows
/// its own "Start recording?" prompt; the tester must tap Start now.
class ScreenRecord {
  static const MethodChannel _ch = MethodChannel('wifi_analytics/screen_record');

  /// Asks Android for permission and starts recording to [path] (.mp4).
  /// False when the tester declines the prompt or recording could not start.
  static Future<bool> start(String path) async {
    try {
      return await _ch.invokeMethod<bool>('start', {'path': path}) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Stops and finalizes the file. Returns its path, or null if nothing was recording.
  static Future<String?> stop() async {
    try {
      return await _ch.invokeMethod<String>('stop');
    } catch (_) {
      return null;
    }
  }

  /// {recording: bool, path: String?, startedMs: int, error: String?}
  static Future<Map<String, dynamic>> status() async {
    try {
      return await _ch.invokeMapMethod<String, dynamic>('status') ?? <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}
