import 'dart:math';

/// Output file names:
///   Field|Lab _ Make _ Model _ build (last 4) _ profile _ Location _ IMEI (last 4)
///   e.g. Field_Samsung_S25_ylz1_walk_DAL_3245
///        Lab_iPhone_17ProMax_26.5.2_stationary_DEN_5678

/// "Samsung", "Pixel", "iPhone", or the OEM name capitalized.
String makeLabel(Map<String, dynamic> device) {
  final m = (device['make'] ?? '').toString().trim();
  final model = (device['model'] ?? '').toString();
  switch (m.toLowerCase()) {
    case 'samsung':
      return 'Samsung';
    case 'google':
      return 'Pixel';
    case 'apple':
      return model.startsWith('iPad') ? 'iPad' : 'iPhone';
    case 'motorola':
      return 'Motorola';
    case 'oneplus':
      return 'OnePlus';
    case '':
      return 'Phone';
  }
  return m[0].toUpperCase() + m.substring(1);
}

/// Short model name: "S25+", "S25Ultra", "S25E", "ZFold7", "10ProXL", "17ProMax".
String modelLabel(Map<String, dynamic> device) {
  final make = (device['make'] ?? '').toString().toLowerCase();
  final model = (device['model'] ?? '').toString().trim();
  final market = (device['marketName'] ?? '').toString().trim();
  String compact(String s) => s.replaceAll(RegExp(r'\s+'), '');

  if (make == 'apple') {
    final name = _iphones[model];
    return name != null ? compact(name) : model.replaceAll(',', '-');
  }
  if (make == 'google') {
    // Build.MODEL is already the marketing name: "Pixel 10 Pro XL".
    return compact(model.replaceFirst(RegExp(r'^Pixel\s*', caseSensitive: false), ''));
  }
  if (make == 'samsung') {
    // SM-S936U -> "S936" -> S25+
    final code = RegExp(r'^SM-([A-Z]\d{3})').firstMatch(model.toUpperCase())?[1];
    final name = code == null ? null : _samsung[code];
    if (name != null) return name;
    if (market.toLowerCase().startsWith('galaxy ')) {
      return compact(market.substring(7))
          .replaceAll('Ultra', 'U')
          .replaceAll('Edge', 'E');
    }
  }
  return compact(model);
}

/// Last 4 characters of the software build: Samsung "S938USQS4AYI1" -> "AYI1",
/// Pixel "13531031" -> "1031". iPhone: the full iOS version ("26.5.2").
String buildLabel(Map<String, dynamic> device) {
  final make = (device['make'] ?? '').toString().toLowerCase();
  final b = (device['buildIncremental'] ?? '').toString().trim();
  if (b.isEmpty) return 'build';
  if (make == 'apple') return b;
  final clean = b.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  return clean.length <= 4 ? clean : clean.substring(clean.length - 4);
}

/// A market code for a point: nearest city in [markets] within 80 km.
String? marketCode(double lat, double lon) {
  String? best;
  var bestKm = 80.0;
  for (final (code, mLat, mLon) in markets) {
    final km = _km(lat, lon, mLat, mLon);
    if (km < bestKm) {
      bestKm = km;
      best = code;
    }
  }
  return best;
}

double _km(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  double rad(double d) => d * pi / 180;
  final dLat = rad(lat2 - lat1), dLon = rad(lon2 - lon1);
  final a = sin(dLat / 2) * sin(dLat / 2) + cos(rad(lat1)) * cos(rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
  return 2 * r * asin(min(1.0, sqrt(a)));
}

/// File-name-safe text (keeps + and . for "S25+" and "26.5.2").
String fileSafe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9.+-]+'), '-');

