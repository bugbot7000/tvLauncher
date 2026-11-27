/*
 * Amadi additions to Arc Launcher (GPL-3.0-or-later).
 * Screen-on events for the welcome screen and default Wi-Fi joining.
 */
package com.omeda.arc;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.wifi.WifiConfiguration;
import android.net.wifi.WifiManager;
import android.net.wifi.WifiNetworkSuggestion;
import android.os.Build;

import java.util.ArrayList;
import java.util.List;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;

public final class AmadiBridge {
    private static final String CHANNEL = "amadi/bridge";
    private static BroadcastReceiver screenReceiver;
    private static WifiManager.WifiLock wifiLock;

    private AmadiBridge() {}

    @SuppressLint({"UnspecifiedRegisterReceiverFlag", "WrongConstant"})
    public static void attach(Activity activity, BinaryMessenger messenger) {
        MethodChannel channel = new MethodChannel(messenger, CHANNEL);
        new Thread(() -> AmadiDeviceOwner.onWake(activity.getApplicationContext())).start();
        channel.setMethodCallHandler((call, result) -> {
            switch (call.method) {
                case "connectWifi": {
                    String ssid = call.argument("ssid");
                    String password = call.argument("password");
                    result.success(connectWifi(activity, ssid, password));
                    break;
                }
                case "ensureWifi": {
                    final String ssid = call.argument("ssid");
                    final String pass = call.argument("password");
                    final String fbSsid = call.argument("fallbackSsid");
                    final String fbPass = call.argument("fallbackPassword");
                    new Thread(() -> {
                        String r = ensureWifi(activity.getApplicationContext(), ssid, pass, fbSsid, fbPass);
                        activity.runOnUiThread(() -> result.success(r));
                    }).start();
                    break;
                }
                case "wifiEnabled": {
                    WifiManager wm = (WifiManager) activity.getApplicationContext().getSystemService(Context.WIFI_SERVICE);
                    result.success(wm != null && wm.isWifiEnabled());
                    break;
                }
                case "ownerStatus": {
                    java.util.HashMap<String, Object> m = new java.util.HashMap<>();
                    m.put("owner", AmadiDeviceOwner.isOwner(activity));
                    m.put("lastSignOut", AmadiDeviceOwner.lastSignOut(activity));
                    m.put("adbOk", AmadiSelfAdb.lastOk());
                    m.put("adbError", AmadiSelfAdb.lastError());
                    result.success(m);
                    break;
                }
                case "signOutNow":
                    new Thread(() -> {
                        AmadiDeviceOwner.signOutAll(activity);
                        final boolean ok = AmadiDeviceOwner.isOwner(activity) || AmadiSelfAdb.lastOk();
                        activity.runOnUiThread(() -> result.success(ok));
                    }).start();
                    break;
                case "setDeviceName": {
                    String raw = call.argument("name");
                    final String name = raw == null ? "" : raw.replaceAll("[^A-Za-z0-9 ._-]", "").trim();
                    if (name.isEmpty()) {
                        result.success(false);
                        break;
                    }
                    new Thread(() -> {
                        String out = AmadiSelfAdb.shell(activity,
                                "settings put global device_name '" + name + "'; settings put secure bluetooth_name '" + name + "'; "
                                        + hostnameCmd(name));
                        final boolean ok = out != null;
                        activity.runOnUiThread(() -> result.success(ok));
                    }).start();
                    break;
                }
                case "openPackage": {
                    // Enables a disabled app (e.g. the Aptoide store) and opens it.
                    final String pkg = call.argument("package");
                    new Thread(() -> {
                        AmadiSelfAdb.shell(activity, "pm enable " + pkg + "; appops set " + pkg + " REQUEST_INSTALL_PACKAGES allow; settings put secure install_non_market_apps 1");
                        activity.runOnUiThread(() -> {
                            android.content.pm.PackageManager pm = activity.getPackageManager();
                            android.content.Intent i = pm.getLeanbackLaunchIntentForPackage(pkg);
                            if (i == null) i = pm.getLaunchIntentForPackage(pkg);
                            if (i == null) { result.success(false); return; }
                            i.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK);
                            activity.startActivity(i);
                            result.success(true);
                        });
                    }).start();
                    break;
                }
                case "installedVersion": {
                    // versionCode of an installed app (as text), or null.
                    String pkg = call.argument("package");
                    try {
                        android.content.pm.PackageInfo pi = activity.getPackageManager().getPackageInfo(pkg, 0);
                        long code = Build.VERSION.SDK_INT >= 28 ? pi.getLongVersionCode() : pi.versionCode;
                        result.success(String.valueOf(code));
                    } catch (Exception e) {
                        result.success(null);
                    }
                    break;
                }
                case "wifiHighPerf": {
                    // Keeps Wi-Fi out of power-save while the installer downloads.
                    Boolean on = call.argument("on");
                    WifiManager wm = (WifiManager) activity.getApplicationContext().getSystemService(Context.WIFI_SERVICE);
                    if (wm != null) {
                        if (wifiLock == null) wifiLock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "amadi-install");
                        if (on != null && on && !wifiLock.isHeld()) wifiLock.acquire();
                        if ((on == null || !on) && wifiLock.isHeld()) wifiLock.release();
                    }
                    result.success(true);
                    break;
                }
                case "volumeInfo": {
                    android.media.AudioManager am = (android.media.AudioManager) activity.getSystemService(Context.AUDIO_SERVICE);
                    java.util.HashMap<String, Object> m = new java.util.HashMap<>();
                    m.put("max", am == null ? 0 : am.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC));
                    m.put("now", am == null ? 0 : am.getStreamVolume(android.media.AudioManager.STREAM_MUSIC));
                    result.success(m);
                    break;
                }
                case "networkInfo": {
                    new Thread(() -> {
                        java.util.HashMap<String, Object> m = networkInfo(activity.getApplicationContext());
                        activity.runOnUiThread(() -> result.success(m));
                    }).start();
                    break;
                }
                case "applyVolumeLimit":
                    AmadiWifiService.enforceVolumeLimit(activity.getApplicationContext());
                    result.success(true);
                    break;
                case "sleepNow": {
                    // Standby, like the power button. KEYCODE_SLEEP only ever turns the screen off.
                    new Thread(() -> {
                        AmadiSelfAdb.shell(activity, "input keyevent KEYCODE_SLEEP");
                        activity.runOnUiThread(() -> result.success(true));
                    }).start();
                    break;
                }
                case "installApks": {
                    // Installs one app from its downloaded APK files (base + splits)
                    // through the TV's own ADB. Returns "ok" or the error text.
                    final java.util.List<String> paths = call.argument("paths");
                    new Thread(() -> {
                        String r = installApks(activity.getApplicationContext(), paths);
                        activity.runOnUiThread(() -> result.success(r));
                    }).start();
                    break;
                }
                case "setSettingsHidden": {
                    Boolean hidden = call.argument("hidden");
                    final boolean h = hidden != null && hidden;
                    new Thread(() -> {
                        try { AmadiDeviceOwner.setSettingsHidden(activity, h); } catch (Exception ignored) {}
                        activity.runOnUiThread(() -> result.success(true));
                    }).start();
                    break;
                }
                case "welcomeShownThisBoot": {
                    // The welcome shows once per power-on (and again on screen-on), not when
                    // the launcher is reopened after an app.
                    int boot = android.provider.Settings.Global.getInt(activity.getContentResolver(), "boot_count", -1);
                    int shown = activity.getSharedPreferences("amadi_welcome", Context.MODE_PRIVATE).getInt("boot", -2);
                    result.success(boot >= 0 && boot == shown);
                    break;
                }
                case "markWelcomeShown": {
                    int boot = android.provider.Settings.Global.getInt(activity.getContentResolver(), "boot_count", -1);
                    activity.getSharedPreferences("amadi_welcome", Context.MODE_PRIVATE).edit().putInt("boot", boot).apply();
                    result.success(true);
                    break;
                }
                case "removeOwner":
                    result.success(AmadiDeviceOwner.removeOwner(activity));
                    break;
                default:
                    result.notImplemented();
            }
        });

        if (screenReceiver != null) {
            try { activity.getApplicationContext().unregisterReceiver(screenReceiver); } catch (Exception ignored) {}
        }
        screenReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                if (Intent.ACTION_SCREEN_ON.equals(intent.getAction())) {
                    final Context app = context.getApplicationContext();
                    new Thread(() -> AmadiDeviceOwner.onWake(app)).start();
                    try { channel.invokeMethod("screenOn", null); } catch (Exception ignored) {}
                }
            }
        };
        IntentFilter filter = new IntentFilter(Intent.ACTION_SCREEN_ON);
        if (Build.VERSION.SDK_INT >= 33) {
            activity.getApplicationContext().registerReceiver(screenReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            activity.getApplicationContext().registerReceiver(screenReceiver, filter);
        }
    }

    /** SSID the TV is on now, read through the TV's own ADB (apps can't see it without location access). */
    static String currentSsid(Context c) {
        String out = AmadiSelfAdb.shell(c, "dumpsys wifi | grep mWifiInfo");
        if (out == null) return "";
        int i = out.indexOf("SSID: ");
        if (i < 0) return "";
        int j = out.indexOf(", BSSID", i);
        String s = j > i ? out.substring(i + 6, j) : "";
        return s.replace("\"", "").trim();
    }

    /** Connected network, IP and MAC addresses, read through the TV's own ADB. */
    static java.util.HashMap<String, Object> networkInfo(Context c) {
        java.util.HashMap<String, Object> m = new java.util.HashMap<>();
        String out = AmadiSelfAdb.shell(c,
                "echo WMAC $(cat /sys/class/net/wlan0/address 2>/dev/null); "
                        + "echo EMAC $(cat /sys/class/net/eth0/address 2>/dev/null); "
                        + "echo WIP $(ip -4 -o addr show wlan0 2>/dev/null); "
                        + "echo EIP $(ip -4 -o addr show eth0 2>/dev/null); "
                        + "dumpsys wifi | grep mWifiInfo");
        if (out == null) {
            m.put("error", "Could not read (TV debugging connection refused)");
            return m;
        }
        String wifiMac = "", ethMac = "", wifiIp = "", ethIp = "", ssid = "";
        for (String line : out.split("\n")) {
            String l = line.trim();
            if (l.startsWith("WMAC")) wifiMac = l.substring(4).trim();
            else if (l.startsWith("EMAC")) ethMac = l.substring(4).trim();
            else if (l.startsWith("WIP")) wifiIp = ipOf(l);
            else if (l.startsWith("EIP")) ethIp = ipOf(l);
            else if (l.contains("mWifiInfo") && l.contains("SSID: ")) {
                int i = l.indexOf("SSID: ");
                int j = l.indexOf(", BSSID", i);
                if (j > i) ssid = l.substring(i + 6, j).replace("\"", "").trim();
            }
        }
        if (ssid.equals("<unknown ssid>")) ssid = "";
        if (!ethIp.isEmpty()) {
            m.put("type", "Ethernet (cable)");
            m.put("ip", ethIp);
        } else if (!wifiIp.isEmpty()) {
            m.put("type", "Wi-Fi");
            m.put("ip", wifiIp);
        } else {
            m.put("type", "Not connected");
            m.put("ip", "");
        }
        m.put("ssid", ssid);
        m.put("wifiMac", wifiMac);
        m.put("ethMac", ethMac);
        return m;
    }

    /** "WIP 3: wlan0    inet 192.168.2.195/24 brd ..." -> "192.168.2.195". */
    private static String ipOf(String line) {
        java.util.regex.Matcher mm = java.util.regex.Pattern.compile("inet (\\d+\\.\\d+\\.\\d+\\.\\d+)").matcher(line);
        return mm.find() ? mm.group(1) : "";
    }

    static String installApks(Context c, java.util.List<String> paths) {
        if (paths == null || paths.isEmpty()) return "no files";
        long total = 0;
        for (String p : paths) total += new java.io.File(p).length();
        // The first time, the TV shows "Allow debugging?" for the launcher: wait up to 2 min for it.
        String out = null;
        for (int i = 0; i < 24 && out == null; i++) {
            out = AmadiSelfAdb.shell(c, "pm install-create -r -S " + total);
            if (out == null) { try { Thread.sleep(5000); } catch (InterruptedException ignored) {} }
        }
        if (out == null) return "TV debugging connection refused: " + AmadiSelfAdb.lastError();
        java.util.regex.Matcher m = java.util.regex.Pattern.compile("\\[(\\d+)\\]").matcher(out);
        if (!m.find()) return out.trim();
        String session = m.group(1);
        int i = 0;
        for (String p : paths) {
            java.io.File f = new java.io.File(p);
            // The system installer may not read the launcher's own storage (SELinux), so the
            // shell copies each file to /data/local/tmp first, like a normal adb install.
            String tmp = "/data/local/tmp/amadi_" + i + ".apk";
            String w = AmadiSelfAdb.shell(c, "cp '" + p + "' " + tmp + " && pm install-write -S " + f.length()
                    + " " + session + " " + (i++) + "_" + f.getName() + " " + tmp + "; rm -f " + tmp);
            if (w == null || !w.contains("Success")) {
                AmadiSelfAdb.shell(c, "pm install-abandon " + session);
                return "write failed: " + (w == null ? AmadiSelfAdb.lastError() : w.trim());
            }
        }
        String done = AmadiSelfAdb.shell(c, "pm install-commit " + session);
        if (done == null) return "commit failed: " + AmadiSelfAdb.lastError();
        return done.contains("Success") ? "ok" : done.trim();
    }

    /** DHCP hostname the router (Omada) shows, e.g. "207-TV". Android 9 sends net.hostname if set. */
    static String hostnameCmd(String name) {
        String h = name.replaceAll("[^A-Za-z0-9-]+", "-").replaceAll("^-+|-+$", "");
        return h.isEmpty() ? "true" : "setprop net.hostname " + h;
    }

    /** Re-applies the hostname after boot (setprop doesn't survive a restart). */
    static void applyHostname(Context c) {
        try {
            String name = android.provider.Settings.Global.getString(c.getContentResolver(), "device_name");
            if (name != null && !name.trim().isEmpty()) AmadiSelfAdb.shell(c, hostnameCmd(name.trim()));
        } catch (Exception ignored) {}
    }

    private static final Object WIFI_LOCK = new Object();

    /** Joins the staff network; if that doesn't work within ~25 s, joins the fallback. */
    static String ensureWifi(Context c, String ssid, String pass, String fbSsid, String fbPass) {
        synchronized (WIFI_LOCK) {
            if (ssid == null || ssid.isEmpty()) return "invalid";
            if (ssid.equals(currentSsid(c))) return "already";
            connectWifi(c, ssid, pass);
            for (int k = 0; k < 10; k++) {
                try { Thread.sleep(2500); } catch (InterruptedException ignored) {}
                if (ssid.equals(currentSsid(c))) return "staff";
            }
            if (fbSsid == null || fbSsid.isEmpty()) return "failed";
            if (fbSsid.equals(currentSsid(c))) return "fallback";
            connectWifi(c, fbSsid, fbPass);
            for (int k = 0; k < 8; k++) {
                try { Thread.sleep(2500); } catch (InterruptedException ignored) {}
                if (fbSsid.equals(currentSsid(c))) return "fallback";
            }
            return "failed";
        }
    }

    /** Returns "connected-request", "suggested", "disabled", "invalid" or "error:<msg>". */
    @SuppressWarnings("deprecation")
    @SuppressLint({"NewApi", "MissingPermission"})
    static String connectWifi(Context context, String ssid, String password) {
        if (ssid == null || ssid.trim().isEmpty()) return "invalid";
        try {
            WifiManager wm = (WifiManager) context.getApplicationContext().getSystemService(Context.WIFI_SERVICE);
            if (wm == null) return "error:no wifi";
            if (!wm.isWifiEnabled()) {
                if (Build.VERSION.SDK_INT < 29) wm.setWifiEnabled(true);
                else return "disabled";
            }
            boolean open = password == null || password.isEmpty();
            if (Build.VERSION.SDK_INT < 29) {
                WifiConfiguration conf = new WifiConfiguration();
                conf.SSID = "\"" + ssid + "\"";
                if (open) {
                    conf.allowedKeyManagement.set(WifiConfiguration.KeyMgmt.NONE);
                } else {
                    conf.preSharedKey = "\"" + password + "\"";
                }
                int id = wm.addNetwork(conf);
                if (id == -1) {
                    for (WifiConfiguration c : wm.getConfiguredNetworks()) {
                        if (conf.SSID.equals(c.SSID)) { id = c.networkId; break; }
                    }
                }
                if (id == -1) return "error:add failed";
                // No disconnect()/reconnect(): reconnect() makes the TV re-pick its
                // strongest saved network and abandon this attempt within 2 s.
                wm.enableNetwork(id, true);
                return "connected-request";
            } else {
                WifiNetworkSuggestion.Builder b = new WifiNetworkSuggestion.Builder().setSsid(ssid);
                if (!open) b.setWpa2Passphrase(password);
                List<WifiNetworkSuggestion> list = new ArrayList<>();
                list.add(b.build());
                wm.removeNetworkSuggestions(list);
                int status = wm.addNetworkSuggestions(list);
                return status == WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS ? "suggested" : "error:suggestion " + status;
            }
        } catch (Exception e) {
            return "error:" + e.getMessage();
        }
    }
}
