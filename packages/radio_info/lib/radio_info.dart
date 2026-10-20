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

  /// Make, model, OS version and (Android 9 and older only) the last 4 IMEI digits.
  static Future<Map<String, dynamic>> deviceInfo() async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('getDeviceInfo');
      return m ?? <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// Android: data SIM (slot, carrier, PLMN) and cellular IPs. Cheap; polled 4 times a second.
  static Future<Map<String, dynamic>> dataState() async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('getDataState');
      return m ?? <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// Android: Wi-Fi scans and connection steps since the last call, plus Wi-Fi byte counters.
  static Future<Map<String, dynamic>> wifiEvents() async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('getWifiEvents');
      return m ?? <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// Android: asks the phone to scan now. False when Android throttles it
  /// (4 scans per 2 minutes for an app; testers can turn off "Wi-Fi scan
  /// throttling" in Developer options).
  static Future<bool> startWifiScan() async {
    try {
      return await _channel.invokeMethod<bool>('startWifiScan') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Android 11+: why earlier runs of the app ended (ANR, crash, killed ...) after [since] (ms).
  static Future<List<Map>> exitReasons(int since) async {
    try {
      final l = await _channel.invokeListMethod<Map>('getExitReasons', {'since': since});
      return l ?? const [];
    } catch (_) {
      return const [];
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
