# Wi-Fi_Analytics_v1.3

A field network-testing app for **iPhone and Android** (one Flutter codebase).

- **On-demand speed test**: TCP download then upload against your **iperf3** server, with parallel streams.
- **UDP stream test**: download, upload or both, at a set bitrate, for a set time or continuously until stopped. Reports jitter and packet loss.
- **Latency (TWAMP)**: TWAMP-Light round-trip time, jitter and loss, alongside every test (latency under load) or as a stand-alone test. Falls back to ping on Android when no reflector is set.
- **GPS capture**: position, accuracy, speed, heading and altitude logged every second while the app is open, and on every test sample.
- **Sites**: save named sites at your current location; the selected site is tagged on every test and log row.
- **Radio / technology info** during tests: LTE / 5G NSA / 5G SA / Wi-Fi on both platforms; full LTE and 5G NR signal metrics and Wi-Fi details on Android.
- **Traffic profiles**: Drive (latency + continuous UDP), Walk (speed test each time the phone joins Wi-Fi), Lab (UDP up and down at the same time) and manual tests, all running until Stop.
- **Test servers**: one-tap public server shortcuts; when a test can't start, the app moves to the next port or public server and keeps that failure out of the results.
- **Results**: one Excel workbook per session (Tests, Speed, Latency, GPS track, Server failures, Geofence, DSDS, Traffic gaps, Spectrum Wi-Fi, Sites), named like `Field_Samsung_S25_ylz1_walk_DAL_3245_20261019-1123.xlsx` and emailed automatically when the session stops; Excel or CSV export from the Data tab.
- **Geofence**: every saved site is a geofence (radius per site); entering and leaving is logged with time and GPS.
- **Dual SIM (DSDS)**, Android: data-SIM switches, IP changes and data gaps between the two SIMs (e.g. Spectrum Mobile and Verizon), with the IP owner, plus per-session statistics.
- **Spectrum Mobile Wi-Fi**, Android: every scan that hears a Spectrum SSID, time from first heard to connected (association, authentication, IP, internet validated), and time connected and sending traffic on it, with per-session statistics.
- **Debug app** (`Analytics_debug_ver1.0`, Android): everything above plus logcat for every session.

**To build and install, follow [BUILD_GUIDE.md](BUILD_GUIDE.md).** No developer tools are needed on your computer.
CSV column definitions are in [DATA_DICTIONARY.md](DATA_DICTIONARY.md).

## Contents

