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

/// Several reflectors, comma separated (--dart-define=TWAMP_HOSTS=a:862,b:862). The app tests each one and uses the best
/// (no loss first, then lowest round-trip time) when Settings has no reflector.
const String kReflectorList = String.fromEnvironment('TWAMP_HOSTS');

/// Test settings fixed at build time with --dart-define, applied on every start (for phones where typing in Settings
/// is not possible). -1 or blank = leave the saved setting alone. UDP_DURATION=0 runs until Stop.
const int kUdpDuration = int.fromEnvironment('UDP_DURATION', defaultValue: -1);
const int kUdpMbps = int.fromEnvironment('UDP_MBPS', defaultValue: -1);
const int kUdpParallel = int.fromEnvironment('UDP_PARALLEL', defaultValue: -1);
const int kTcpDuration = int.fromEnvironment('TCP_DURATION', defaultValue: -1);
const int kTcpParallel = int.fromEnvironment('TCP_PARALLEL', defaultValue: -1);
const String kIperfServer = String.fromEnvironment('IPERF_SERVER'); // host or host:port
