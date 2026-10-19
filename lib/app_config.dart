/// Build-time switches, set by the Codemagic workflow with --dart-define.
///
/// Main app:  Wi-Fi_Analytics_v1.3
/// Debug app: Analytics_debug_ver1.0 (separate install, also records logcat)
const bool kDebugApp = bool.fromEnvironment('DEBUG_APP');
const String kAppName = String.fromEnvironment('APP_NAME', defaultValue: 'Wi-Fi_Analytics_v1.3');
