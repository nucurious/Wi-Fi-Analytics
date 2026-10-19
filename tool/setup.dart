// Finishes the generated iOS / Android project folders for WiFi Analytics.
//
// Run from the project root AFTER `flutter create`:
//   dart run tool/setup.dart
//
// Optional environment variable:
//   BUNDLE_ID   iOS bundle identifier / Android application ID
//               (e.g. com.yourname.wifianalytics). Must match what you
//               registered with Apple.
//
// Safe to run more than once.

import 'dart:io';

const appName = 'Wi-Fi_Analytics_v1.3';

void main() {
  final bundleId = Platform.environment['BUNDLE_ID']?.trim();
  _removeTemplateTest();
  _patchAndroidManifest();
  if (bundleId != null && bundleId.isNotEmpty) _patchAndroidAppId(bundleId);
  _patchInfoPlist();
  if (bundleId != null && bundleId.isNotEmpty) _patchIosBundleId(bundleId);
  stdout.writeln('WiFi Analytics setup complete.');
}

void _removeTemplateTest() {
  // `flutter create` adds a counter-app test that doesn't apply to this app.
  final f = File('test/widget_test.dart');
  if (f.existsSync() && f.readAsStringSync().contains('MyApp')) {
    f.deleteSync();
    stdout.writeln('Removed template test/widget_test.dart');
  }
}

void _patchAndroidManifest() {
  final f = File('android/app/src/main/AndroidManifest.xml');
  if (!f.existsSync()) {
    stderr.writeln('Android manifest not found. Did you run `flutter create`?');
    exitCode = 1;
    return;
  }
  var xml = f.readAsStringSync();
  xml = xml.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="$appName"');
  // Permissions also come from the radio_info plugin manifest; listing them
  // here makes them explicit and covers INTERNET for release builds.
  const perms = [
    'android.permission.INTERNET',
    'android.permission.ACCESS_NETWORK_STATE',
    'android.permission.ACCESS_WIFI_STATE',
    'android.permission.READ_PHONE_STATE',
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
  ];
  final missing = perms.where((p) => !xml.contains('"$p"')).toList();
  if (missing.isNotEmpty) {
    final lines = missing.map((p) => '    <uses-permission android:name="$p" />').join('\n');
    final m = RegExp(r'<manifest[^>]*>').firstMatch(xml)!;
    xml = xml.replaceRange(m.end, m.end, '\n$lines');
  }
  f.writeAsStringSync(xml);
  stdout.writeln('Patched AndroidManifest.xml');
}

void _patchAndroidAppId(String id) {
  for (final name in ['android/app/build.gradle.kts', 'android/app/build.gradle']) {
    final f = File(name);
    if (!f.existsSync()) continue;
    var g = f.readAsStringSync();
    g = g.replaceAll(RegExp(r'applicationId\s*=?\s*"[^"]*"'), 'applicationId = "$id"');
    f.writeAsStringSync(g);
    stdout.writeln('Set Android applicationId to $id');
  }
}

void _patchInfoPlist() {
  final f = File('ios/Runner/Info.plist');
  if (!f.existsSync()) {
    stdout.writeln('iOS Info.plist not found (skipping iOS).');
    return;
  }
  var plist = f.readAsStringSync();

  plist = _setString(plist, 'CFBundleDisplayName', appName);
  plist = _setString(plist, 'NSLocationWhenInUseUsageDescription',
      'WiFi Analytics records your GPS location with each network test and site.');
  plist = _setString(plist, 'NSLocationAlwaysAndWhenInUseUsageDescription',
      'WiFi Analytics records your GPS location with each network test and site.');
  plist = _setBool(plist, 'ITSAppUsesNonExemptEncryption', false);
  plist = _setBool(plist, 'UIFileSharingEnabled', true);
  plist = _setBool(plist, 'LSSupportsOpeningDocumentsInPlace', true);

  f.writeAsStringSync(plist);
  stdout.writeln('Patched Info.plist');
}

String _setString(String plist, String key, String value) {
  final existing = RegExp('<key>$key</key>\\s*<string>[^<]*</string>');
  final entry = '<key>$key</key>\n\t<string>$value</string>';
  if (existing.hasMatch(plist)) return plist.replaceFirst(existing, entry);
  return _insert(plist, entry);
}

String _setBool(String plist, String key, bool value) {
  final existing = RegExp('<key>$key</key>\\s*<(true|false)/>');
  final entry = '<key>$key</key>\n\t<${value ? 'true' : 'false'}/>';
  if (existing.hasMatch(plist)) return plist.replaceFirst(existing, entry);
  return _insert(plist, entry);
}

String _insert(String plist, String entry) {
  final idx = plist.lastIndexOf('</dict>');
  return '${plist.substring(0, idx)}\t$entry\n${plist.substring(idx)}';
}

void _patchIosBundleId(String id) {
  final f = File('ios/Runner.xcodeproj/project.pbxproj');
  if (!f.existsSync()) return;
  var p = f.readAsStringSync();
  // Only the app target (not RunnerTests, which ends in .RunnerTests).
  p = p.replaceAllMapped(
    RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);'),
    (m) => m[1]!.contains('RunnerTests')
        ? 'PRODUCT_BUNDLE_IDENTIFIER = $id.RunnerTests;'
        : 'PRODUCT_BUNDLE_IDENTIFIER = $id;',
  );
  f.writeAsStringSync(p);
  stdout.writeln('Set iOS bundle identifier to $id');
}
