/*
 * Amadi additions to Arc Launcher (GPL-3.0-or-later).
 * Keeps the TV's Wi-Fi out of power-save mode all the time (power-save causes
 * lag spikes and buffering on these TVs). Runs in its own small process so it
 * stays alive when Android closes the launcher to make room for YouTube.
 */
package com.omeda.arc;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.IBinder;

public class AmadiWifiService extends Service {
    private WifiManager.WifiLock lock;
    private android.content.BroadcastReceiver screenOn;

    /**
     * Sets the TV volume to the "volume at power-on" setting (default 5), so a guest
     * never turns the TV on to whatever the last guest left it at. Empty = off.
     */
    public static void applyStartVolume(Context c) {
        try {
            String v = pref(c, "flutter.amadi_start_volume", "5");
            if (v == null || v.trim().isEmpty()) return;
            int want = Integer.parseInt(v.trim());
            android.media.AudioManager am = (android.media.AudioManager) c.getSystemService(Context.AUDIO_SERVICE);
            if (am == null) return;
            int max = am.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC);
            am.setStreamVolume(android.media.AudioManager.STREAM_MUSIC, Math.max(0, Math.min(want, max)), 0);
        } catch (Throwable ignored) {}
    }

    /** Re-reads the launcher's settings file (it is written by the launcher process). */
    @SuppressWarnings("deprecation")
    private static String pref(Context c, String key, String def) {
        android.content.SharedPreferences p = c.getSharedPreferences("FlutterSharedPreferences",
                Context.MODE_PRIVATE | Context.MODE_MULTI_PROCESS);
        return p.getString(key, def);
    }

    public static void start(Context c) {
        try {
            Intent i = new Intent(c, AmadiWifiService.class);
            if (Build.VERSION.SDK_INT >= 26) c.startForegroundService(i); else c.startService(i);
        } catch (Throwable ignored) {}
    }

    @Override
    public void onCreate() {
        super.onCreate();
        Notification.Builder b;
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
            nm.createNotificationChannel(new NotificationChannel("amadi_wifi", "Wi-Fi", NotificationManager.IMPORTANCE_MIN));
            b = new Notification.Builder(this, "amadi_wifi");
        } else {
            b = new Notification.Builder(this);
        }
        startForeground(7, b.setContentTitle("Wi-Fi at full speed").setSmallIcon(android.R.drawable.stat_sys_download_done).build());
        WifiManager wm = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        if (wm != null) {
            lock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "amadi-always");
            lock.setReferenceCounted(false);
            lock.acquire();
        }
        // The TV's "power button" usually just turns the screen off and on: reset volume then too.
        screenOn = new android.content.BroadcastReceiver() {
            @Override public void onReceive(Context c, Intent i) {
                applyStartVolume(c);
                AmadiUpdater.checkAsync(c, true); // power on: update straight away if there's a new build
            }
        };
        registerReceiver(screenOn, new android.content.IntentFilter(Intent.ACTION_SCREEN_ON));
        // Started at boot: check for a launcher update (after a moment for Wi-Fi to connect).
        new android.os.Handler(android.os.Looper.getMainLooper())
                .postDelayed(() -> AmadiUpdater.checkAsync(AmadiWifiService.this, true), 45 * 1000L);
        // CVTE (Onwa) TVs: make sure the TV powers on when mains power returns.
        AmadiCvtePower.applyAsync(this);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        if (screenOn != null) try { unregisterReceiver(screenOn); } catch (Throwable ignored) {}
        if (lock != null && lock.isHeld()) lock.release();
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }
}
