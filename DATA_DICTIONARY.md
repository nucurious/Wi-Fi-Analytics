# Wi-Fi_Analytics_v1.3: Data Dictionary

All files are UTF-8 CSV with a header row. Blank cells mean the value wasn't available (for example, signal metrics on iPhone, or a value the phone doesn't report).

| File | One row per |
|---|---|
| `tests.csv` | Completed or failed test |
| `samples.csv` | Second of a running test |
| `twamp.csv` | Second of latency measurement (TWAMP or ping) during a test |
| `gps_track.csv` | Second while the app is open (if enabled in Settings) |
| `sites.csv` | Saved site |
| `server_failures.csv` | Test that could not start (server switched), or walk test skipped off Wi-Fi |
| `geofence.csv` | Geofence crossing (Entered / Exited / Inside at start) |
| `dsds_transitions.csv` | Dual-SIM data transition (Android) |
| `ui_stalls.csv` | UI freeze longer than 0.7 s |
| `traffic_gaps.csv` | User-plane interruption seen in the traffic (UDP download packet gap > 0.3 s, or 2+ latency probes lost in a row) |

The emailed workbook (and Data → Export Excel workbook) has one sheet per file: Tests, Speed (per second), Latency (per second), GPS track, Server failures, Geofence, DSDS transitions, Traffic gaps, UI stalls, Sites; the session email also has a Transition performance sheet (Android). File names: `Field|Lab_Make_Model_build_profile_location_IMEI_date-time.xlsx` (see BUILD_GUIDE.md, Emailing results).

Rows in `samples.csv` and `twamp.csv` link to `tests.csv` by `test_id`.


## Contents

