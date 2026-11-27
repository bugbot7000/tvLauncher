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
    private android.content.BroadcastReceiver volumeChanged;
    private android.database.ContentObserver volumeObserver;

    /**
     * Sets the TV volume to the "volume at power-on" setting (default 15), so a guest
     * never turns the TV on to whatever the last guest left it at. Empty = off.
     */
    public static void applyStartVolume(Context c) {
        try {
            String v = pref(c, "flutter.amadi_start_volume", "15");
            if (v == null || v.trim().isEmpty()) return;
            int want = Integer.parseInt(v.trim());
            android.media.AudioManager am = (android.media.AudioManager) c.getSystemService(Context.AUDIO_SERVICE);
            if (am == null) return;
            int max = am.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC);
            int limit = volumeLimit(c);
            if (limit >= 0) max = Math.min(max, limit);
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

    /** "Maximum volume" setting, or -1 when there is no limit. */
    static int volumeLimit(Context c) {
        try {
            String v = pref(c, "flutter.amadi_max_volume", "");
            if (v == null || v.trim().isEmpty()) return -1;
            return Math.max(0, Integer.parseInt(v.trim()));
        } catch (Throwable t) {
            return -1;
        }
    }

    /** Pulls the volume back down if a guest turned it above the limit. */
    static void enforceVolumeLimit(Context c) {
        try {
            int limit = volumeLimit(c);
            if (limit < 0) return;
            android.media.AudioManager am = (android.media.AudioManager) c.getSystemService(Context.AUDIO_SERVICE);
            if (am == null) return;
            if (am.getStreamVolume(android.media.AudioManager.STREAM_MUSIC) > limit) {
                am.setStreamVolume(android.media.AudioManager.STREAM_MUSIC, limit, 0);
            }
        } catch (Throwable ignored) {}
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
            @Override public void onReceive(Context c, Intent i) { applyStartVolume(c); }
        };
        registerReceiver(screenOn, new android.content.IntentFilter(Intent.ACTION_SCREEN_ON));
        // Volume limit: Android announces every volume change; cap it straight away.
        volumeChanged = new android.content.BroadcastReceiver() {
            @Override public void onReceive(Context c, Intent i) { enforceVolumeLimit(c); }
        };
        registerReceiver(volumeChanged, new android.content.IntentFilter("android.media.VOLUME_CHANGED_ACTION"));
        // Backup in case this TV doesn't send that announcement: watch the volume settings too.
        volumeObserver = new android.database.ContentObserver(new android.os.Handler(android.os.Looper.getMainLooper())) {
            @Override public void onChange(boolean selfChange) { enforceVolumeLimit(AmadiWifiService.this); }
        };
        try {
            getContentResolver().registerContentObserver(android.provider.Settings.System.CONTENT_URI, true, volumeObserver);
        } catch (Throwable ignored) {}
        enforceVolumeLimit(this);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        if (screenOn != null) try { unregisterReceiver(screenOn); } catch (Throwable ignored) {}
        if (volumeChanged != null) try { unregisterReceiver(volumeChanged); } catch (Throwable ignored) {}
        if (volumeObserver != null) try { getContentResolver().unregisterContentObserver(volumeObserver); } catch (Throwable ignored) {}
        if (lock != null && lock.isHeld()) lock.release();
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }
}
