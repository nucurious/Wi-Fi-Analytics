// Finishes the generated iOS / Android project folders for WiFi Analytics.
//
// Run from the project root AFTER `flutter create`:
//   dart run tool/setup.dart
//
// Optional environment variables:
//   APP_NAME    name under the app icon (default Wi-Fi_Analytics_v1.3)
//   DEBUG_APP   "true" for the debug app: adds READ_LOGS (granted later with
//               adb shell pm grant <id> android.permission.READ_LOGS)
//   BUNDLE_ID   iOS bundle identifier / Android application ID
//               (e.g. com.yourname.wifianalytics). Must match what you
//               registered with Apple.
//
// Safe to run more than once.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

final appName = (Platform.environment['APP_NAME']?.trim().isNotEmpty ?? false)
    ? Platform.environment['APP_NAME']!.trim()
    : 'Wi-Fi_Analytics_v1.3';
final debugApp = Platform.environment['DEBUG_APP'] == 'true';

void main() {
  final bundleId = Platform.environment['BUNDLE_ID']?.trim();
  _removeTemplateTest();
  _patchAndroidManifest();
  if (Platform.environment['PROV'] == 'true') _installProvIcon();
  if (bundleId != null && bundleId.isNotEmpty) _patchAndroidAppId(bundleId);
  _patchInfoPlist();
  if (Platform.environment['PROV'] == 'true') _installProvIosIcon();
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
    'android.permission.CHANGE_WIFI_STATE',
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
  if (debugApp && !xml.contains('android.permission.READ_LOGS')) {
    // A development permission: only adb can grant it. tools:ignore keeps the
    // release lint check from failing the build.
    if (!xml.contains('xmlns:tools=')) {
      xml = xml.replaceFirst('<manifest ', '<manifest xmlns:tools="http://schemas.android.com/tools" ');
    }
    final m = RegExp(r'<manifest[^>]*>').firstMatch(xml)!;
    xml = xml.replaceRange(m.end, m.end,
        '\n    <uses-permission android:name="android.permission.READ_LOGS" tools:ignore="ProtectedPermissions" />');
  }
  if (Platform.environment['VIDEO_CALL'] == 'true') {
    // Video Call Analytics: foreground service so logging continues while a call app is on screen.
    const fg = [
      'android.permission.FOREGROUND_SERVICE',
      'android.permission.FOREGROUND_SERVICE_LOCATION',
      'android.permission.FOREGROUND_SERVICE_DATA_SYNC',
      'android.permission.POST_NOTIFICATIONS',
      'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
      'android.permission.WAKE_LOCK',
    ];
    final miss = fg.where((p) => !xml.contains('"$p"')).toList();
    if (miss.isNotEmpty) {
      final lines = miss.map((p) => '    <uses-permission android:name="$p" />').join('\n');
      final m = RegExp(r'<manifest[^>]*>').firstMatch(xml)!;
      xml = xml.replaceRange(m.end, m.end, '\n$lines');
    }
    if (!xml.contains('flutter_foreground_task.service.ForegroundService')) {
      xml = xml.replaceFirst('</application>',
          '    <service android:name="com.pravera.flutter_foreground_task.service.ForegroundService" android:foregroundServiceType="location|dataSync" android:exported="false" />\n  </application>');
    }
  }
  f.writeAsStringSync(xml);
  stdout.writeln('Patched AndroidManifest.xml${debugApp ? ' (debug app, READ_LOGS)' : ''}');
}

