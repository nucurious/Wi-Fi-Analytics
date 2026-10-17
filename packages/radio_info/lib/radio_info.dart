import 'package:flutter/services.dart';

/// Access to serving-cell radio info (Android: full metrics; iOS: tech type).
class RadioInfo {
  static const MethodChannel _channel = MethodChannel('wifi_analytics/radio_info');

  /// Returns a map of radio fields. Keys that aren't available are omitted.
  static Future<Map<String, dynamic>> get() async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('getRadioInfo');
      return m ?? <String, dynamic>{};
    } on PlatformException catch (e) {
      return {'error': e.message ?? e.code};
    } on MissingPluginException {
      return {'error': 'Radio info not supported on this platform'};
    }
  }

  /// Android: asks for READ_PHONE_STATE (needed for network type / 5G NSA).
  static Future<bool> requestPhonePermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPhonePermission') ?? false;
    } catch (_) {
      return false;
    }
  }
}
