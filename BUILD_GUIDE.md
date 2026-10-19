# WiFi Analytics: Build & Install Guide

This guide gets the app onto your phones **without installing any developer tools on your computer**. A free cloud service, **Codemagic**, builds the app for you:

- **Android:** Codemagic gives you an `.apk` file you install directly on the phone.
- **iPhone:** Codemagic builds the app and sends it to **TestFlight**, then you install it with Apple's TestFlight app.

Plan on about an hour the first time. After that, a new build is one click.

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
2. Choose the workflow **Android APK** and click **Start new build**.
3. Wait about 10 minutes for a green ✅.
4. Under **Artifacts**, download `app-release.apk`.

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

1. Open **WiFi Analytics** and allow **Location** ("While Using the App"). On Android also allow **Phone** (needed to read 4G/5G details; the app never makes calls).
2. Go to **Settings** → enter your **iperf3 server address** and **port** (normally 5201) → **Save settings**.
3. (Optional) Go to **Sites** → **Add site here** to tag your current location.
4. Go to **Test** → **Run speed test** or **Start UDP stream**.
5. Go to **Data** → **Export CSV files** to email or save your results.

**Tips for good results**
- Keep the app open on screen during tests. Both iPhone and Android pause network tests and GPS when the app is in the background. "Keep screen on during tests" (on by default) stops the phone from locking mid-test.
- Turn Wi-Fi **off** when you want to test cellular, and on when you want to test Wi-Fi. The app records which one was used.
- For the GPS track to be accurate, wait until the GPS accuracy shown on the Test screen is under ~10 m.

---

## Your iperf3 server checklist

**Lab server:** `96.37.191.0`, port `5201` (Dell OptiPlex 7070 on the lab's 1 Gbps Spectrum Business line). This is the app's default server address on a new install; existing installs keep whatever is in Settings. To add more iperf3 ports (so several testers can run at once) and the TWAMP reflector to that PC, run `server/setup-windows-test-server.ps1` on it as administrator.

Quick reachability check from a Windows PC **outside** the lab network:
`Test-NetConnection 96.37.191.0 -Port 5201` → `TcpTestSucceeded : True`. Testing from inside the lab can fail even when the server is fine (many routers don't loop traffic back to their own public IP); the definitive test is the app on a phone using **cellular**.

Things that limit results from the lab server:
- The line's **upload** speed caps every phone **download** test (the server sends). Check it with a speed test from the lab.
- 1 Gbps line → tests top out around 940 Mbps. For faster Wi-Fi 7 tests, test against the server's LAN address from the lab Wi-Fi.

The phone connects to your server on the port in Settings (default 5201):

- Start the server with: `iperf3 -s -p 5201`
- Open **both TCP and UDP** on that port in the server's firewall / cloud security group. UDP tests need UDP open; speed tests need TCP.
- iperf3 runs one test at a time. If another device is testing, the app waits and retries, then shows "server is busy".
- Servers with iperf3 authentication (`--rsa-private-key-path`) aren't supported.

---

## Your TWAMP reflector (for latency)

Latency is measured with **TWAMP-Light**: the phone sends small timestamped UDP packets to a reflector, which sends them straight back. There are no public reflectors, so run your own, ideally on the same server as iperf3:

1. Install Python 3.11 or newer, then get Nokia's free reflector: `pip install git+https://github.com/nokia/twampy` (or download the repo and run it from its `src` folder).
2. Start it: `twampy responder :862`
3. Open **UDP port 862** in the server's firewall / cloud security group.
4. In the app, **Settings → Latency (TWAMP)**: enter the server address and port 862, then **Save settings**.

Until a reflector is set, Android uses **ping** to the ping host in Settings (default 1.1.1.1). iPhones don't allow apps to ping, so on iPhone latency starts once the reflector is set. Routers often answer ping at low priority, so ping latency can read a little high; TWAMP is the reference.

## Traffic profiles (Test tab)

- **Drive test:** latency (TWAMP, or ping on Android without a reflector) plus one continuous UDP stream (direction in **Settings → Drive profile**; bitrate and packet size from **UDP stream**). Runs until you tap Stop. After a network change or server drop it restarts within 3–15 seconds.
- **Walk test:** latency runs the whole time. Each time the phone **joins Wi-Fi**, the app waits a few seconds (**Settings → Walk profile**), then runs a TCP speed test (download + upload). Optionally it also tests when the phone **moves to a new AP** (Android). A minimum gap stops back-to-back tests. Runs until you tap Stop.

Every row records the `profile`, and `tests.csv` records the `trigger` (for example `Joined Wi-Fi SpectrumWiFi a4:2b:…`).

## Emailing results automatically

When a session stops (Stop on a drive/walk/repeat run, or the end of a single test), the app emails **that session's rows** to the address in **Settings → Email results** (default `rockfordtest7@gmail.com`).

1. Use a Gmail account just for sending. Turn on **2-Step Verification**, then create an **App password** (Google Account → Security → App passwords).
2. In the app, **Settings → Email results**: enter the sender Gmail address and the 16-character app password, check the IMEI last 4 digits (dial `*#06#`; Android 10+ and iPhone don't let apps read it), then **Save settings**.

The attachment is one Excel workbook named `<Make>_<Model>_<IMEI last 4>_<Profile>_<date-time>.xlsx` (for example `samsung_SM-S938U_1234_Walk_20261018-121500.xlsx`) with a sheet each for **Tests**, **Speed (per second)**, **Latency (per second)** and **GPS track**. If a session is too big for one email (long weekend runs), its data is sent as gzip-compressed CSVs split across several emails instead. With no signal, the email waits in an outbox and is retried every 10 minutes and when the app starts; the Data tab shows the status and a **Send now** button.

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
| Cell fields blank on Android | Allow **Phone** and **Location** permissions for the app in Android Settings → Apps → WiFi Analytics → Permissions, and make sure Location is on. |
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
