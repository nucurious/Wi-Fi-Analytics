package com.wifianalytics.radio_info;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.net.ConnectivityManager;
import android.net.LinkAddress;
import android.net.LinkProperties;
import android.net.NetworkSpecifier;
import android.net.TelephonyNetworkSpecifier;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkInfo;
import android.net.NetworkRequest;
import android.net.TrafficStats;
import android.net.wifi.ScanResult;
import android.net.wifi.SupplicantState;
import android.net.wifi.WifiInfo;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.telephony.CellIdentityGsm;
import android.telephony.CellIdentityLte;
import android.telephony.CellIdentityNr;
import android.telephony.CellIdentityWcdma;
import android.telephony.CellInfo;
import android.telephony.CellInfoGsm;
import android.telephony.CellInfoLte;
import android.telephony.CellInfoNr;
import android.telephony.CellInfoWcdma;
import android.telephony.CellSignalStrength;
import android.telephony.CellSignalStrengthLte;
import android.telephony.CellSignalStrengthNr;
import android.telephony.SignalStrength;
import android.telephony.SubscriptionInfo;
import android.telephony.SubscriptionManager;
import android.telephony.TelephonyCallback;
import android.telephony.TelephonyDisplayInfo;
import android.telephony.TelephonyManager;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

/**
 * Reports the serving cell's radio technology and signal metrics
 * (RSRP / RSRQ / SINR / PCI / band / cell ID) for LTE and 5G NR.
 */
