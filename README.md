# WiFi Analytics

A field network-testing app for **iPhone and Android** (one Flutter codebase).

- **On-demand speed test**: TCP download then upload against your **iperf3** server, with parallel streams.
- **UDP stream test**: download, upload or both, at a set bitrate, for a set time or continuously until stopped. Reports jitter and packet loss.
- **GPS capture**: position, accuracy, speed, heading and altitude logged every second while the app is open, and on every test sample.
- **Sites**: save named sites at your current location; the selected site is tagged on every test and log row.
- **Radio / technology info** during tests: LTE / 5G NSA / 5G SA / Wi-Fi on both platforms; full LTE and 5G NR signal metrics and Wi-Fi details on Android.
- **CSV export** via the phone's share sheet (email, Files, Drive, AirDrop).

**To build and install, follow [BUILD_GUIDE.md](BUILD_GUIDE.md).** No developer tools are needed on your computer.
CSV column definitions are in [DATA_DICTIONARY.md](DATA_DICTIONARY.md).

## Project layout

```
lib/
  main.dart                 App shell and tabs
  app_state.dart            Settings, GPS stream, radio polling, test runner, logging
  models.dart               Radio snapshot, site, test record, shared CSV columns
  iperf/iperf_client.dart   Pure-Dart iperf3 client (TCP/UDP, up/down, parallel streams)
  services/data_store.dart  CSV files in the app's documents folder
  screens/                  Test, Sites, Data, Settings screens
packages/radio_info/        Native plugin: Android (Java) cell + Wi-Fi metrics, iOS (Swift) RAT type
tool/setup.dart             Applies app name, permissions and Bundle ID after `flutter create`
codemagic.yaml              Cloud builds: Android APK and iPhone → TestFlight
```

## Notes

- The iperf3 client speaks the iperf3 3.x protocol directly, so no native iperf binary is bundled. Its protocol flow (TCP/UDP, upload/download, parallel stream numbering) was validated against an iperf3 3.16 server.
- The `android/` and `ios/` folders are generated at build time by `flutter create`, then customised by `tool/setup.dart`.
- Tests run in the foreground. Mobile operating systems suspend network tests when an app is backgrounded.
