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

The emailed workbook (and Data → Export Excel workbook) has one sheet per file: Tests, Speed (per second), Latency (per second), GPS track, Server failures, Sites. File names: `Field|Lab_Make_Model_build_profile_location_IMEI_date-time.xlsx` (see BUILD_GUIDE.md, Emailing results).

Rows in `samples.csv` and `twamp.csv` link to `tests.csv` by `test_id`.

## Document versions

| Version | Date | Commit(s) | Changes |
|---|---|---|---|
| 1.0 | Oct 17, 2026 | dde7a99 | First data dictionary. |
| 1.1 | Oct 18, 2026 | a1f1e21, 4dd5252 | Latency columns; profile and trigger columns. |
| 1.2 | Oct 19, 2026 | f33eaac | server_failures.csv. |
| 2.0 | Oct 19, 2026 | this update | Workbook sheets and file names; Lab profile; walk tests skipped off Wi-Fi; version tables. |

## App and script versions

| App / script | Version | Date | Commit(s) | Changes |
|---|---|---|---|---|
| Wi-Fi Analytics (Android) | 1.0 | Oct 17, 2026 | dde7a99 | First version in the repository: iperf3 TCP/UDP, ping latency, GPS and radio logging, sites, CSV export. |
| Wi-Fi Analytics (Android) | 1.1 | Oct 18, 2026 | a1f1e21 to 72ca927 (Codemagic build 8) | TWAMP latency during every test; Wi-Fi generation and BSSID; long runs; Drive and Walk profiles; email when a session stops; Excel workbook; screen-freeze fixes. |
| Wi-Fi Analytics (Android) | 1.2 | Oct 18-19, 2026 | 90fe7a5 to f33eaac | Lab server as default with shortcuts; address:port parsing and repair of saved addresses; 11 public servers; automatic port/server switching; Server failures sheet. |
| Wi-Fi_Analytics_v1.3 (Android) | 1.3.0 | Oct 19, 2026 | 9313d12 to 1c9fce9 (current) | File names Field\|Lab_Make_Model_build_profile_LOC_IMEI_date-time; Lab profile (UDP up and down together); app renamed; Field unless the Lab profile runs; exports named _all_; walk tests only on Wi-Fi; tests stopped before data not recorded. |
| Analytics_debug_ver1.0 (Android) | 1.0.0 | Oct 19, 2026 | aaafbb5 to 1c9fce9 (current) | Separate debug app: everything in v1.3 plus logcat per session (logcat -b all -v time, rotating files, gzipped and emailed; adb-pullable). |
| Wi-Fi Analytics (iPhone) | 1.3 (code) | Oct 19, 2026 | 1c9fce9 | Same code as Android v1.3. Not built yet: needs Bundle ID and App Store Connect key. |
| setup-windows-test-server.ps1 (lab server) | 1.0 | Oct 18, 2026 | 7be8bc7 | iperf3 3.21 on ports 5201-5205 and TWAMP reflector on UDP 862, start at boot, firewall rules, self-test. |
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

site_id, site_name, notes, latitude, longitude, gps_accuracy_m, created_utc

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
