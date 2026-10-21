package com.wifianalytics.screen_record;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.hardware.display.DisplayManager;
import android.hardware.display.VirtualDisplay;
import android.media.MediaRecorder;
import android.media.projection.MediaProjection;
import android.media.projection.MediaProjectionManager;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.util.DisplayMetrics;

import java.io.File;

/** Foreground service that owns the MediaProjection and writes the MP4. */
public class ScreenRecordService extends Service {
    static final String ACTION_START = "com.wifianalytics.screen_record.START";
    static final String EXTRA_CODE = "code";
    static final String EXTRA_DATA = "data";
    static final String EXTRA_PATH = "path";
    private static final String CHANNEL_ID = "screen_record";
    private static final int NOTIFICATION_ID = 7421;
    private static final int MAX_SIDE = 1280;      // keeps files small
    private static final int BITRATE = 3_000_000;  // about 22 MB per minute at most
    private static final int FPS = 30;

    static volatile boolean recording = false;
    static volatile String currentPath = null;
    static volatile long startedMs = 0;
    static volatile String lastError = null;
    private static ScreenRecordService instance;

    private MediaProjection projection;
    private MediaRecorder recorder;
    private VirtualDisplay display;

    /** Stops the recording and returns the file path (null when nothing was recording). */
    static synchronized String stopNow() {
        ScreenRecordService s = instance;
        String path = currentPath;
        if (s == null || !recording) return null;
        s.finish();
        return path;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null || !ACTION_START.equals(intent.getAction())) {
            stopSelf();
            return START_NOT_STICKY;
        }
        // The foreground notification must be up before the projection is used (Android 14).
        startAsForeground();
        try {
            begin(intent.getIntExtra(EXTRA_CODE, 0), (Intent) intent.getParcelableExtra(EXTRA_DATA),
                    intent.getStringExtra(EXTRA_PATH));
        } catch (Exception e) {
            lastError = "Could not start screen recording: " + e.getMessage();
            releaseAll();
            recording = false;
            stopSelf();
        }
        return START_NOT_STICKY;
    }

    private void startAsForeground() {
        NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        Notification.Builder nb;
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                    new NotificationChannel(CHANNEL_ID, "Screen recording", NotificationManager.IMPORTANCE_LOW));
            nb = new Notification.Builder(this, CHANNEL_ID);
        } else {
            nb = new Notification.Builder(this);
        }
        Notification n = nb.setContentTitle("WiFi Analytics")
                .setContentText("Recording the screen. Stop it in the app.")
                .setSmallIcon(android.R.drawable.ic_menu_camera)
                .setOngoing(true)
                .build();
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION);
        } else {
            startForeground(NOTIFICATION_ID, n);
        }
    }

    private void begin(int resultCode, Intent data, String path) throws Exception {
        if (data == null || path == null) throw new IllegalArgumentException("missing projection data or path");
        File out = new File(path);
        File dir = out.getParentFile();
        if (dir != null && !dir.exists()) //noinspection ResultOfMethodCallIgnored
            dir.mkdirs();

        MediaProjectionManager mpm = (MediaProjectionManager) getSystemService(Context.MEDIA_PROJECTION_SERVICE);
        projection = mpm.getMediaProjection(resultCode, data);
        // Android 14 requires a callback to be registered before the virtual display is created.
        projection.registerCallback(new MediaProjection.Callback() {
            @Override
            public void onStop() {
                if (recording) finish(); // the phone ended the projection (for example from the system UI)
            }
        }, new Handler(Looper.getMainLooper()));

        DisplayMetrics m = getResources().getDisplayMetrics();
        float scale = Math.min(1f, (float) MAX_SIDE / Math.max(m.widthPixels, m.heightPixels));
        int w = even(Math.round(m.widthPixels * scale));
        int h = even(Math.round(m.heightPixels * scale));

        recorder = Build.VERSION.SDK_INT >= 31 ? new MediaRecorder(this) : new MediaRecorder();
        recorder.setVideoSource(MediaRecorder.VideoSource.SURFACE);
        recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4);
        recorder.setVideoEncoder(MediaRecorder.VideoEncoder.H264);
        recorder.setVideoSize(w, h);
        recorder.setVideoFrameRate(FPS);
        recorder.setVideoEncodingBitRate(BITRATE);
        recorder.setOutputFile(out.getAbsolutePath());
        recorder.prepare();

        display = projection.createVirtualDisplay("WiFiAnalyticsRecording", w, h, m.densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, recorder.getSurface(), null, null);
        recorder.start();

        instance = this;
        currentPath = path;
        startedMs = System.currentTimeMillis();
        recording = true;
    }

    private static int even(int v) {
        return Math.max(2, v & ~1);
    }

    /** Stops, finalizes the file and ends the service. Safe to call more than once. */
    synchronized void finish() {
        boolean wasRecording = recording;
        recording = false;
        String path = currentPath;
        if (recorder != null) {
            try {
                recorder.stop();
            } catch (RuntimeException e) {
                // Stopped immediately after start: no frames, the file is invalid.
                if (path != null) //noinspection ResultOfMethodCallIgnored
                    new File(path).delete();
                if (wasRecording) lastError = "Recording was too short to save";
            }
        }
        releaseAll();
        stopForeground(true);
        stopSelf();
    }

    private void releaseAll() {
        try {
            if (display != null) display.release();
        } catch (Exception ignored) {
        }
        display = null;
        try {
            if (recorder != null) {
                recorder.reset();
                recorder.release();
            }
        } catch (Exception ignored) {
        }
        recorder = null;
        // Clear the field first: projection.stop() calls the callback, which calls finish() again.
        MediaProjection p = projection;
        projection = null;
        if (instance == this) instance = null;
        try {
            if (p != null) p.stop();
        } catch (Exception ignored) {
        }
    }

    @Override
    public void onDestroy() {
        if (recording) finish();
        super.onDestroy();
    }
}