// Analytics Pro launcher icon: a small cell tower with Wi-Fi arcs (adaptive icon, Android 8+; older phones keep the default icon).
void _installProvIcon() {
  final res = 'android/app/src/main/res';
  if (!Directory('android/app/src/main').existsSync()) return;
  Directory('${res}/drawable').createSync(recursive: true);
  Directory('${res}/mipmap-anydpi-v26').createSync(recursive: true);
  const fg = r'''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
  <path android:fillColor="#FFFFFF"
      android:pathData="M54,48.5 a3.5,3.5 0 1,0 0.01,0 z" />
  <path android:strokeColor="#FFFFFF" android:strokeWidth="3.2" android:strokeLineCap="round"
      android:pathData="M46.93,44.93 A10,10 0 0,1 61.07,44.93" />
  <path android:strokeColor="#FFFFFF" android:strokeWidth="3.2" android:strokeLineCap="round"
      android:pathData="M40.57,38.57 A19,19 0 0,1 67.43,38.57" />
  <path android:strokeColor="#FFFFFF" android:strokeWidth="3.2" android:strokeLineCap="round"
      android:pathData="M34.2,32.2 A28,28 0 0,1 73.8,32.2" />
  <path android:strokeColor="#FFFFFF" android:strokeWidth="3" android:strokeLineCap="round" android:strokeLineJoin="round"
      android:pathData="M54,56 L42,88 M54,56 L66,88 M36,88 L72,88 M48,72 L60,72 M45,80 L63,80 M48,72 L63,80 M60,72 L45,80" />
</vector>
''';
  const icon = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@color/ic_launcher_background" />
  <foreground android:drawable="@drawable/ic_launcher_foreground" />
  <monochrome android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
''';
  Directory('${res}/values').createSync(recursive: true);
  File('${res}/values/ic_launcher_background.xml').writeAsStringSync(
      '<?xml version="1.0" encoding="utf-8"?>\n<resources><color name="ic_launcher_background">#0B3D91</color></resources>\n');
  File('${res}/drawable/ic_launcher_foreground.xml').writeAsStringSync(fg);
  File('${res}/mipmap-anydpi-v26/ic_launcher.xml').writeAsStringSync(icon);
  stdout.writeln('Installed Analytics Pro launcher icon');
}

// Analytics Pro iPhone icon: the same cell tower with Wi-Fi arcs, drawn here so no image files are needed.
void _installProvIosIcon() {
  final dir = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
  final contents = File(dir.path + '/Contents.json');
  if (!contents.existsSync()) return;
  final json = jsonDecode(contents.readAsStringSync()) as Map<String, dynamic>;
  var n = 0;
  for (final im in (json['images'] as List)) {
    final fn = im['filename'];
    if (fn == null) continue;
    final base = double.parse((im['size'] as String).split('x').first);
    final scale = im['scale'] == null ? 1.0 : double.parse((im['scale'] as String).replaceAll('x', ''));
    final px = (base * scale).round();
    File(dir.path + '/' + (fn as String)).writeAsBytesSync(_towerPng(px));
    n++;
  }
  stdout.writeln('Installed Analytics Pro iPhone icon (' + n.toString() + ' sizes)');
}

double _segDist(double px, double py, double ax, double ay, double bx, double by) {
  final dx = bx - ax, dy = by - ay;
  final t = (((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)).clamp(0.0, 1.0).toDouble();
  final cx = ax + t * dx, cy = ay + t * dy;
  return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
}

// Distance (in a 108 x 108 design grid) from a point to the nearest white shape; negative inside.
double _towerDist(double x, double y) {
  var d = math.sqrt((x - 54) * (x - 54) + (y - 52) * (y - 52)) - 3.5;
  const legs = <List<double>>[
    [54, 56, 42, 88], [54, 56, 66, 88], [36, 88, 72, 88], [48, 72, 60, 72], [45, 80, 63, 80], [48, 72, 63, 80], [60, 72, 45, 80],
  ];
  for (final l in legs) {
    d = math.min(d, _segDist(x, y, l[0], l[1], l[2], l[3]) - 1.5);
  }
  final vx = x - 54, vy = y - 52;
  final len = math.sqrt(vx * vx + vy * vy);
  final up = vy < 0 && vx.abs() <= -vy;
  for (final r in const [10.0, 19.0, 28.0]) {
    double a;
    if (up) {
      a = (len - r).abs();
    } else {
      final e = r * 0.70710678;
      final l1 = math.sqrt((x - (54 - e)) * (x - (54 - e)) + (y - (52 - e)) * (y - (52 - e)));
      final l2 = math.sqrt((x - (54 + e)) * (x - (54 + e)) + (y - (52 - e)) * (y - (52 - e)));
      a = math.min(l1, l2);
    }
    d = math.min(d, a - 1.6);
  }
  return d;
}

List<int> _towerPng(int s) {
  final ppu = s / 108.0;
  final raw = <int>[];
  for (var y = 0; y < s; y++) {
    raw.add(0);
    for (var x = 0; x < s; x++) {
      final d = _towerDist((x + 0.5) / ppu, (y + 0.5) / ppu);
      final c = (0.5 - d * ppu).clamp(0.0, 1.0).toDouble();
      raw.add((11 + (255 - 11) * c).round());
      raw.add((61 + (255 - 61) * c).round());
      raw.add((145 + (255 - 145) * c).round());
    }
  }
  final out = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  void chunk(String type, List<int> data) {
    final td = <int>[...type.codeUnits, ...data];
    out.addAll(_u32(data.length));
    out.addAll(td);
    out.addAll(_u32(_crc32(td)));
  }
  chunk('IHDR', [..._u32(s), ..._u32(s), 8, 2, 0, 0, 0]);
  chunk('IDAT', ZLibEncoder().convert(raw));
  chunk('IEND', <int>[]);
  return out;
}

List<int> _u32(int v) => [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255];

int _crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c ^= b;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
  }
  return c ^ 0xFFFFFFFF;
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
  if (Platform.environment['PROV'] == 'true' && !plist.contains('UIBackgroundModes')) {
    // Analytics Pro: keep logging with the screen off or another app in front.
    plist = _insert(plist, '<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>location</string>\n\t</array>');
  }

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
