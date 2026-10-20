# Wi-Fi_Analytics_v1.3: Build & Install Guide

This guide gets the app onto your phones **without installing any developer tools on your computer**. A free cloud service, **Codemagic**, builds the app for you:

- **Android:** Codemagic gives you an `.apk` file you install directly on the phone.
- **iPhone:** Codemagic builds the app and sends it to **TestFlight**, then you install it with Apple's TestFlight app.

Plan on about an hour the first time. After that, a new build is one click.

## Contents

- [Document versions](#document-versions)
- [App and script versions](#app-and-script-versions)
- [What you need](#what-you-need)
- [Step 1: Put the project on GitHub](#step-1-put-the-project-on-github)
- [Step 2: Connect Codemagic](#step-2-connect-codemagic)
- [Step 3: Build the Android app](#step-3-build-the-android-app)
- [Step 4: Set up iPhone builds (one time)](#step-4-set-up-iphone-builds-one-time)
  - [4a. Renew your Apple Developer membership](#4a-renew-your-apple-developer-membership)
  - [4b. Choose and register a Bundle ID](#4b-choose-and-register-a-bundle-id)
  - [4c. Create the app in App Store Connect](#4c-create-the-app-in-app-store-connect)
  - [4d. Create an API key so Codemagic can upload for you](#4d-create-an-api-key-so-codemagic-can-upload-for-you)
  - [4e. Add the key to Codemagic](#4e-add-the-key-to-codemagic)
  - [4f. Put your Bundle ID in the project](#4f-put-your-bundle-id-in-the-project)
- [Step 5: Build for iPhone and install via TestFlight](#step-5-build-for-iphone-and-install-via-testflight)
- [Step 6: First run](#step-6-first-run)
- [Your iperf3 server checklist](#your-iperf3-server-checklist)
- [Your TWAMP reflector (for latency)](#your-twamp-reflector-for-latency)
- [Test servers and automatic switching](#test-servers-and-automatic-switching)
- [Traffic profiles (Test tab)](#traffic-profiles-test-tab)
- [Geofence and dual-SIM (DSDS) logs](#geofence-and-dual-sim-dsds-logs)
- [Emailing results automatically](#emailing-results-automatically)
- [Overnight and weekend runs](#overnight-and-weekend-runs)
- [What the app records on each platform](#what-the-app-records-on-each-platform)
- [Troubleshooting](#troubleshooting)
- [Alternative: building on your own computer](#alternative-building-on-your-own-computer)
- [Debug app: Analytics_debug_ver1.0 (records logcat)](#debug-app-analytics_debug_ver10-records-logcat)

## Document versions

| Version | Date | Commit(s) | Changes |
|---|---|---|---|
| 1.0 | Oct 17, 2026 | dde7a99 | First guide: GitHub, Codemagic, Android and iPhone builds, first run, server checklist. |
| 1.1 | Oct 18, 2026 | a1f1e21, b210737 | TWAMP reflector; overnight and weekend runs. |
| 1.2 | Oct 18, 2026 | 4dd5252, bc020ac, 72ca927 | Traffic profiles; email results; Excel workbook. |
| 1.3 | Oct 18, 2026 | 90fe7a5 | Lab iperf3 server. |
| 1.4 | Oct 19, 2026 | aaafbb5, 2f2829b | Debug app and logcat capture. |
| 2.0 | Oct 19, 2026 | 78ad25f | App v1.3: APK names, Lab profile, test servers and automatic switching, lab server status, file naming, version tables. |
| 2.1 | Oct 19, 2026 | 994535f | Geofence and dual-SIM (DSDS) logs section; app 1.3.1 / debug 1.0.1. |
| 2.2 | Oct 19, 2026 | b5ec863 | Spectrum HMNO CBRS geofence (541 areas); Hand In / Hand Out transition performance. |
| 2.3 | Oct 19, 2026 | 96fa286 | Table of contents; app 1.3.2 / debug 1.0.2 (UI freeze fix, UI stalls sheet). |
| 2.4 | Oct 20, 2026 | 357ba31 | App 1.3.3 to 1.3.6 / debug 1.0.3 to 1.0.6: fast Stop, run folders, settings auto-save, continuous UDP down + up, restart on data-SIM switch, Traffic gaps and user-plane interruption (IP level, higher than PDCP), public servers only. |

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
| Wi-Fi_Analytics_v1.3 (Android) | 1.3.6 | Oct 20, 2026 | 357ba31 (current) | Public iperf3 servers only: lab server shortcuts removed; saved lab addresses move to Clouvider Dallas (default dal.speedtest.clouvider.net:5200). |
| Analytics_debug_ver1.0 (Android) | 1.0.3 to 1.0.6 | Oct 19-20, 2026 | 1def654 to 357ba31 (current) | Same as 1.3.3 to 1.3.6, plus logcat as before (logcat stored in each run folder). |
| Wi-Fi Analytics (iPhone) | 1.3.6 (code) | Oct 20, 2026 | 357ba31 | Same code as Android 1.3.6 (geofence works on iPhone; DSDS is Android only). Not built yet: needs Bundle ID and App Store Connect key. |
| setup-windows-test-server.ps1 (lab server) | 1.0 | Oct 18, 2026 | 7be8bc7 | iperf3 3.21 on ports 5201-5205 and TWAMP reflector on UDP 862, start at boot, firewall rules, self-test. Not used by the app from 1.3.6 (public servers only); kept in the repository for later. |
| wifi_analytics.py (log/PCAP analyzer, PC) | v5.14 | Oct 16, 2026 | Golden PY folder; Google Drive | Device-IP and DDS/subscription classification separating Wi-Fi, Spectrum Mobile on Verizon and Spectrum HMNO; registry-checked carrier IP ranges; Classification Basis sheet (section 12). |

Versions 1.0 to 1.2 are labels given afterwards to group the builds; those APKs show 1.0.0 in Android settings. From 1.3 the version is set in the build. Commits are in github.com/nucurious/Wi-Fi-Analytics.

---

## What you need

| | Android | iPhone |
|---|---|---|
| A free **GitHub** account (github.com) | ✅ | ✅ |
| A free **Codemagic** account (codemagic.io) | ✅ | ✅ |
| An **Apple Developer** membership ($99/yr) | | ✅ |
| Your **iperf3 server** address and port | ✅ | ✅ |

---

## Step 1: Put the project on GitHub

1. Sign in at **github.com** → click **+** (top right) → **New repository**.
2. Name it `wifi-analytics`, choose **Private**, and click **Create repository**.
3. On the next page, click **uploading an existing file**.
4. Unzip `wifi_analytics.zip` on your computer. Open the `wifi_analytics` folder, select **everything inside it** (including the `lib`, `packages` and `tool` folders) and drag it onto the GitHub page.
   - Hidden files like `.gitignore` may not be visible; that's fine.
5. Click **Commit changes**.

Check: the repository's main page should show `codemagic.yaml`, `pubspec.yaml`, and folders `lib`, `packages`, `tool`. If you see a single `wifi_analytics` folder instead, you uploaded the folder itself; delete the repo and upload its *contents*.

---

## Step 2: Connect Codemagic

1. Go to **codemagic.io** → **Sign up** → choose **Sign up with GitHub** and allow access.
2. Click **Add application** → **GitHub** → pick `wifi-analytics`.
3. When asked for the project type, choose **Flutter App**. Codemagic will detect `codemagic.yaml` automatically.

---

## Step 3: Build the Android app

1. In Codemagic, open the app and click **Start new build**.
2. Choose the workflow **Android APK** (or **Android Debug APK (logcat)** for the debug app) and click **Start new build**.
3. Wait about 15 minutes for a green ✅.
4. Under **Artifacts**, download `Wi-Fi_Analytics_v1.3.apk` (debug app: `Analytics_debug_ver1.0.apk`). Both can be installed on the same phone.

**Install it on the Android phone:**

1. Send the `.apk` to the phone (email it to yourself, or put it in Google Drive) and tap it.
2. Android will ask to **allow installs from this source**. Allow it, then tap **Install**.
3. If Google Play Protect warns about an unknown app, tap **More details → Install anyway**. This appears because the app isn't from the Play Store.

---

## Step 4: Set up iPhone builds (one time)

### 4a. Renew your Apple Developer membership
Sign in at **developer.apple.com/account**. If it shows the membership expired, click **Renew**. It's active again right after payment.

### 4b. Choose and register a Bundle ID
A Bundle ID is the app's unique name in Apple's system, written like a reversed web address. Pick one that's yours, for example `com.yourname.wifianalytics` (lowercase, no spaces).

1. Go to **developer.apple.com/account** → **Certificates, IDs & Profiles** → **Identifiers** → **+**.
2. Choose **App IDs** → **App** → Continue.
3. Description: `WiFi Analytics`. Bundle ID: **Explicit**, enter your ID. Leave capabilities as they are. Click **Continue → Register**.

### 4c. Create the app in App Store Connect
1. Go to **appstoreconnect.apple.com** → **Apps** → **+** → **New App**.
2. Platform **iOS**, Name `WiFi Analytics` (if taken, add something like your company name), language English, Bundle ID: the one you just registered, SKU: `wifianalytics1`.
3. Click **Create**. You don't need to fill in store details for TestFlight.

### 4d. Create an API key so Codemagic can upload for you
1. In **App Store Connect** → **Users and Access** → **Integrations** tab → **App Store Connect API** → **Team Keys** → **+**.
2. Name: `Codemagic`, Access: **App Manager** → **Generate**.
3. Note the **Issuer ID** (top of the page) and the **Key ID**, then click **Download API Key**. Save the `.p8` file; Apple only lets you download it once.

### 4e. Add the key to Codemagic
1. In Codemagic, click your profile/team → **Integrations** (under Team settings or User settings) → **Developer Portal** → **Manage keys** → **Add key**.
2. **App Store Connect API key name:** type exactly `WiFi Analytics key`
3. Enter the **Issuer ID** and **Key ID**, and upload the `.p8` file. Save.

### 4f. Put your Bundle ID in the project
1. On GitHub, open `codemagic.yaml` and click the ✏️ pencil icon.
2. Replace `com.example.wifianalytics` with your Bundle ID **on all three lines marked `CHANGE-ME`**.
3. Click **Commit changes**.

---

## Step 5: Build for iPhone and install via TestFlight

1. In Codemagic, **Start new build** → workflow **iPhone TestFlight** → **Start new build**.
2. Wait for ✅ (about 15–20 minutes). Codemagic uploads to TestFlight automatically.
3. Apple then processes the build for 5–30 minutes. You'll get an email when it's ready.
4. In **App Store Connect** → your app → **TestFlight** tab:
   - If the build shows **Missing Compliance**, click it and answer **None of the algorithms mentioned above** (the app is already set up to skip this, so you'll usually not see it).
   - Under **Internal Testing**, click **+** to create a group, add yourself (your Apple ID email), and add the build.
5. On the iPhone, install **TestFlight** from the App Store, open the invite email, and tap **Install**.

TestFlight builds last 90 days. To refresh, just start a new iPhone build.

---

## Step 6: First run

1. Open **Wi-Fi_Analytics_v1.3** and allow **Location** ("While Using the App"). On Android also allow **Phone** (needed to read 4G/5G details; the app never makes calls).
2. Go to **Settings** → tap a server shortcut (or type the address only, and the port in **Port**) → enter the **IMEI last 4 digits** and the email sender (see below) → **Save settings**.
3. (Optional) Go to **Sites** → **Add site here** to tag your current location.
4. Go to **Test** → **Run speed test** or **Start UDP stream**.
5. Results are emailed when the session stops. **Data** → **Export Excel workbook** saves or shares everything logged so far.

**Tips for good results**
- Keep the app open on screen during tests. Both iPhone and Android pause network tests and GPS when the app is in the background. "Keep screen on during tests" (on by default) stops the phone from locking mid-test.
- Turn Wi-Fi **off** when you want to test cellular, and on when you want to test Wi-Fi. The app records which one was used.
- For the GPS track to be accurate, wait until the GPS accuracy shown on the Test screen is under ~10 m.

---

## Your iperf3 server checklist

**Default server:** `dal.speedtest.clouvider.net`, port `5200` (Clouvider Dallas: 10 ports 5200–5209, UDP, IPv6). As of Oct 20, 2026 the app uses **public iperf3 servers only**: the lab server (96.37.191.0 / Dell OptiPlex) shortcuts were removed, and phones that still had it saved move to Clouvider Dallas automatically. If a public server is busy or down, the app switches to the next one (see below). To use your own server later, type its address in Settings.

If you set up your own server later, the phone connects to it on the port in Settings:

- Start the server with: `iperf3 -s -p 5201`
- Open **both TCP and UDP** on that port in the server's firewall / cloud security group. UDP tests need UDP open; speed tests need TCP.
- iperf3 runs one test at a time per port. If another device is testing, the app waits and retries, then moves to the next port or server (see below).
- Servers with iperf3 authentication (`--rsa-private-key-path`) aren't supported.

---

## Your TWAMP reflector (for latency)

Latency is measured with **TWAMP-Light**: the phone sends small timestamped UDP packets to a reflector, which sends them straight back. There are no public reflectors, so run your own, ideally on the same server as iperf3:

1. Install Python 3.11 or newer, then get Nokia's free reflector: `pip install git+https://github.com/nokia/twampy` (or download the repo and run it from its `src` folder).
2. Start it: `twampy responder :862`
3. Open **UDP port 862** in the server's firewall / cloud security group.
4. In the app, **Settings → Latency (TWAMP)**: enter the server address and port 862, then **Save settings**.

Until a reflector is set, Android uses **ping** to the ping host in Settings (default 1.1.1.1). iPhones don't allow apps to ping, so on iPhone latency starts once the reflector is set. Routers often answer ping at low priority, so ping latency can read a little high; TWAMP is the reference.

## Test servers and automatic switching

**Settings → iperf3 server** has shortcuts for 11 US public servers (Clouvider, Leaseweb, IS.CC and others in Dallas, Chicago, Atlanta and Boston). Servers marked **no UDP** work for speed tests and Walk only. Each port runs one test at a time, so multi-port servers (Clouvider Dallas and Atlanta: 10 ports with UDP) are best when several phones test at once.

With **Switch servers when a test can't start** on (default), a test that fails before any data (busy, refused, timed out, not found) is retried on the busy server's next port (or the next ports of a server you typed in), or the next public server (nearest to Denver first; UDP tests only use UDP servers), up to 8 tries. The server that works is kept for the rest of the session. Those failures go to the **Server failures** sheet, not to the results.

## Traffic profiles (Test tab)

- **Drive test:** latency (TWAMP, or ping on Android without a reflector) plus one continuous UDP stream (direction in **Settings → Drive profile**; bitrate and packet size from **UDP stream**). Runs until you tap Stop. After a network change or server drop it restarts within 3–15 seconds.
- **Walk test:** latency runs the whole time. Each time the phone **joins Wi-Fi**, the app waits a few seconds (**Settings → Walk profile**), then runs a TCP speed test (download + upload). Optionally it also tests when the phone **moves to a new AP** (Android). A minimum gap stops back-to-back tests. Runs until you tap Stop.

- **Lab test:** latency plus one UDP downstream and one UDP upstream at the same time, until Stop (upstream on the next port, e.g. 5202, so run the server setup script first). The screen shows Down and Up Mbps. Files are named `Lab_…`; every other profile is `Field_…`.

Walk tests only run while the phone is on Wi-Fi; a test that would start on cellular is skipped and listed on the Server failures sheet.

Every row records the `profile`, and `tests.csv` records the `trigger` (for example `Joined Wi-Fi SpectrumWiFi a4:2b:…`).

## Geofence and dual-SIM (DSDS) logs

**Geofence:** the Spectrum HMNO CBRS geofence (GeoFence_20260708.json, 541 areas) is built in: entering and leaving it is logged with the CBSD area (Settings → Logging to turn it off). Also, every saved site with coordinates is a geofence. Set the radius when adding the site (default 100 m; sites can also be added at typed coordinates) or long-press a site to change it. With the app open, **Entered** and **Exited** are logged (10 m margin against GPS jitter; fixes worse than 50 m ignored) on the **Geofence** sheet with time, site, distance, time inside, GPS and radio. The last event shows on the Test screen.

**Dual SIM (Android):** the app reads every second which SIM carries mobile data (slot, carrier, PLMN) and the cellular IP addresses. **SIM switch**, **IP change**, **Data interrupted** and **Data lost** go to the **DSDS transitions** sheet with the gap without a cellular IP, time on the previous SIM, both SIMs, addresses and the IP owner (Spectrum Mobile on Verizon, Spectrum HMNO, Verizon Wireless …). Each switch is **Hand In** (onto HMNO) or **Hand Out**, successful or failed, with its switch time. The session email adds a **Transition performance** sheet in the same layout as the Transition Performance report: Switch Count, Successful switches, Mean, Median, Min, Max, Std Dev per direction. Needs the **Phone** permission; iPhones don't expose this.

## Emailing results automatically

When a session stops (Stop on a drive/walk/repeat run, or the end of a single test), the app emails **that session's rows** to the address in **Settings → Email results** (default `rockfordtest7@gmail.com`).

1. Use a Gmail account just for sending. Turn on **2-Step Verification**, then create an **App password** (Google Account → Security → App passwords).
2. In the app, **Settings → Email results**: enter the sender Gmail address and the 16-character app password, check the IMEI last 4 digits (dial `*#06#`; Android 10+ and iPhone don't let apps read it), then **Save settings**.

The attachment is one Excel workbook named `Field|Lab_Make_Model_build_profile_location_IMEI_date-time.xlsx`, for example `Field_Samsung_S25_ylz1_walk_DAL_3245_20261019-1123.xlsx`: Lab only for the Lab profile; model as a short name (S25, S25E, 17ProMax); build = last 4 of the software build (iPhone: iOS version); profile walk, drive, lab or stationary; location from **Settings → Location code**, else the market nearest the site or GPS (DEN, DAL, HEN, ATL, CLT, MAC …); IMEI last 4 (`xxxx` if not set). **Settings → File names** shows the current name. The workbook has a sheet each for **Tests**, **Speed (per second)**, **Latency (per second)**, **GPS track**, **Server failures**, **Geofence**, **DSDS transitions**, **Transition performance** (Android) and **Sites**. Data-tab exports hold every log and are named `…_all_…`. If a session is too big for one email (long weekend runs), its data is sent as gzip-compressed CSVs split across several emails instead. With no signal, the email waits in an outbox and is retried every 10 minutes and when the app starts; the Data tab shows the status and a **Send now** button.

The app password is stored on the phone in the app's private storage. Use a sending account that holds nothing else.

## Overnight and weekend runs

1. **Settings → Long runs:** turn on **Repeat until stopped** and set the pause between rounds (for example 900 s = a speed test every 15 minutes). For one continuous UDP stream, set the UDP duration to **0** instead; with Repeat on, it restarts on its own after a network change or server drop (retrying after 10 s, 20 s, 40 s … up to 2 minutes).
2. **Keep the app open with the screen on**, phone **plugged into a charger**, ideally somewhere cool. The screen can be dimmed, but don't lock it or switch apps.
3. **Use your own iperf3 server.** Public servers often end long sessions or are busy at night.
4. **Storage:** about 100–150 MB per day of CSV files with GPS logging, UDP samples and latency every second. Export and clear the logs (Data tab) after each weekend run.

Data is written to the phone every 10 seconds, so a crash or dead battery loses only the last few seconds.

## What the app records on each platform

| | Android | iPhone |
|---|---|---|
| Throughput, UDP jitter & packet loss | ✅ | ✅ |
| GPS (lat/lon, accuracy, speed, heading, altitude) | ✅ | ✅ |
| Technology (LTE / 5G NSA / 5G SA / Wi-Fi) | ✅ | ✅ |
| Carrier name, MCC/MNC | ✅ | — |
| LTE RSRP, RSRQ, SINR, RSSI, CQI, PCI, TAC, eNB/Cell ID, EARFCN, band | ✅ | — |
| 5G NR SS-RSRP, SS-RSRQ, SS-SINR, PCI, NCI, ARFCN, band | ✅ | — |
| Wi-Fi network name, signal (dBm), channel, band, standard, link speed | ✅ | — |

Apple doesn't allow apps to read signal strength or cell details, so on iPhone you get the technology type only. Some Android phones also hide certain values (they'll be blank in the CSV).

---

## Troubleshooting

| Problem | Fix |
|---|---|
| "Could not reach server" | Check the address/port in Settings, and that the server is running and its firewall allows the port. |
| "No UDP reply from the server" | UDP is blocked. Open UDP on the server port in the firewall/security group. Some guest Wi-Fi networks block UDP. |
| Speed test shows much lower speeds than expected | Increase **Parallel streams** to 8 in Settings. |
| UDP test shows high loss | The target bitrate may be higher than the link can carry. Lower the **Target bitrate**. |
| Cell fields blank on Android | Allow **Phone** and **Location** permissions for the app in Android Settings → Apps → Wi-Fi_Analytics_v1.3 → Permissions, and make sure Location is on. |
| Codemagic Android build fails | Open the failed step's log and send me the error text. |
| Codemagic iPhone build fails at code signing | Check the Bundle ID is identical in all three `codemagic.yaml` lines, in Apple's Identifiers list, and in App Store Connect; and that the integration name is exactly `WiFi Analytics key`. |

---

## Alternative: building on your own computer

If you or a developer prefer to build locally, install Flutter 3.38 or newer (flutter.dev), then from this folder run:

```
flutter create --org com.wifianalytics --project-name wifi_analytics --platforms=android,ios .
dart run tool/setup.dart
flutter pub get
flutter run            # with a phone connected
```

For iPhone you'll need a Mac with Xcode. Set `BUNDLE_ID=com.yourname.wifianalytics` before `dart run tool/setup.dart` to apply your Bundle ID.

## Debug app: Analytics_debug_ver1.0 (records logcat)

A separate app (`com.example.analyticsdebug`) that installs next to Wi-Fi_Analytics_v1.3 and does
everything it does, plus records logcat during every test session.

1. In Codemagic, start the **Android Debug APK (logcat)** workflow and install
   `Analytics_debug_ver1.0.apk`.
2. Android only lets an app read the radio and system logs if you grant it from a computer,
   once per install (USB debugging on, phone connected):

   ```
   adb shell pm grant com.example.analyticsdebug android.permission.READ_LOGS
   ```

   Then force-stop and reopen the app. Data tab > Logcat > Check access should say
   "Full access granted". Without it, only the app's own lines are recorded.
3. Each session records `logcat -b all -v time -f logcat_output.txt -r <size> -n <files>`, the same
   capture as On-Device_AdbLogging.bat, into its own folder:
   `/sdcard/Android/data/com.example.analyticsdebug/files/logcat/<session file name>/`.
   Defaults: 64 MB files (about 6 MB gzipped, fits in email), 50 files kept; set 1024 MB to match
   the .bat. It starts from "now" (`-T 1`) instead of clearing the buffer, so other logs are not wiped.
   When the session stops, each file is gzipped (`<file name>_logcat_output.txt.gz`, `.01`, ... higher
   number = older), emailed with the results, and kept on the phone for Data > Logcat > Share or:

   ```
   adb pull /sdcard/Android/data/com.example.analyticsdebug/files/logcat
   ```

   `session_info.txt` in each folder gives the start time in UTC and the phone's time zone
   (`-v time` stamps are phone local time, without the year).
