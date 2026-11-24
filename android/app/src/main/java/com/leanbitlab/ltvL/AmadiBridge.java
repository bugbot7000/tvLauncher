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
                        activity.runOnUiThread(() -> result.success(true));
                    }).start();
                    break;
                case "setSettingsHidden": {
                    Boolean hidden = call.argument("hidden");
                    final boolean h = hidden != null && hidden;
                    new Thread(() -> {
                        try { AmadiDeviceOwner.setSettingsHidden(activity, h); } catch (Exception ignored) {}
                        activity.runOnUiThread(() -> result.success(true));
                    }).start();
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
                wm.disconnect();
                wm.enableNetwork(id, true);
                wm.reconnect();
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
