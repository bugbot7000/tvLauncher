/*
 * Amadi additions to Arc Launcher (GPL-3.0-or-later).
 * Device-owner powers: daily sign-out of streaming apps, permanent home screen,
 * Wi-Fi lock to the staff network, hiding the Android settings app from guests.
 */
package com.omeda.arc;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.AlarmManager;
import android.app.PendingIntent;
import android.app.admin.DevicePolicyManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.net.wifi.WifiConfiguration;
import android.net.wifi.WifiManager;
import android.os.Build;

import java.util.Calendar;
import java.util.List;
import java.util.concurrent.Executors;

public final class AmadiDeviceOwner {
    public static final String[] STREAMING_APPS = {
            "com.google.android.youtube.tv",
            "com.amazon.amazonvideo.livingroom",
            "in.startv.hotstar",
    };
    public static final String TV_SETTINGS = "com.android.tv.settings";
    private static final String PREFS = "amadi_owner";
    private static final String KEY_LAST_SIGNOUT = "last_signout";
    public static final String STAFF_SSID = "Amadi_Staff";
    private static final long DAY_MS = 24L * 60 * 60 * 1000;

    private AmadiDeviceOwner() {}

    static ComponentName admin(Context c) {
        return new ComponentName(c, AmadiAdminReceiver.class);
    }

    static DevicePolicyManager dpm(Context c) {
        return (DevicePolicyManager) c.getSystemService(Context.DEVICE_POLICY_SERVICE);
    }

    public static boolean isOwner(Context c) {
        DevicePolicyManager d = dpm(c);
        return d != null && d.isDeviceOwnerApp(c.getPackageName());
    }

    /** Runs at launcher start, boot and screen-on. Safe to call often. */
    public static void onWake(Context c) {
        // Sign-out now follows guest changes (handled in the launcher), so cancel
        // the old daily 11:30 alarm if one is still scheduled.
        try { cancelDailySignOut(c); } catch (Exception ignored) {}
        AmadiBridge.applyHostname(c);
        if (!isOwner(c)) {
            try { setSettingsHidden(c, true); } catch (Exception ignored) {}
            return;
        }
        try { grantSelf(c); } catch (Exception ignored) {}
        try { lockHome(c); } catch (Exception ignored) {}
        try { setSettingsHidden(c, true); } catch (Exception ignored) {}
        try { lockWifi(c); } catch (Exception ignored) {}
    }

    static void cancelDailySignOut(Context c) {
        AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
        if (am == null) return;
        Intent i = new Intent(c, AmadiSignOutReceiver.class);
        PendingIntent pi = PendingIntent.getBroadcast(c, 1130, i,
                PendingIntent.FLAG_NO_CREATE | (Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0));
        if (pi != null) {
            am.cancel(pi);
            pi.cancel();
        }
    }

    static void grantSelf(Context c) {
        DevicePolicyManager d = dpm(c);
        d.setPermissionGrantState(admin(c), c.getPackageName(), Manifest.permission.ACCESS_FINE_LOCATION,
                DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED);
        d.setPermissionGrantState(admin(c), c.getPackageName(), Manifest.permission.ACCESS_COARSE_LOCATION,
                DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED);
    }

    @SuppressLint("NewApi")
    static void lockHome(Context c) {
        IntentFilter f = new IntentFilter(Intent.ACTION_MAIN);
        f.addCategory(Intent.CATEGORY_HOME);
        f.addCategory(Intent.CATEGORY_DEFAULT);
        dpm(c).addPersistentPreferredActivity(admin(c), f, new ComponentName(c, MainActivity.class));
    }

    public static void setSettingsHidden(Context c, boolean hidden) {
        if (isOwner(c)) {
            dpm(c).setApplicationHidden(admin(c), TV_SETTINGS, hidden);
        } else {
            AmadiSelfAdb.shell(c, hidden ? "pm disable-user --user 0 " + TV_SETTINGS : "pm enable " + TV_SETTINGS);
        }
    }

