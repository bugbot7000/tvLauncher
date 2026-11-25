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
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        if (lock != null && lock.isHeld()) lock.release();
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }
}