public class RadioInfoPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler,
        ActivityAware, PluginRegistry.RequestPermissionsResultListener {

    private static final String CHANNEL = "wifi_analytics/radio_info";
    private static final int PERMISSION_REQUEST = 47321;
    private static final int UNAVAILABLE = Integer.MAX_VALUE;

    private MethodChannel channel;
    private Context context;
    private Activity activity;
    private ActivityPluginBinding activityBinding;
    private MethodChannel.Result pendingPermissionResult;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    // Telephony / Wi-Fi / connectivity calls are binder calls that can block for
    // seconds while the modem is busy (i.e. during a test). They run on these
    // background threads, never on the main (touch/UI) thread; only the
    // result is posted back to the main thread.
    private final ScheduledExecutorService radioWorker = Executors.newSingleThreadScheduledExecutor();
    private final ScheduledExecutorService dataWorker = Executors.newSingleThreadScheduledExecutor();
    private final ScheduledExecutorService wifiWorker = Executors.newSingleThreadScheduledExecutor();

    // Wi-Fi scans and connection steps, queued as they happen (with their own
    // time stamps) and collected by the app once a second (getWifiEvents).
    private final ConcurrentLinkedQueue<Map<String, Object>> wifiEvents = new ConcurrentLinkedQueue<>();
    private BroadcastReceiver wifiReceiver;
    private ConnectivityManager.NetworkCallback wifiNetCallback;
    private int scansDelivered = 0;

    // Main-thread watchdog: every 200 ms a probe is posted to the main thread;
    // the delay before it runs is how long the main thread was blocked.
    private final AtomicLong maxMainLagMs = new AtomicLong(0);
    private final AtomicBoolean probePending = new AtomicBoolean(false);
    private final AtomicLong probePostedAt = new AtomicLong(0);
    private final AtomicBoolean stackTaken = new AtomicBoolean(false);
    // Where the main thread was stuck during the last freeze (top frames), read once by the app.
    private final java.util.concurrent.atomic.AtomicReference<String> mainStack =
            new java.util.concurrent.atomic.AtomicReference<>(null);
    private ScheduledExecutorService watchdog;

    // Latest TelephonyDisplayInfo override type (tells us about 5G NSA). -1 = unknown.
    private volatile int overrideNetworkType = -1;
    private Object displayInfoCallback;

    // ---------------------------------------------------------------- lifecycle

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);
        watchdog = Executors.newSingleThreadScheduledExecutor();
        watchdog.scheduleAtFixedRate(() -> {
            if (!probePending.compareAndSet(false, true)) {
                // Still blocked: after 0.7 s, record where the main thread is stuck (once per freeze).
                long blocked = android.os.SystemClock.uptimeMillis() - probePostedAt.get();
                if (blocked >= 700 && stackTaken.compareAndSet(false, true)) {
                    try {
                        StackTraceElement[] st = Looper.getMainLooper().getThread().getStackTrace();
                        StringBuilder sb = new StringBuilder();
                        for (int i = 0; i < st.length && i < 25; i++) {
                            if (i > 0) sb.append(" <- ");
                            sb.append(st[i].getClassName()).append('.').append(st[i].getMethodName())
                                    .append(':').append(st[i].getLineNumber());
                        }
                        mainStack.set(sb.toString());
                    } catch (Exception ignored) {
                    }
                }
                return;
            }
            final long posted = android.os.SystemClock.uptimeMillis();
            probePostedAt.set(posted);
            mainHandler.post(() -> {
                long lag = android.os.SystemClock.uptimeMillis() - posted;
                maxMainLagMs.accumulateAndGet(lag, Math::max);
                probePending.set(false);
                stackTaken.set(false);
            });
        }, 200, 200, TimeUnit.MILLISECONDS);
        registerWifiListeners();
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        unregisterDisplayInfo();
        unregisterWifiListeners();
        if (watchdog != null) watchdog.shutdownNow();
        wifiWorker.shutdownNow();
        radioWorker.shutdownNow();
        dataWorker.shutdownNow();
    }

    @Override
    public void onAttachedToActivity(ActivityPluginBinding binding) {
        activity = binding.getActivity();
        activityBinding = binding;
        binding.addRequestPermissionsResultListener(this);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {
        onAttachedToActivity(binding);
    }

    @Override
    public void onDetachedFromActivity() {
        if (activityBinding != null) {
            activityBinding.removeRequestPermissionsResultListener(this);
        }
        activityBinding = null;
        activity = null;
    }

    // ---------------------------------------------------------------- methods

    @SuppressLint("MissingPermission")
    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "getRadioInfo":
                radioWorker.execute(() -> collect(result));
                break;
            case "getDataState":
                dataWorker.execute(() -> {
                    Map<String, Object> d = new HashMap<>();
                    try {
                        putDataState(d);
                    } catch (Exception ignored) {
                    }
                    mainHandler.post(() -> result.success(d));
                });
                break;
            case "getWifiEvents":
                wifiWorker.execute(() -> {
                    Map<String, Object> d = new HashMap<>();
                    List<Object> list = new ArrayList<>();
                    Map<String, Object> e;
                    while ((e = wifiEvents.poll()) != null) list.add(e);
                    d.put("events", list);
                    d.put("scansDelivered", scansDelivered);
                    putWifiBytes(d);
                    mainHandler.post(() -> result.success(d));
                });
                break;
            case "startWifiScan":
                wifiWorker.execute(() -> {
                    boolean ok = false;
                    try {
                        WifiManager wm = (WifiManager) context.getApplicationContext().getSystemService(Context.WIFI_SERVICE);
                        if (wm != null && wm.isWifiEnabled()) ok = wm.startScan();
                    } catch (Exception ignored) {
                    }
                    final boolean r = ok;
                    mainHandler.post(() -> result.success(r));
                });
                break;
            case "getMainThreadLag":
                result.success(maxMainLagMs.getAndSet(0));
                break;
            case "getDeviceInfo":
                result.success(deviceInfo());
                break;
            case "hasPhonePermission":
                result.success(hasPermission(Manifest.permission.READ_PHONE_STATE));
                break;
            case "requestPhonePermission":
                requestPhonePermission(result);
                break;
            default:
                result.notImplemented();
        }
    }

    /** Make, model, OS and (where Android still allows it) the last 4 digits of the IMEI. */
    @SuppressLint({"MissingPermission", "HardwareIds"})
    @SuppressWarnings("deprecation")
    private Map<String, Object> deviceInfo() {
        Map<String, Object> m = new HashMap<>();
        m.put("make", Build.MANUFACTURER);
        m.put("model", Build.MODEL);
        m.put("osVersion", "Android " + Build.VERSION.RELEASE);
        m.put("buildIncremental", Build.VERSION.INCREMENTAL); // Samsung: S938USQS4AYI1, Pixel: 13531031
        m.put("buildDisplay", Build.DISPLAY);
        // Marketing name ("Galaxy S25+"); the owner can rename it, so it is only a fallback.
        try {
            String name = android.provider.Settings.Global.getString(context.getContentResolver(), "device_name");
            if (name != null) m.put("marketName", name);
        } catch (Exception ignored) { }
        // Android 10+ only lets system apps read the IMEI; on older versions
        // READ_PHONE_STATE is enough. Only the last 4 digits are kept.
        try {
            TelephonyManager tm = (TelephonyManager) context.getSystemService(Context.TELEPHONY_SERVICE);
            if (tm != null && hasPermission(Manifest.permission.READ_PHONE_STATE)) {
                String imei = Build.VERSION.SDK_INT >= 26 ? tm.getImei() : tm.getDeviceId();
                if (imei != null && imei.length() >= 4) m.put("imeiLast4", imei.substring(imei.length() - 4));
            }
        } catch (Exception ignored) {
            // SecurityException on Android 10+: the tester enters it in Settings.
        }
        return m;
    }

    private boolean hasPermission(String permission) {
        if (Build.VERSION.SDK_INT < 23) return true;
        return context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED;
    }

    private void requestPhonePermission(MethodChannel.Result result) {
        if (hasPermission(Manifest.permission.READ_PHONE_STATE)) {
            result.success(true);
            return;
        }
        if (activity == null || Build.VERSION.SDK_INT < 23 || pendingPermissionResult != null) {
            result.success(false);
            return;
        }
        pendingPermissionResult = result;
        activity.requestPermissions(new String[]{Manifest.permission.READ_PHONE_STATE}, PERMISSION_REQUEST);
    }

    @Override
    public boolean onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        if (requestCode != PERMISSION_REQUEST) return false;
        boolean granted = grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED;
        if (pendingPermissionResult != null) {
            pendingPermissionResult.success(granted);
            pendingPermissionResult = null;
        }
        if (granted) registerDisplayInfo();
        return true;
    }

    // ---------------------------------------------------------------- 5G NSA detection

    private void registerDisplayInfo() {
        if (Build.VERSION.SDK_INT < 31 || displayInfoCallback != null) return;
        if (!hasPermission(Manifest.permission.READ_PHONE_STATE)) return;
        TelephonyManager tm = (TelephonyManager) context.getSystemService(Context.TELEPHONY_SERVICE);
        if (tm == null) return;
        try {
            DisplayInfoCallback cb = new DisplayInfoCallback();
            tm.registerTelephonyCallback(context.getMainExecutor(), cb);
            displayInfoCallback = cb;
        } catch (Exception ignored) {
            // SecurityException on some OEM builds; fall back to signal heuristics.
        }
    }

    private void unregisterDisplayInfo() {
        if (Build.VERSION.SDK_INT < 31 || displayInfoCallback == null) return;
        TelephonyManager tm = (TelephonyManager) context.getSystemService(Context.TELEPHONY_SERVICE);
        try {
            if (tm != null) tm.unregisterTelephonyCallback((TelephonyCallback) displayInfoCallback);
        } catch (Exception ignored) {
        }
        displayInfoCallback = null;
    }

    private class DisplayInfoCallback extends TelephonyCallback implements TelephonyCallback.DisplayInfoListener {
        @Override
        public void onDisplayInfoChanged(TelephonyDisplayInfo info) {
            overrideNetworkType = info.getOverrideNetworkType();
        }
    }

    // ---------------------------------------------------------------- collection

    private void collect(final MethodChannel.Result result) {
        final AtomicBoolean done = new AtomicBoolean(false);
        final TelephonyManager tm = (TelephonyManager) context.getSystemService(Context.TELEPHONY_SERVICE);
        registerDisplayInfo();

        if (Build.VERSION.SDK_INT >= 29 && tm != null
                && hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)) {
            try {
                tm.requestCellInfoUpdate(radioWorker, new TelephonyManager.CellInfoCallback() {
                    @Override
                    public void onCellInfo(List<CellInfo> cellInfo) {
                        finish(done, result, tm, cellInfo);
                    }

                    @Override
                    public void onError(int errorCode, Throwable detail) {
                        finish(done, result, tm, null);
                    }
                });
                // Some devices never call back; fall back to cached info.
                radioWorker.schedule(() -> finish(done, result, tm, null), 1500, TimeUnit.MILLISECONDS);
                return;
            } catch (Exception ignored) {
                // fall through
            }
        }
        finish(done, result, tm, null);
    }

    private void finish(AtomicBoolean done, final MethodChannel.Result result,
                        TelephonyManager tm, List<CellInfo> fresh) {
        if (!done.compareAndSet(false, true)) return;
        Map<String, Object> map;
        try {
            map = build(tm, fresh);
        } catch (Exception e) {
            map = new HashMap<>();
            map.put("platform", "android");
            map.put("error", e.toString());
        }
        final Map<String, Object> out = map;
        mainHandler.post(() -> result.success(out));
    }

    private Map<String, Object> build(TelephonyManager tm, List<CellInfo> fresh) {
        Map<String, Object> m = new HashMap<>();
        m.put("platform", "android");
        m.put("mainLagMs", maxMainLagMs.getAndSet(0)); // worst main-thread block since the last read
        String stack = mainStack.getAndSet(null);
        if (stack != null) m.put("mainStack", stack);
        m.put("connection", connectionType());
        m.put("internetValidated", internetValidated());
        m.put("phonePermission", hasPermission(Manifest.permission.READ_PHONE_STATE));
        m.put("locationPermission", hasPermission(Manifest.permission.ACCESS_FINE_LOCATION));
        putWifi(m);
        putDataState(m);
        if (tm == null) return m;

        try {
            m.put("operator", tm.getNetworkOperatorName());
            String op = tm.getNetworkOperator();
            if (op != null && op.length() >= 5) {
                m.put("mcc", op.substring(0, 3));
                m.put("mnc", op.substring(3));
            }
        } catch (Exception ignored) {
        }

        int dataType = -1;
        if (hasPermission(Manifest.permission.READ_PHONE_STATE)) {
            try {
                dataType = Build.VERSION.SDK_INT >= 24 ? tm.getDataNetworkType() : tm.getNetworkType();
            } catch (Exception ignored) {
            }
        }
        if (dataType >= 0) m.put("dataNetworkType", networkTypeName(dataType));
        if (overrideNetworkType >= 0) m.put("overrideNetworkType", overrideName(overrideNetworkType));

        List<CellInfo> cells = fresh;
        if (cells == null && hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)) {
            try {
                cells = tm.getAllCellInfo();
            } catch (Exception ignored) {
            }
        }

        boolean lteServing = false, nrServing = false, umtsServing = false, gsmServing = false;
        if (cells != null) {
            for (CellInfo ci : cells) {
                if (ci == null || !ci.isRegistered()) continue;
                if (ci instanceof CellInfoLte && !lteServing) {
                    putLte(m, (CellInfoLte) ci);
                    lteServing = true;
                } else if (Build.VERSION.SDK_INT >= 29 && ci instanceof CellInfoNr && !nrServing) {
                    putNr(m, (CellInfoNr) ci);
                    nrServing = true;
                } else if (Build.VERSION.SDK_INT >= 18 && ci instanceof CellInfoWcdma && !umtsServing) {
                    CellInfoWcdma w = (CellInfoWcdma) ci;
                    CellIdentityWcdma id = w.getCellIdentity();
                    putInt(m, "umtsDbm", w.getCellSignalStrength().getDbm());
                    putInt(m, "umtsCid", id.getCid());
                    putInt(m, "umtsLac", id.getLac());
                    putInt(m, "umtsPsc", id.getPsc());
                    if (Build.VERSION.SDK_INT >= 24) putInt(m, "umtsUarfcn", id.getUarfcn());
                    umtsServing = true;
                } else if (ci instanceof CellInfoGsm && !gsmServing) {
                    CellInfoGsm g = (CellInfoGsm) ci;
                    CellIdentityGsm id = g.getCellIdentity();
                    putInt(m, "gsmDbm", g.getCellSignalStrength().getDbm());
                    putInt(m, "gsmCid", id.getCid());
                    putInt(m, "gsmLac", id.getLac());
                    if (Build.VERSION.SDK_INT >= 24) putInt(m, "gsmArfcn", id.getArfcn());
                    gsmServing = true;
                }
            }
        }

        // In 5G NSA, the NR leg usually isn't a "registered" cell; its signal
        // only shows up in SignalStrength.
        boolean nrSignalSeen = nrServing;
        if (!nrServing && Build.VERSION.SDK_INT >= 29) {
            try {
                SignalStrength ss = tm.getSignalStrength();
                if (ss != null) {
                    for (CellSignalStrength css : ss.getCellSignalStrengths()) {
                        if (css instanceof CellSignalStrengthNr) {
                            CellSignalStrengthNr nr = (CellSignalStrengthNr) css;
                            if (nr.getSsRsrp() != UNAVAILABLE) {
                                putNrSignal(m, nr);
                                nrSignalSeen = true;
                            }
                        } else if (css instanceof CellSignalStrengthLte && !lteServing) {
                            CellSignalStrengthLte lte = (CellSignalStrengthLte) css;
                            putLteSignal(m, lte);
                        }
                    }
                }
            } catch (Exception ignored) {
            }
        }

        m.put("rat", ratLabel(dataType, lteServing, nrServing, nrSignalSeen, umtsServing, gsmServing));
        return m;
    }

    private String ratLabel(int dataType, boolean lte, boolean nr, boolean nrSignal,
                            boolean umts, boolean gsm) {
        int ov = overrideNetworkType;
        if (dataType == 20) return "5G SA";
        if (dataType == 13 || dataType == 19 || (dataType <= 0 && lte)) {
            if (ov == 5) return "5G NSA+"; // NR Advanced / mmWave
            if (ov == 4) return "5G NSA mmWave";
            if (ov == 3 || nrSignal) return "5G NSA";
            if (ov == 2) return "LTE-A Pro";
            if (ov == 1 || dataType == 19) return "LTE-CA";
            return "LTE";
        }
        if (dataType <= 0 && nr) return "5G SA";
        switch (dataType) {
            case 3: case 5: case 6: case 8: case 9: case 10: case 12: case 14: case 15: case 17:
                return "3G";
            case 1: case 2: case 4: case 7: case 11: case 16:
                return "2G";
            case 18:
                return "IWLAN";
            default:
                break;
        }
        if (umts) return "3G";
        if (gsm) return "2G";
        return dataType == 0 ? "No service" : "Unknown";
    }

    private void putLte(Map<String, Object> m, CellInfoLte ci) {
        CellIdentityLte id = ci.getCellIdentity();
        putLteSignal(m, ci.getCellSignalStrength());
        putInt(m, "ltePci", id.getPci());
        putInt(m, "lteTac", id.getTac());
        int eci = id.getCi();
        if (eci != UNAVAILABLE && eci >= 0) {
            m.put("lteEci", eci);
            m.put("lteEnb", eci >> 8);
            m.put("lteCellId", eci & 0xFF);
        }
        if (Build.VERSION.SDK_INT >= 24) putInt(m, "lteEarfcn", id.getEarfcn());
        if (Build.VERSION.SDK_INT >= 28) putInt(m, "lteBandwidthKhz", id.getBandwidth());
        if (Build.VERSION.SDK_INT >= 30) {
            int[] bands = id.getBands();
            if (bands != null && bands.length > 0) m.put("lteBand", joinBands(bands));
        }
    }

    private void putLteSignal(Map<String, Object> m, CellSignalStrengthLte ss) {
        if (Build.VERSION.SDK_INT >= 26) {
            putInt(m, "lteRsrp", ss.getRsrp());
            putInt(m, "lteRsrq", ss.getRsrq());
            putInt(m, "lteSinr", ss.getRssnr());
            putInt(m, "lteCqi", ss.getCqi());
        } else {
            putInt(m, "lteRsrp", ss.getDbm());
        }
        if (Build.VERSION.SDK_INT >= 29) putInt(m, "lteRssi", ss.getRssi());
        putInt(m, "lteTimingAdvance", ss.getTimingAdvance());
    }

    private void putNr(Map<String, Object> m, CellInfoNr ci) {
        if (Build.VERSION.SDK_INT < 29) return;
        CellIdentityNr id = (CellIdentityNr) ci.getCellIdentity();
        putNrSignal(m, (CellSignalStrengthNr) ci.getCellSignalStrength());
        putInt(m, "nrPci", id.getPci());
        putInt(m, "nrTac", id.getTac());
        long nci = id.getNci();
        if (nci != Long.MAX_VALUE && nci >= 0) m.put("nrNci", nci);
        putInt(m, "nrArfcn", id.getNrarfcn());
        if (Build.VERSION.SDK_INT >= 30) {
            int[] bands = id.getBands();
            if (bands != null && bands.length > 0) m.put("nrBand", "n" + joinBands(bands).replace("/", "/n"));
        }
    }

    private void putNrSignal(Map<String, Object> m, CellSignalStrengthNr ss) {
        if (Build.VERSION.SDK_INT < 29) return;
        putInt(m, "nrSsRsrp", ss.getSsRsrp());
        putInt(m, "nrSsRsrq", ss.getSsRsrq());
        putInt(m, "nrSsSinr", ss.getSsSinr());
        putInt(m, "nrCsiRsrp", ss.getCsiRsrp());
        putInt(m, "nrCsiSinr", ss.getCsiSinr());
    }

    private static void putInt(Map<String, Object> m, String key, int value) {
        if (value != UNAVAILABLE && value != Integer.MIN_VALUE) m.put(key, value);
    }

    private static String joinBands(int[] bands) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < bands.length; i++) {
            if (i > 0) sb.append('/');
            sb.append(bands[i]);
        }
        return sb.toString();
    }

    @SuppressWarnings("deprecation")
    private void putWifi(Map<String, Object> m) {
        try {
            WifiManager wm = (WifiManager) context.getApplicationContext().getSystemService(Context.WIFI_SERVICE);
            if (wm == null || !wm.isWifiEnabled()) return;
            WifiInfo info = wm.getConnectionInfo();
            if (info == null || info.getNetworkId() == -1) return;
            String ssid = info.getSSID();
            if (ssid != null && !ssid.equals("<unknown ssid>")) {
                if (ssid.length() >= 2 && ssid.startsWith("\"") && ssid.endsWith("\"")) {
                    ssid = ssid.substring(1, ssid.length() - 1);
                }
                m.put("wifiSsid", ssid);
            }
            String bssid = info.getBSSID();
            if (bssid != null && !bssid.equals("02:00:00:00:00:00")) m.put("wifiBssid", bssid);
            int rssi = info.getRssi();
            if (rssi > -127 && rssi < 0) m.put("wifiRssi", rssi);
            int link = info.getLinkSpeed();
            if (link > 0) m.put("wifiLinkMbps", link);
            if (Build.VERSION.SDK_INT >= 29) {
                int tx = info.getTxLinkSpeedMbps();
                int rx = info.getRxLinkSpeedMbps();
                if (tx > 0) m.put("wifiTxMbps", tx);
                if (rx > 0) m.put("wifiRxMbps", rx);
            }
            if (Build.VERSION.SDK_INT >= 21) {
                int freq = info.getFrequency();
                if (freq > 0) {
                    m.put("wifiFreqMhz", freq);
                    m.put("wifiBand", wifiBand(freq));
                    int ch = wifiChannel(freq);
                    if (ch > 0) m.put("wifiChannel", ch);
                }
            }
            if (Build.VERSION.SDK_INT >= 30) m.put("wifiStandard", wifiStandardName(info.getWifiStandard()));
        } catch (Exception ignored) {
        }
    }

    private static String wifiBand(int freq) {
        if (freq >= 2400 && freq < 2500) return "2.4 GHz";
        if (freq >= 4900 && freq < 5900) return "5 GHz";
        if (freq >= 5925 && freq < 7125) return "6 GHz";
        if (freq >= 58000) return "60 GHz";
        return freq + " MHz";
    }

    private static int wifiChannel(int freq) {
        if (freq == 2484) return 14;
        if (freq >= 2412 && freq < 2484) return (freq - 2407) / 5;
        if (freq >= 5955 && freq <= 7115) return (freq - 5950) / 5; // 6 GHz
        if (freq >= 5000 && freq < 5900) return (freq - 5000) / 5;
        return -1;
    }

    private static String wifiStandardName(int s) {
        switch (s) {
            case 1: return "Legacy (a/b/g)";
            case 4: return "Wi-Fi 4 (n)";
            case 5: return "Wi-Fi 5 (ac)";
            case 6: return "Wi-Fi 6/6E (ax)";
            case 7: return "WiGig (ad)";
            case 8: return "Wi-Fi 7 (be)";
            default: return "Unknown";
        }
    }

    // ---------------------------------------------------------------- Wi-Fi scans and joins

    /**
     * Listens to the phone's Wi-Fi scans (every scan, whoever started it) and to
     * the connection steps: CONNECTING / AUTHENTICATING / OBTAINING_IPADDR /
     * CONNECTED (network state), ASSOCIATING ... COMPLETED (supplicant), IP
     * available, internet validated and lost (network callback). Each event gets
     * the wall-clock time (ms) at which it happened.
     */
    @SuppressWarnings("deprecation")
    private void registerWifiListeners() {
        if (wifiReceiver != null) return;
        wifiReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context c, Intent intent) {
                final long now = System.currentTimeMillis();
                final String action = intent.getAction();
                if (WifiManager.SCAN_RESULTS_AVAILABLE_ACTION.equals(action)) {
                    final boolean updated = intent.getBooleanExtra(WifiManager.EXTRA_RESULTS_UPDATED, true);
                    wifiWorker.execute(() -> queueScan(now, updated));
                } else if (WifiManager.NETWORK_STATE_CHANGED_ACTION.equals(action)) {
                    NetworkInfo ni = intent.getParcelableExtra(WifiManager.EXTRA_NETWORK_INFO);
                    final String st = ni == null ? null : String.valueOf(ni.getDetailedState());
                    wifiWorker.execute(() -> queueState(now, "network", st, 0));
                } else if (WifiManager.SUPPLICANT_STATE_CHANGED_ACTION.equals(action)) {
                    SupplicantState ss = intent.getParcelableExtra(WifiManager.EXTRA_NEW_STATE);
                    final int err = intent.getIntExtra(WifiManager.EXTRA_SUPPLICANT_ERROR, 0);
                    final String st = ss == null ? null : ss.name();
                    wifiWorker.execute(() -> queueState(now, "supplicant", st, err));
                }
            }
        };
        IntentFilter f = new IntentFilter();
        f.addAction(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION);
        f.addAction(WifiManager.NETWORK_STATE_CHANGED_ACTION);
        f.addAction(WifiManager.SUPPLICANT_STATE_CHANGED_ACTION);
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                context.registerReceiver(wifiReceiver, f, Context.RECEIVER_EXPORTED);
            } else {
                context.registerReceiver(wifiReceiver, f);
            }
        } catch (Exception ignored) {
            wifiReceiver = null;
        }
        if (Build.VERSION.SDK_INT >= 24) {
            try {
                ConnectivityManager cm = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
                NetworkRequest req = new NetworkRequest.Builder()
                        .addTransportType(NetworkCapabilities.TRANSPORT_WIFI).build();
                wifiNetCallback = new ConnectivityManager.NetworkCallback() {
                    private boolean validated = false;

                    @Override
                    public void onAvailable(Network n) {
                        validated = false;
                        queueNet("IP available");
                    }

                    @Override
                    public void onCapabilitiesChanged(Network n, NetworkCapabilities nc) {
                        boolean v = nc.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED);
                        if (v && !validated) queueNet("Internet validated");
                        validated = v;
                    }

                    @Override
                    public void onLost(Network n) {
                        validated = false;
                        queueNet("Lost");
                    }
                };
                if (cm != null) cm.registerNetworkCallback(req, wifiNetCallback);
            } catch (Exception ignored) {
                wifiNetCallback = null;
            }
        }
    }

    private void unregisterWifiListeners() {
        try {
            if (wifiReceiver != null) context.unregisterReceiver(wifiReceiver);
        } catch (Exception ignored) {
        }
        wifiReceiver = null;
        try {
            ConnectivityManager cm = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
            if (cm != null && wifiNetCallback != null) cm.unregisterNetworkCallback(wifiNetCallback);
        } catch (Exception ignored) {
        }
        wifiNetCallback = null;
    }

    private void offer(Map<String, Object> e) {
        if (wifiEvents.size() > 5000) wifiEvents.poll(); // app not collecting; keep the newest
        wifiEvents.add(e);
    }

    private void queueNet(String what) {
        Map<String, Object> e = new HashMap<>();
        e.put("kind", "net");
        e.put("t", System.currentTimeMillis());
        e.put("state", what);
        wifiWorker.execute(() -> {
            putConnected(e);
            offer(e);
        });
    }

    private void queueState(long t, String source, String state, int error) {
        if (state == null) return;
        Map<String, Object> e = new HashMap<>();
        e.put("kind", source);
        e.put("t", t);
        e.put("state", state);
        if (error != 0) e.put("error", error == 1 ? "Authentication failed" : "Error " + error);
        putConnected(e);
        offer(e);
    }

    /** SSID / BSSID / RSSI / frequency of the network being joined or connected. */
    @SuppressWarnings("deprecation")
    @SuppressLint("MissingPermission")
    private void putConnected(Map<String, Object> e) {
        try {
            WifiManager wm = (WifiManager) context.getApplicationContext().getSystemService(Context.WIFI_SERVICE);
            if (wm == null) return;
            WifiInfo info = wm.getConnectionInfo();
            if (info == null) return;
            String ssid = cleanSsid(info.getSSID());
            if (ssid != null) e.put("ssid", ssid);
            String bssid = info.getBSSID();
            if (bssid != null && !bssid.equals("02:00:00:00:00:00") && !bssid.equals("00:00:00:00:00:00")) e.put("bssid", bssid);
            int rssi = info.getRssi();
            if (rssi > -127 && rssi < 0) e.put("rssi", rssi);
            if (Build.VERSION.SDK_INT >= 21 && info.getFrequency() > 0) e.put("freq", info.getFrequency());
            if (Build.VERSION.SDK_INT >= 29 && info.getPasspointFqdn() != null) e.put("passpoint", true);
        } catch (Exception ignored) {
        }
    }

    private static String cleanSsid(String ssid) {
        if (ssid == null || ssid.equals("<unknown ssid>") || ssid.isEmpty()) return null;
        if (ssid.length() >= 2 && ssid.startsWith("\"") && ssid.endsWith("\"")) ssid = ssid.substring(1, ssid.length() - 1);
        return ssid;
    }

    /**
     * One scan's results. "heard" is when each AP's beacon / probe response was
     * received (ScanResult.timestamp, converted from time since boot to wall clock).
     */
    @SuppressWarnings("deprecation")
    @SuppressLint("MissingPermission")
    private void queueScan(long t, boolean updated) {
        scansDelivered++;
        Map<String, Object> e = new HashMap<>();
        e.put("kind", "scan");
        e.put("t", t);
        e.put("updated", updated);
        List<Object> aps = new ArrayList<>();
        try {
            WifiManager wm = (WifiManager) context.getApplicationContext().getSystemService(Context.WIFI_SERVICE);
            List<ScanResult> res = wm == null ? null : wm.getScanResults();
            long bootToWall = System.currentTimeMillis() - android.os.SystemClock.elapsedRealtime();
            if (res != null) {
                for (ScanResult r : res) {
                    Map<String, Object> a = new HashMap<>();
                    a.put("ssid", r.SSID == null ? "" : r.SSID);
                    a.put("bssid", r.BSSID);
                    a.put("rssi", r.level);
                    a.put("freq", r.frequency);
                    if (Build.VERSION.SDK_INT >= 17) a.put("heard", bootToWall + r.timestamp / 1000);
                    if (Build.VERSION.SDK_INT >= 23) {
                        if (r.isPasspointNetwork()) a.put("passpoint", true);
                        if (r.operatorFriendlyName != null && r.operatorFriendlyName.length() > 0) {
                            a.put("operator", r.operatorFriendlyName.toString());
                        }
                    }
                    aps.add(a);
                }
            }
        } catch (Exception ex) {
            e.put("error", ex.toString());
        }
        e.put("aps", aps);
        putConnected(e);
        offer(e);
    }

    /** Bytes sent and received on non-cellular networks (Wi-Fi) since boot. */
    private void putWifiBytes(Map<String, Object> d) {
        try {
            long rx = TrafficStats.getTotalRxBytes(), tx = TrafficStats.getTotalTxBytes();
            long mrx = TrafficStats.getMobileRxBytes(), mtx = TrafficStats.getMobileTxBytes();
            if (rx < 0 || tx < 0) return;
            d.put("wifiRxBytes", rx - Math.max(0, mrx));
            d.put("wifiTxBytes", tx - Math.max(0, mtx));
        } catch (Exception ignored) {
        }
    }

    /**
     * Dual SIM (DSDS): which SIM carries mobile data, its carrier and PLMN,
     * and the cellular data interface with its IP addresses.
     * Keys: dataSubId, dataSimSlot (1-based), dataCarrier, dataPlmn, sims,
     * cellIface, cellIpv4, cellIpv6 (comma-separated, no link-local), cellNetSubId.
     */
    @SuppressLint("MissingPermission")
    private void putDataState(Map<String, Object> m) {
        int dataSub = -1;
        try {
            if (Build.VERSION.SDK_INT >= 30) dataSub = SubscriptionManager.getActiveDataSubscriptionId();
            if (dataSub < 0 && Build.VERSION.SDK_INT >= 24) dataSub = SubscriptionManager.getDefaultDataSubscriptionId();
            if (dataSub >= 0) m.put("dataSubId", dataSub);
        } catch (Exception ignored) {
        }
        try {
            SubscriptionManager sm = (SubscriptionManager) context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE);
            if (sm != null && hasPermission(Manifest.permission.READ_PHONE_STATE)) {
                List<SubscriptionInfo> subs = sm.getActiveSubscriptionInfoList();
                if (subs != null) {
                    StringBuilder all = new StringBuilder();
                    for (SubscriptionInfo si : subs) {
                        String plmn = Build.VERSION.SDK_INT >= 29
                                ? (si.getMccString() == null ? "" : si.getMccString()) + (si.getMncString() == null ? "" : si.getMncString())
                                : String.format("%03d%02d", si.getMcc(), si.getMnc());
                        String name = String.valueOf(si.getCarrierName());
                        int slot = si.getSimSlotIndex() + 1;
                        if (all.length() > 0) all.append("; ");
                        all.append("SIM").append(slot).append(' ').append(name).append(' ').append(plmn);
                        if (si.getSubscriptionId() == dataSub) {
                            m.put("dataSimSlot", slot);
                            m.put("dataCarrier", name);
                            m.put("dataPlmn", plmn);
                        }
                    }
                    m.put("sims", all.toString());
                }
            }
        } catch (Exception ignored) {
        }
        try {
            ConnectivityManager cm = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
            if (cm == null) return;
            // The network new sockets use; when it changes, open tests are on a network that is going away.
            if (Build.VERSION.SDK_INT >= 23) {
                Network active = cm.getActiveNetwork();
                m.put("defaultNet", active == null ? "" : active.toString());
            }
            Network best = null;
            int bestSub = -1;
            for (Network n : cm.getAllNetworks()) {
                NetworkCapabilities nc = cm.getNetworkCapabilities(n);
                if (nc == null || !nc.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)
                        || !nc.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) continue;
                int sub = -1;
                if (Build.VERSION.SDK_INT >= 30) {
                    NetworkSpecifier spec = nc.getNetworkSpecifier();
                    if (spec instanceof TelephonyNetworkSpecifier) sub = ((TelephonyNetworkSpecifier) spec).getSubscriptionId();
                }
                if (best == null || (sub >= 0 && sub == dataSub)) {
                    best = n;
                    bestSub = sub;
                }
            }
            if (best == null) return;
            LinkProperties lp = cm.getLinkProperties(best);
            if (lp == null) return;
            StringBuilder v4 = new StringBuilder(), v6 = new StringBuilder();
            for (LinkAddress la : lp.getLinkAddresses()) {
                java.net.InetAddress a = la.getAddress();
                if (a == null || a.isLinkLocalAddress() || a.isLoopbackAddress()) continue;
                String s = a.getHostAddress();
                if (s == null) continue;
                int pct = s.indexOf('%');
                if (pct >= 0) s = s.substring(0, pct);
                StringBuilder b = a instanceof java.net.Inet4Address ? v4 : v6;
                if (b.length() > 0) b.append(',');
                b.append(s);
            }
            if (lp.getInterfaceName() != null) m.put("cellIface", lp.getInterfaceName());
            if (v4.length() > 0) m.put("cellIpv4", v4.toString());
            if (v6.length() > 0) m.put("cellIpv6", v6.toString());
            if (bestSub >= 0) m.put("cellNetSubId", bestSub);
        } catch (Exception ignored) {
        }
    }

    /** True when Android has checked that the active network reaches the internet. */
    private boolean internetValidated() {
        try {
            ConnectivityManager cm = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
            if (cm == null || Build.VERSION.SDK_INT < 23) return true;
            Network n = cm.getActiveNetwork();
            if (n == null) return false;
            NetworkCapabilities caps = cm.getNetworkCapabilities(n);
            return caps != null && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED);
        } catch (Exception e) {
            return true;
        }
    }

    private String connectionType() {
        try {
            ConnectivityManager cm = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
            if (cm == null || Build.VERSION.SDK_INT < 23) return "UNKNOWN";
            Network n = cm.getActiveNetwork();
            if (n == null) return "NONE";
            NetworkCapabilities caps = cm.getNetworkCapabilities(n);
            if (caps == null) return "NONE";
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) return "WIFI";
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) return "CELLULAR";
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) return "ETHERNET";
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) return "VPN";
            return "OTHER";
        } catch (Exception e) {
            return "UNKNOWN";
        }
    }

    private static String networkTypeName(int t) {
        switch (t) {
            case 0: return "UNKNOWN";
            case 1: return "GPRS";
            case 2: return "EDGE";
            case 3: return "UMTS";
            case 4: return "CDMA";
            case 5: return "EVDO_0";
            case 6: return "EVDO_A";
            case 7: return "1xRTT";
            case 8: return "HSDPA";
            case 9: return "HSUPA";
            case 10: return "HSPA";
            case 11: return "IDEN";
            case 12: return "EVDO_B";
            case 13: return "LTE";
            case 14: return "EHRPD";
            case 15: return "HSPAP";
            case 16: return "GSM";
            case 17: return "TD_SCDMA";
            case 18: return "IWLAN";
            case 19: return "LTE_CA";
            case 20: return "NR";
            default: return "TYPE_" + t;
        }
    }

    private static String overrideName(int t) {
        switch (t) {
            case 0: return "NONE";
            case 1: return "LTE_CA";
            case 2: return "LTE_ADVANCED_PRO";
            case 3: return "NR_NSA";
            case 4: return "NR_NSA_MMWAVE";
            case 5: return "NR_ADVANCED";
            default: return "TYPE_" + t;
        }
    }
}