    /** Forgets every saved network except the staff network and connects to it. */
    @SuppressLint("MissingPermission")
    @SuppressWarnings("deprecation")
    static void lockWifi(Context c) {
        WifiManager wm = (WifiManager) c.getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        if (wm == null) return;
        if (!wm.isWifiEnabled()) wm.setWifiEnabled(true);
        List<WifiConfiguration> list = wm.getConfiguredNetworks();
        if (list == null) return;
        int staffId = -1;
        for (WifiConfiguration w : list) {
            if (("\"" + STAFF_SSID + "\"").equals(w.SSID)) staffId = w.networkId;
        }
        if (staffId == -1) return; // never remove networks if the staff one is missing
        for (WifiConfiguration w : list) {
            if (w.networkId != staffId) wm.removeNetwork(w.networkId);
        }
        wm.saveConfiguration();
        if (wm.getConnectionInfo() == null || wm.getConnectionInfo().getNetworkId() != staffId) {
            wm.enableNetwork(staffId, true);
            wm.reconnect();
        }
    }

    @SuppressLint("NewApi")
    public static void signOutAll(Context c) {
        if (!isOwner(c)) {
            StringBuilder cmd = new StringBuilder();
            for (String p : STREAMING_APPS) {
                if (cmd.length() > 0) cmd.append("; ");
                cmd.append("pm clear ").append(p);
            }
            String out = AmadiSelfAdb.shell(c, cmd.toString());
            if (out != null) prefs(c).edit().putLong(KEY_LAST_SIGNOUT, System.currentTimeMillis()).apply();
            return;
        }
        if (Build.VERSION.SDK_INT < 28) return;
        DevicePolicyManager d = dpm(c);
        for (String p : STREAMING_APPS) {
            try {
                d.clearApplicationUserData(admin(c), p, Executors.newSingleThreadExecutor(), (pkg, ok) -> {});
            } catch (Exception ignored) {
            }
        }
        prefs(c).edit().putLong(KEY_LAST_SIGNOUT, System.currentTimeMillis()).apply();
    }

    public static long lastSignOut(Context c) {
        return prefs(c).getLong(KEY_LAST_SIGNOUT, 0);
    }

    /** If the TV was off at 11:30, sign out once it is on and 24 hours have passed. */
    static void signOutIfOverdue(Context c) {
        long last = lastSignOut(c);
        long now = System.currentTimeMillis();
        // The TV clock starts in 2021 until it syncs; skip until the time looks real.
        if (now < 1767225600000L) return; // 1 Jan 2026
        if (last == 0) {
            prefs(c).edit().putLong(KEY_LAST_SIGNOUT, now).apply();
            return;
        }
        if (now - last >= DAY_MS) signOutAll(c);
    }

    @SuppressLint({"NewApi", "MissingPermission", "ScheduleExactAlarm"})
    static void scheduleDailySignOut(Context c) {
        AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
        if (am == null) return;
        Calendar next = Calendar.getInstance();
        next.set(Calendar.HOUR_OF_DAY, 11);
        next.set(Calendar.MINUTE, 30);
        next.set(Calendar.SECOND, 0);
        next.set(Calendar.MILLISECOND, 0);
        if (next.getTimeInMillis() <= System.currentTimeMillis()) next.add(Calendar.DAY_OF_MONTH, 1);
        Intent i = new Intent(c, AmadiSignOutReceiver.class);
        PendingIntent pi = PendingIntent.getBroadcast(c, 1130, i,
                PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0));
        if (Build.VERSION.SDK_INT >= 23) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.getTimeInMillis(), pi);
        } else {
            am.setExact(AlarmManager.RTC_WAKEUP, next.getTimeInMillis(), pi);
        }
    }

    public static boolean removeOwner(Context c) {
        if (!isOwner(c)) return false;
        try {
            setSettingsHidden(c, false);
            dpm(c).clearPackagePersistentPreferredActivities(admin(c), c.getPackageName());
            dpm(c).clearDeviceOwnerApp(c.getPackageName());
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    static SharedPreferences prefs(Context c) {
        return c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }
}