- [Document versions](#document-versions)
- [App and script versions](#app-and-script-versions)
- [tests.csv](#testscsv)
- [samples.csv](#samplescsv)
- [twamp.csv](#twampcsv)
- [gps_track.csv](#gps_trackcsv)
- [sites.csv](#sitescsv)
- [GPS columns](#gps-columns)
- [Radio columns](#radio-columns)
- [server_failures.csv (sheet "Server failures")](#server_failurescsv-sheet-server-failures)
- [geofence.csv (sheet "Geofence")](#geofencecsv-sheet-geofence)
- [dsds_transitions.csv (sheet "DSDS transitions", Android)](#dsds_transitionscsv-sheet-dsds-transitions-android)
- [Transition performance (sheet in the session email, Android)](#transition-performance-sheet-in-the-session-email-android)
- [ui_stalls.csv (sheet "UI stalls")](#ui_stallscsv-sheet-ui-stalls)

## Document versions

| Version | Date | Commit(s) | Changes |
|---|---|---|---|
| 1.0 | Oct 17, 2026 | dde7a99 | First data dictionary. |
| 1.1 | Oct 18, 2026 | a1f1e21, 4dd5252 | Latency columns; profile and trigger columns. |
| 1.2 | Oct 19, 2026 | f33eaac | server_failures.csv. |
| 2.0 | Oct 19, 2026 | 78ad25f | Workbook sheets and file names; Lab profile; walk tests skipped off Wi-Fi; version tables. |
| 2.1 | Oct 19, 2026 | 994535f | geofence.csv, dsds_transitions.csv, DSDS summary, data SIM radio columns, site geofence radius. |
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

## tests.csv

If you update the app and the columns change, the older log is kept as `tests_old_<date-time>.csv` on the phone and a new `tests.csv` starts.

| Column | Meaning |
|---|---|
| test_id | Unique ID: start time + test type |
| test_type | TCP Download, TCP Upload, UDP Download, UDP Upload, Latency TWAMP, Latency ICMP |
| start_utc / start_local | Test start time |
| duration_s | Actual test length in seconds |
| throughput_mbps | Average throughput. Uploads use the server's received count; downloads use the phone's |
| min_mbps / max_mbps | Lowest and highest one-second throughput during the test |
| median_mbps | Middle one-second throughput (less affected by TCP ramp-up than the average) |
| p10_mbps / p90_mbps | 10th / 90th percentile of one-second throughput: speed you got at least 90% / 10% of the time |
| jitter_ms | UDP only. RFC 1889 inter-arrival jitter measured by the receiver |
| lost_packets / total_packets / loss_pct | UDP only. Measured by the receiver |
| stopped_by_user | 1 if Stop was pressed |
| error | Error message if the test failed after it started. Tests that never started are in server_failures.csv instead; tests stopped before any data are not recorded |
| server / port | iperf3 server used |
| parallel_streams | Number of parallel streams |
| udp_target_mbps / udp_packet_bytes | UDP settings |
| site_id / site_name | Site selected when the test ran |
| device_platform | android or ios |
| profile | Manual, Drive, Walk or Lab: how the session was started |
| trigger | Why this test started: Manual, Repeat, Drive profile, Lab profile, `Joined Wi-Fi <SSID> <BSSID>`, `AP change <old> -> <new>`, or Walk start on Wi-Fi |
| latency_target | Latency method and target measured during this test, e.g. `TWAMP 203.0.113.5:862` or `ICMP 1.1.1.1`. Blank if latency was off or unavailable |
| rtt_avg_ms / rtt_min_ms / rtt_max_ms / rtt_median_ms | Round-trip time during the test (latency under load for throughput tests). TWAMP removes the reflector's own processing time |
| rtt_jitter_ms | Mean difference between consecutive round-trip times (IPDV) |
| rtt_loss_pct / rtt_packets | Latency probe packets lost / sent during the test |
| GPS columns | Position at test start (see below) |
| Radio columns | Radio state at test start (see below) |

## samples.csv

| Column | Meaning |
|---|---|
| test_id / test_type | Links to tests.csv |
| time_utc / time_local | Sample time |
| elapsed_s | Seconds since the test started |
| interval_mbps | Throughput during the last second |
| site_id | Selected site |
| profile | Manual, Drive or Walk |
| GPS + Radio columns | At the time of the sample |

## twamp.csv

Written while a test runs, if **Measure latency during every test** is on, and during a stand-alone **Latency test**. The method is TWAMP-Light (RFC 5357 Appendix I / STAMP RFC 8762) when a reflector is set in Settings; otherwise ping on Android. Each row covers the probe packets **sent** in that second, and is written once they have all returned or timed out (2 s).

| Column | Meaning |
|---|---|
| time_utc / time_local | The second the packets were sent |
| test_id / test_type | Test running at that time (links to tests.csv) |
| method / target | TWAMP or ICMP, and the reflector or ping host |
| sent / received / lost / loss_pct | Probe packets in that second |
| rtt_min_ms / rtt_avg_ms / rtt_max_ms / rtt_median_ms | Round-trip time |
| jitter_ms | Mean difference between consecutive round-trip times |
| outbound_avg_ms / inbound_avg_ms | TWAMP only: phone→reflector and reflector→phone delay. Only meaningful if both clocks are synchronized (NTP/PTP); otherwise they include the clock offset |
| site_id | Selected site |
| profile | Manual, Drive or Walk |
| GPS + Radio columns | When the first result of that second arrived |

## gps_track.csv

| Column | Meaning |
|---|---|
| time_utc / time_local | Sample time |
| site_id | Selected site |
| test_running | 1 if a test was running |
| profile | Drive or Walk while that profile runs; blank when idle |
| GPS + Radio columns | At the time of the sample |

## sites.csv

site_id, site_name, notes, latitude, longitude, gps_accuracy_m, created_utc, geofence_radius_m

## GPS columns

| Column | Meaning |
|---|---|
| latitude / longitude | WGS84 decimal degrees |
| altitude_m | Meters |
| gps_accuracy_m | Horizontal accuracy radius, meters |
| speed_kmh | Ground speed |
| heading_deg | Direction of travel, 0–359 |
| gps_time_utc | Time of the GPS fix |

## Radio columns

**Both platforms**

| Column | Meaning |
|---|---|
| connection | WIFI, CELLULAR, ETHERNET, VPN, NONE |
| rat | Summary technology: 5G SA, 5G NSA, 5G NSA+ (NR Advanced), LTE, LTE-CA, LTE-A Pro, 3G, 2G |
| data_network_type | Raw OS network type (e.g. LTE, NR, NRNSA) |

**Android only**

| Column | Meaning |
|---|---|
| override_network_type | Android display override (NR_NSA, NR_ADVANCED, LTE_CA…) |
| operator, mcc, mnc | Serving carrier |
| lte_rsrp / lte_rsrq / lte_sinr / lte_rssi | LTE serving-cell signal (dBm / dB) |
| lte_cqi, lte_timing_advance | Channel quality, timing advance |
| lte_pci, lte_tac, lte_eci, lte_enb, lte_cell_id | LTE identity (ECI = eNB × 256 + cell) |
| lte_earfcn, lte_band, lte_bandwidth_khz | LTE channel / band (band needs Android 11+) |
| nr_ss_rsrp / nr_ss_rsrq / nr_ss_sinr | 5G NR SSB signal |
| nr_csi_rsrp / nr_csi_sinr | 5G NR CSI signal |
| nr_pci, nr_tac, nr_nci, nr_arfcn, nr_band | 5G NR identity / channel (SA, or NSA where the phone reports it) |
| umts_*, gsm_* | 3G / 2G serving cell, if on those networks |
| wifi_ssid, wifi_bssid | Wi-Fi network name and access point MAC |
| wifi_rssi | Wi-Fi signal, dBm |
| wifi_freq_mhz, wifi_band, wifi_channel | Wi-Fi frequency, band (2.4/5/6 GHz), channel |
| wifi_standard | Wi-Fi 4/5/6/7 (Android 11+) |
| wifi_link_mbps, wifi_tx_mbps, wifi_rx_mbps | Negotiated link rates |
| data_sim_slot, data_carrier, data_plmn | SIM carrying mobile data (1-based slot), its carrier name and MCC+MNC (Android) |
| cell_iface, cell_ipv4, cell_ipv6 | Cellular data interface (e.g. rmnet_data2) and its addresses, comma-separated, no link-local (Android) |

In 5G NSA, Android often reports the NR signal (nr_ss_*) without NR cell identity, because the phone is anchored on the LTE cell.

## server_failures.csv (sheet "Server failures")

Tests that could not start (server busy, down, unreachable, or timed out before any data) when
Settings > "Switch servers when a test can't start" is on. These are **not** in the Tests sheet;
the app moved to the next port of the same server (if busy) or the next public server
(Dallas, Chicago, Atlanta, Boston; UDP tests only use servers that accept UDP).

| Column | Meaning |
|---|---|
| time_utc, time_local | When the attempt failed |
| test_type | TCP/UDP Download/Upload |
| profile | Manual, Drive or Walk |
| server, port | Server that failed |
| error | Why it failed |
| switched_to, switched_port | Where the app tried next (blank = nothing left; test skipped this round) |
| radio columns | Same as the Tests sheet |

## geofence.csv (sheet "Geofence")

Two kinds of fence, checked on every GPS fix while the app is open (fixes less accurate than 50 m are ignored):

- **HMNO CBRS**: the Spectrum HMNO CBRS geofence built into the app (`assets/geofence/GeoFence_20260708.json`, 541 CBSD radial areas, carrier 2449, band 48). The union of the areas is one coverage area; each event names the CBSD area involved. On/off in Settings → Logging.
- **Site**: every saved site with coordinates (sites.csv `geofence_radius_m`, default 100 m).

| Column | Meaning |
|---|---|
| time_utc, time_local | When the crossing was detected |
| event | Entered (within the radius), Exited (10 m beyond the radius), Inside at start (app started inside the fence) |
| source | HMNO CBRS or Site |
| fence_id, fence_name, radius_m | CBSD area (e.g. HENRY_151GA_1001) or site; for HMNO Entered: the nearest area containing the phone; Exited: the nearest area |
| distance_m | Distance from the area / site center |
| distance_to_edge_m | Distance to its edge (negative = inside) |
| hmno_areas_inside | HMNO: number of CBSD areas containing the phone |
| time_inside_s | On Exited: time since Entered |
| latitude, longitude, gps_accuracy_m, speed_kmh, heading_deg | GPS fix |
| profile, test_running, test_type | What was running |
| radio columns | Same as the Tests sheet (Wi-Fi, cell, data SIM) |

## dsds_transitions.csv (sheet "DSDS transitions", Android)

The data SIM and cellular IPs are read every second.

| Column | Meaning |
|---|---|
| time_utc, time_local | When the new data path was up (or the loss confirmed) |
| event | SIM switch (data moved to the other SIM and its network has an IP), SIM switch failed (went back to the old SIM, or no IP within 60 s), SIM switch (late) (IP after the timeout), IP change (same SIM, new address), Data interrupted (IP gone and back unchanged), Data lost (no cellular IP for 30 s) |
| direction | Hand In (onto the Spectrum HMNO subscription: PLMN 314020 or HMNO IP), Hand Out (off it), Other; blank for non-switch events |
| success | yes / no for switches |
| started_utc | When the previous data path ended, or the data SIM changed if earlier |
| switch_time_s | From started_utc to the IP on the new SIM (blank for failed). Read 4 times a second (about 0.25 s resolution) |
| time_on_previous_s | Time on the previous SIM / address |
| from_sim, from_carrier, from_plmn, from_iface, from_ipv4, from_ipv6 | Before |
| to_sim, to_carrier, to_plmn, to_iface, to_ipv4, to_ipv6 | After |
| from_ip_owner, to_ip_owner | From the registry-checked ranges (analyzer v5.14): Spectrum Mobile on Verizon (2600:100c, 100.124.x), Spectrum HMNO (2603:90f4, 10.14.x), Verizon Wireless (2600:1000::/28, 2600:1010::/29, 97.128/9, 174.192/10, 70.192/11), T-Mobile, AT&T Mobility, Carrier NAT, Private, Other |
| sims | Active SIMs, e.g. `SIM1 Spectrum 311480; SIM2 Verizon 311480` |
| default_connection | WIFI or CELLULAR (what the phone used by default) |
| in_hmno_geofence, hmno_area, hmno_edge_m | Inside the HMNO CBRS geofence (yes/no), containing or nearest CBSD area, distance to its edge (negative = inside) |
| profile, test_running, test_type, site_id | Context |
| GPS + radio columns | At the event |

## Transition performance (sheet in the session email, Android)

Same layout as the Transition Performance report, for this session:

| Transition Type | Hand In | Hand Out |
|---|---|---|
| Switch Count | switch attempts onto HMNO | attempts off HMNO |
| Successful switches | attempts with an IP on the new SIM within 60 s | … |
| Mean (s), Median (s), Min (s), Max (s), Std Dev (s) | switch_time_s of the successful switches (sample std dev) | … |

Below the switch-time rows, **User-plane interruption (from traffic)**: for each successful switch, the longest traffic gap overlapping [switch start − 3 s, switch + 10 s] (UDP download packet gaps preferred, at ms precision; else lost TWAMP/ping probes at 0.1 / 0.2 s), with Switches with a traffic gap, UP Mean, Median, Min, Max, Std Dev. Run a continuous UDP stream (duration 0, Lab or Drive profile) during switches for the best numbers. An **Other** column appears if neither SIM was HMNO. Below: counts of IP changes, interruptions and losses, and the session length.

## ui_stalls.csv (sheet "UI stalls")

Every UI freeze longer than 0.7 s, to find what blocks the screen during runs.

| Column | Meaning |
|---|---|
| time_utc, time_local | When it was detected |
| kind | App thread blocked (the app's Dart thread ran late), Slow frame (a frame took too long to build or draw), Android main thread blocked (touches and screen updates waited; native watchdog every 0.2 s), Slow native call (a radio or SIM read took more than 3 s) |
| duration_ms | How long |
| detail | Extra detail (frame build/raster time, which call) |
| test_running, profile, test_type | What was running |
| iperf_streams, latency, logcat_running | Load at the time |
| connection, rat | Network at the time |

## traffic_gaps.csv (sheet "Traffic gaps")

User-plane interruptions measured from the traffic itself.

| Column | Meaning |
|---|---|
| start_utc, end_utc, start_local, duration_s | The gap (ms precision for UDP download packets) |
| source | UDP download packets (gap > 0.3 s between received packets; in continuous runs also from the last packet before a restart to the first after it), TWAMP lost / Ping lost (2+ probes lost in a row: from the first lost send to the next answered send) |
| test_type, profile | What was running |
| data_sim_slot, data_plmn, cell_ipv6, cell_ipv4, connection, rat, in_hmno_geofence | Network when the gap was logged (after it ended) |
| latitude, longitude, speed_kmh | Position |