/// City / market codes, matched to the nearest one by GPS (or the site's
/// coordinates). Henry County and Macon are listed separately from Atlanta.
const markets = <(String, double, double)>[
  ('DEN', 39.7392, -104.9903), // Denver metro (incl. the lab)
  ('COS', 38.8339, -104.8214), // Colorado Springs
  ('DAL', 32.7767, -96.7970),
  ('FTW', 32.7555, -97.3308),
  ('AUS', 30.2672, -97.7431),
  ('SAT', 29.4241, -98.4936),
  ('HOU', 29.7604, -95.3698),
  ('ELP', 31.7619, -106.4850),
  ('ATL', 33.7490, -84.3880),
  ('HEN', 33.4473, -84.1469), // Henry County GA (McDonough)
  ('MAC', 32.8407, -83.6324), // Macon GA
  ('AUG', 33.4735, -82.0105),
  ('SAV', 32.0809, -81.0912),
  ('CLT', 35.2271, -80.8431),
  ('RAL', 35.7796, -78.6382),
  ('DUR', 35.9940, -78.8986),
  ('GSO', 36.0726, -79.7920),
  ('WIN', 36.0999, -80.2442), // Winston-Salem
  ('GVL', 34.8526, -82.3940), // Greenville SC
  ('COL', 34.0007, -81.0348), // Columbia SC
  ('CHS', 32.7765, -79.9311),
  ('WIL', 34.2257, -77.9447), // Wilmington NC
  ('BHM', 33.5186, -86.8104),
  ('TPA', 27.9506, -82.4572),
  ('ORL', 28.5383, -81.3792),
  ('LOU', 38.2527, -85.7585),
  ('LEX', 38.0406, -84.5037),
  ('CIN', 39.1031, -84.5120),
  ('CMH', 39.9612, -82.9988), // Columbus OH
  ('CLE', 41.4993, -81.6944),
  ('DAY', 39.7589, -84.1916),
  ('AKR', 41.0814, -81.5190),
  ('STL', 38.6270, -90.1994),
  ('KC', 39.0997, -94.5786),
  ('MKE', 43.0389, -87.9065),
  ('MAD', 43.0731, -89.4012),
  ('GRB', 44.5133, -88.0133), // Green Bay
  ('MSP', 44.9778, -93.2650),
  ('NYC', 40.7128, -74.0060),
  ('ALB', 42.6526, -73.7562),
  ('SYR', 43.0481, -76.1474),
  ('ROC', 43.1566, -77.6088),
  ('BUF', 42.8864, -78.8784),
  ('LA', 34.0522, -118.2437),
  ('SD', 32.7157, -117.1611),
  ('RNO', 39.5296, -119.8138),
  ('HON', 21.3069, -157.8583),
  ('NSH', 36.1627, -86.7816),
  ('BOS', 42.3601, -71.0589),
  ('CHI', 41.8781, -87.6298),
];

/// Samsung model code (from SM-xxxxx) to short name.
const _samsung = <String, String>{
  // Galaxy S25
  'S931': 'S25', 'S936': 'S25+', 'S938': 'S25U', 'S937': 'S25E', 'S731': 'S25FE',
  // Galaxy S24
  'S921': 'S24', 'S926': 'S24+', 'S928': 'S24U', 'S721': 'S24FE',
  // Galaxy S23
  'S911': 'S23', 'S916': 'S23+', 'S918': 'S23U', 'S711': 'S23FE',
  // Galaxy S22
  'S901': 'S22', 'S906': 'S22+', 'S908': 'S22U',
  // Foldables
  'F966': 'ZFold7', 'F766': 'ZFlip7', 'F761': 'ZFlip7FE',
  'F956': 'ZFold6', 'F741': 'ZFlip6', 'F946': 'ZFold5', 'F731': 'ZFlip5',
  'F936': 'ZFold4', 'F721': 'ZFlip4',
  // A series (US)
  'A166': 'A16', 'A266': 'A26', 'A366': 'A36', 'A566': 'A56',
  'A156': 'A15', 'A256': 'A25', 'A356': 'A35', 'A556': 'A55',
};

/// iPhone hardware identifiers to names.
const _iphones = <String, String>{
  'iPhone12,1': '11', 'iPhone12,3': '11 Pro', 'iPhone12,5': '11 Pro Max', 'iPhone12,8': 'SE2',
  'iPhone13,1': '12 mini', 'iPhone13,2': '12', 'iPhone13,3': '12 Pro', 'iPhone13,4': '12 Pro Max',
  'iPhone14,4': '13 mini', 'iPhone14,5': '13', 'iPhone14,2': '13 Pro', 'iPhone14,3': '13 Pro Max',
  'iPhone14,6': 'SE3', 'iPhone14,7': '14', 'iPhone14,8': '14 Plus', 'iPhone15,2': '14 Pro',
  'iPhone15,3': '14 Pro Max', 'iPhone15,4': '15', 'iPhone15,5': '15 Plus', 'iPhone16,1': '15 Pro',
  'iPhone16,2': '15 Pro Max', 'iPhone17,3': '16', 'iPhone17,4': '16 Plus', 'iPhone17,1': '16 Pro',
  'iPhone17,2': '16 Pro Max', 'iPhone17,5': '16e', 'iPhone18,3': '17', 'iPhone18,4': 'Air',
  'iPhone18,1': '17 Pro', 'iPhone18,2': '17 Pro Max',
};
