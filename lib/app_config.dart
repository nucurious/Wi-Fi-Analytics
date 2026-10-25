/// Build-time switches, set by the Codemagic workflow with --dart-define.
///
/// Main app:  Wi-Fi_Analytics_v1.3
/// Debug app: Analytics_debug_ver1.0 (separate install, also records logcat)
const bool kDebugApp = bool.fromEnvironment('DEBUG_APP');
const String kAppName = String.fromEnvironment('APP_NAME', defaultValue: 'Wi-Fi_Analytics_v1.3');

/// Analytics-Prov build: phone health sampling (battery, thermal, memory, GPS and logging gaps).
const bool kProv = bool.fromEnvironment('PROV');

/// TWAMP reflector used when none is set in Settings (host or host:port), fixed at build time:
/// flutter run --release --dart-define=TWAMP_HOST=10.0.1.25:8620. Blank = no default.
const String kDefaultReflector = String.fromEnvironment('TWAMP_HOST');
