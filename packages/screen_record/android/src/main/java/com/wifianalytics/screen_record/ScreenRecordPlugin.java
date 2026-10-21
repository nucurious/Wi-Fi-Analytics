package com.wifianalytics.screen_record;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.media.projection.MediaProjectionManager;
import android.os.Build;

import androidx.annotation.NonNull;

import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

/** Screen recording for WiFi Analytics: MediaProjection consent + a foreground service. */
public class ScreenRecordPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler,
        ActivityAware, PluginRegistry.ActivityResultListener {
    private static final int REQ_CAPTURE = 7421;

    private MethodChannel channel;
    private Context context;
    private Activity activity;
    private ActivityPluginBinding binding;
    private MethodChannel.Result pendingResult;
    private String pendingPath;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding b) {
        context = b.getApplicationContext();
        channel = new MethodChannel(b.getBinaryMessenger(), "wifi_analytics/screen_record");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding b) {
        channel.setMethodCallHandler(null);
        channel = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "start": {
                String path = call.argument("path");
                if (path == null || path.isEmpty()) {
                    result.error("bad_args", "path is required", null);
                    return;
                }
                if (ScreenRecordService.recording) {
                    result.success(true);
                    return;
                }
                if (activity == null || pendingResult != null) {
                    result.success(false);
                    return;
                }
                if (Build.VERSION.SDK_INT < 21) {
                    result.success(false);
                    return;
                }
                pendingResult = result;
                pendingPath = path;
                MediaProjectionManager mpm =
                        (MediaProjectionManager) context.getSystemService(Context.MEDIA_PROJECTION_SERVICE);
                activity.startActivityForResult(mpm.createScreenCaptureIntent(), REQ_CAPTURE);
                break;
            }
            case "stop": {
                result.success(ScreenRecordService.stopNow());
                break;
            }
            case "status": {
                Map<String, Object> m = new HashMap<>();
                m.put("recording", ScreenRecordService.recording);
                m.put("path", ScreenRecordService.currentPath);
                m.put("startedMs", ScreenRecordService.startedMs);
                m.put("error", ScreenRecordService.lastError);
                result.success(m);
                break;
            }
            default:
                result.notImplemented();
        }
    }

    @Override
    public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != REQ_CAPTURE) return false;
        MethodChannel.Result r = pendingResult;
        String path = pendingPath;
        pendingResult = null;
        pendingPath = null;
        if (r == null) return true;
        if (resultCode != Activity.RESULT_OK || data == null) {
            ScreenRecordService.lastError = "Screen recording was not allowed";
            r.success(false);
            return true;
        }
        ScreenRecordService.lastError = null;
        Intent svc = new Intent(context, ScreenRecordService.class);
        svc.setAction(ScreenRecordService.ACTION_START);
        svc.putExtra(ScreenRecordService.EXTRA_CODE, resultCode);
        svc.putExtra(ScreenRecordService.EXTRA_DATA, data);
        svc.putExtra(ScreenRecordService.EXTRA_PATH, path);
        if (Build.VERSION.SDK_INT >= 26) {
            context.startForegroundService(svc);
        } else {
            context.startService(svc);
        }
        r.success(true);
        return true;
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding b) {
        binding = b;
        activity = b.getActivity();
        b.addActivityResultListener(this);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        detach();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding b) {
        onAttachedToActivity(b);
    }

    @Override
    public void onDetachedFromActivity() {
        detach();
    }

    private void detach() {
        if (binding != null) binding.removeActivityResultListener(this);
        binding = null;
        activity = null;
    }
}
