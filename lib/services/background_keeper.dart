import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// True in the Video Call Analytics build (flutter build --dart-define=VIDEO_CALL=true).
const bool kVideoCall = bool.fromEnvironment('VIDEO_CALL');

/// Keeps the process alive while a call app (WhatsApp, Teams, Webex...) is on screen:
/// an Android foreground service with a notification, started with a session and stopped when it ends.
/// Does nothing in the other builds.
class BackgroundKeeper {
  static bool _inited = false;

  static Future<void> start() async {
    if (!kVideoCall || !Platform.isAndroid) return;
    try {
      if (!_inited) {
        FlutterForegroundTask.init(
          androidNotificationOptions: AndroidNotificationOptions(
            channelId: 'video_call_analytics',
            channelName: 'Video Call Analytics session',
            channelDescription: 'Shown while a test session keeps logging in the background.',
            onlyAlertOnce: true,
          ),
          iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
          foregroundTaskOptions: ForegroundTaskOptions(eventAction: ForegroundTaskEventAction.nothing()),
        );
        _inited = true;
      }
      if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
      if (await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.startService(
        serviceId: 4711,
        notificationTitle: 'Video Call Analytics',
        notificationText: 'Logging network and radio data. Tap to open.',
      );
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (!kVideoCall || !Platform.isAndroid) return;
    try {
      if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
    } catch (_) {}
  }
}