- [Document versions](#document-versions)
- [App and script versions](#app-and-script-versions)
- [Project layout](#project-layout)
- [Notes](#notes)

## Document versions

| Version | Date | Commit(s) | Changes |
|---|---|---|---|
| 1.0 | Oct 17, 2026 | dde7a99 | First README: features, project layout. |
| 1.1 | Oct 18, 2026 | a1f1e21 | TWAMP latency added. |
| 2.0 | Oct 19, 2026 | 78ad25f | App v1.3 and debug app: profiles, server switching, file naming, workbook and email; project layout; version tables. |
| 2.1 | Oct 19, 2026 | 994535f | Geofence and dual-SIM (DSDS) logs; app 1.3.1. |
| 2.2 | Oct 19, 2026 | b5ec863 | Spectrum HMNO CBRS geofence (541 areas); Hand In / Hand Out transition performance. |
| 2.3 | Oct 19, 2026 | 96fa286 | Table of contents; app 1.3.2 / debug 1.0.2 (UI freeze fix, UI stalls sheet). |
| 2.4 | Oct 20, 2026 | 357ba31 | App 1.3.3 to 1.3.6 / debug 1.0.3 to 1.0.6: fast Stop, run folders, settings auto-save, continuous UDP down + up, restart on data-SIM switch, Traffic gaps and user-plane interruption (IP level, higher than PDCP), public servers only. |
| 2.5 | Oct 20, 2026 | 9270aa1 | App 1.3.7 / debug 1.0.7: Spectrum Mobile Wi-Fi scans, time to connect and time on it (Spectrum Wi-Fi visits, Wi-Fi scans, Wi-Fi connection steps, Wi-Fi join performance). |
| 2.6 | Oct 20, 2026 | 803d6fa | App 1.3.8 / debug 1.0.8: freeze tracking (Mark freeze, recent events and Android main-thread stack on UI stalls); faster restart on network change; versioned APK names. |

## App and script versions

| App / script | Version | Date | Commit(s) | Changes |
|---|---|---|---|---|
| Wi-Fi Analytics (Android) | 1.0 | Oct 17, 2026 | dde7a99 | First version in the repository: iperf3 TCP/UDP, ping latency, GPS and radio logging, sites, CSV export. |
| Wi-Fi Analytics (Android) | 1.1 | Oct 18, 2026 | a1f1e21 to 72ca927 (Codemagic build 8) | TWAMP latency during every test; Wi-Fi generation and BSSID; long runs; Drive and Walk profiles; email when a session stops; Excel workbook; screen-freeze fixes. |
| Wi-Fi Analytics (Android) | 1.2 | Oct 18-19, 2026 | 90fe7a5 to f33eaac | Lab server as default with shortcuts; address:port parsing and repair of saved addresses; 11 public servers; automatic port/server switching; Server failures sheet. |
| Wi-Fi_Analytics_v1.3 (Android) | 1.3.0 | Oct 19, 2026 | 9313d12 to 1c9fce9 | File names Field\|Lab_Make_Model_build_profile_LOC_IMEI_date-time; Lab profile (UDP up and down together); app renamed; Field unless the Lab profile runs; exports named _all_; walk tests only on Wi-Fi; tests stopped before data not recorded. |
| Analytics_debug_ver1.0 (Android) | 1.0.0 | Oct 19, 2026 | aaafbb5 to 1c9fce9 | Separate debug app: everything in v1.3 plus logcat per session (logcat -b all -v time, rotating files, gzipped and emailed; adb-pullable). |
| Wi-Fi_Analytics_v1.3 (Android) | 1.3.1 | Oct 19, 2026 | 5bfc334 to b5ec863 | Geofence: Spectrum HMNO CBRS geofence built in (GeoFence_20260708.json, 541 areas) plus saved sites; Entered / Exited with time and GPS on a Geofence sheet. Dual SIM (DSDS): data-SIM switches (Hand In / Hand Out, success, switch time), IP changes and data gaps on a DSDS transitions sheet, and a Transition performance sheet per session (count, successful, mean, median, min, max, std dev); data SIM and cellular IP on every row. |
| Analytics_debug_ver1.0 (Android) | 1.0.1 | Oct 19, 2026 | 5bfc334 to b5ec863 | Same new features as 1.3.1, plus logcat as before. |
| Wi-Fi_Analytics_v1.3 (Android) | 1.3.2 | Oct 19, 2026 | 96fa286 | UI freeze fix: radio, Wi-Fi and SIM reads moved off the Android main thread. New UI stalls sheet (app thread, slow frames, Android main thread, slow native calls) with what was running. |
| Analytics_debug_ver1.0 (Android) | 1.0.2 | Oct 19, 2026 | 96fa286 | Same as 1.3.2, plus logcat as before. |
| Wi-Fi_Analytics_v1.3 (Android) | 1.3.3 | Oct 19, 2026 | 1def654 | Stop ends the test at once: connection attempts cancelled, final result exchange limited to 3 s, quick latency stop; button shows Stopping. |
| Wi-Fi_Analytics_v1.3 (Android) | 1.3.4 | Oct 19, 2026 | e28d220, 242c053 | Tests with no data for 15 s end with an error instead of running at 0 Mbps; walk tests skipped on Wi-Fi without internet; no false Data lost while on Wi-Fi. One folder per test run (workbook, summary, logcat) with Export buttons on the Test and Data screens. |
| Wi-Fi_Analytics_v1.3 (Android) | 1.3.5 | Oct 20, 2026 | e82a255 | Survives data-SIM switches: the test restarts on a network change instead of failing (Send failed: Network is unreachable). UDP duration 0 runs download and upload together until Stop. User-plane interruption from the traffic (UDP packet gaps over 0.3 s, lost latency probes): Traffic gaps sheet and UP rows in Transition performance. Settings save automatically. |
| Wi-Fi_Analytics_v1.3 (Android) | 1.3.6 | Oct 20, 2026 | 357ba31 | Public iperf3 servers only: lab server shortcuts removed; saved lab addresses move to Clouvider Dallas (default dal.speedtest.clouvider.net:5200). |
| Analytics_debug_ver1.0 (Android) | 1.0.3 to 1.0.6 | Oct 19-20, 2026 | 1def654 to 357ba31 | Same as 1.3.3 to 1.3.6, plus logcat as before (logcat stored in each run folder). |
| Wi-Fi_Analytics_v1.3 (Android) | 1.3.7 | Oct 20, 2026 | 9270aa1 to fbfbf9a | Spectrum Mobile Wi-Fi: every scan that hears a Spectrum SSID (Wi-Fi scans sheet); per visit, time from first heard to connected with association, authentication, IP and internet-validated steps, join failures, time connected and time sending traffic, MB (Spectrum Wi-Fi visits); Wi-Fi connection steps; Wi-Fi join performance per session. App asks for a scan every 30 s. Data-tab exports start with Lab, Mixed or Field according to the tests in them. On a network change the test is dropped at once and restarted (0.1 s checks; restart time on Traffic gaps); Test screen shows "No data for N s" instead of a bare 0.0 and "IP already up · traffic stopped X s" for switches. APK file names carry the version. |
| Analytics_debug_ver1.0 (Android) | 1.0.7 | Oct 20, 2026 | 9270aa1 to fbfbf9a | Same as 1.3.7, plus logcat as before. |
| Wi-Fi_Analytics_v1.3 (Android) | 1.3.8 | Oct 20, 2026 | 803d6fa (current) | Freeze tracking: Mark freeze button on the Test screen; UI stalls rows carry the app events just before the freeze and, for Android main-thread freezes, where the main thread was stuck (stack captured 0.7 s in); stalls written to disk at once. |
| Analytics_debug_ver1.0 (Android) | 1.0.8 | Oct 20, 2026 | 803d6fa (current) | Same as 1.3.8, plus logcat as before. |
| Wi-Fi Analytics (iPhone) | 1.3.8 (code) | Oct 20, 2026 | 803d6fa (current) | Same code as Android 1.3.8 (geofence works on iPhone; DSDS is Android only). Not built yet: needs Bundle ID and App Store Connect key. |
| setup-windows-test-server.ps1 (lab server) | 1.0 | Oct 18, 2026 | 7be8bc7 | iperf3 3.21 on ports 5201-5205 and TWAMP reflector on UDP 862, start at boot, firewall rules, self-test. Not used by the app from 1.3.6 (public servers only); kept in the repository for later. |
| wifi_analytics.py (log/PCAP analyzer, PC) | v5.14 | Oct 16, 2026 | Golden PY folder; Google Drive | Device-IP and DDS/subscription classification separating Wi-Fi, Spectrum Mobile on Verizon and Spectrum HMNO; registry-checked carrier IP ranges; Classification Basis sheet (section 12). |

Versions 1.0 to 1.2 are labels given afterwards to group the builds; those APKs show 1.0.0 in Android settings. From 1.3 the version is set in the build. Commits are in github.com/nucurious/Wi-Fi-Analytics.

## Project layout

```
lib/
  main.dart                    App shell and tabs
  app_config.dart              App name and debug-app switch (set at build time)
  app_state.dart               Settings, GPS, radio polling, profiles, test runner, server switching, sessions
  models.dart                  Radio snapshot, site, test record, shared CSV columns
  iperf/iperf_client.dart      Pure-Dart iperf3 client (TCP/UDP, up/down, parallel streams)
  iperf/iperf_background.dart  Runs the client on a background isolate
  iperf/server_pool.dart       Public servers and the switching order
  latency/latency_probe.dart   TWAMP-Light and ping probes
  services/data_store.dart     CSV logs, exports
  services/xlsx_writer.dart    Excel workbook writer
  services/session_mailer.dart Session workbook + Gmail SMTP outbox
  services/logcat_recorder.dart Debug app: logcat per session
  services/geofence_tracker.dart Geofence enter/exit per site
  services/dsds_tracker.dart   Dual-SIM data transitions and session stats
  util/file_naming.dart        Output file names (model names, market codes)
  util/host_address.dart       Server address / port parsing
  screens/                     Test, Sites, Data, Settings screens
packages/radio_info/           Native plugin: Android (Java) cell + Wi-Fi metrics, iOS (Swift)
server/                        Windows lab server setup (iperf3 x5 + TWAMP reflector)
tool/setup.dart                Applies app name, permissions and IDs after `flutter create`
codemagic.yaml                 Cloud builds: Android APK, Android Debug APK (logcat), iPhone TestFlight
```

## Notes

- The iperf3 client speaks the iperf3 3.x protocol directly, so no native iperf binary is bundled. Its protocol flow (TCP/UDP, upload/download, parallel stream numbering) was validated against an iperf3 3.16 server.
- The `android/` and `ios/` folders are generated at build time by `flutter create`, then customised by `tool/setup.dart`.
- Tests run in the foreground. Mobile operating systems suspend network tests when an app is backgrounded.
