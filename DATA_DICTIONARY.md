# WiFi Analytics: CSV Data Dictionary

All files are UTF-8 CSV with a header row. Blank cells mean the value wasn't available (for example, signal metrics on iPhone, or a value the phone doesn't report).

| File | One row per |
|---|---|
| `tests.csv` | Completed or failed test |
| `samples.csv` | Second of a running test |
| `gps_track.csv` | Second while the app is open (if enabled in Settings) |
| `sites.csv` | Saved site |

Rows in `samples.csv` link to `tests.csv` by `test_id`.

## tests.csv

If you update the app and the columns change, the older log is kept as `tests_old_<date-time>.csv` on the phone and a new `tests.csv` starts.

| Column | Meaning |
|---|---|
| test_id | Unique ID: start time + test type |
| test_type | TCP Download, TCP Upload, UDP Download, UDP Upload |
| start_utc / start_local | Test start time |
| duration_s | Actual test length in seconds |
| throughput_mbps | Average throughput. Uploads use the server's received count; downloads use the phone's |
| min_mbps / max_mbps | Lowest and highest one-second throughput during the test |
| median_mbps | Middle one-second throughput (less affected by TCP ramp-up than the average) |
| p10_mbps / p90_mbps | 10th / 90th percentile of one-second throughput: speed you got at least 90% / 10% of the time |
| jitter_ms | UDP only. RFC 1889 inter-arrival jitter measured by the receiver |
| lost_packets / total_packets / loss_pct | UDP only. Measured by the receiver |
| stopped_by_user | 1 if Stop was pressed |
| error | Error message if the test failed |
| server / port | iperf3 server used |
| parallel_streams | Number of parallel streams |
| udp_target_mbps / udp_packet_bytes | UDP settings |
| site_id / site_name | Site selected when the test ran |
| device_platform | android or ios |
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
| GPS + Radio columns | At the time of the sample |

## gps_track.csv

| Column | Meaning |
|---|---|
| time_utc / time_local | Sample time |
| site_id | Selected site |
| test_running | 1 if a test was running |
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
