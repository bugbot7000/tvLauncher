/*
 * Amadi additions to Arc Launcher (GPL-3.0-or-later).
 * Talks to the TV's own ADB over the local network port so the launcher can run
 * shell commands it has no Android permission for (clearing app data, hiding the
 * settings app). The TV asks "Allow debugging?" once; tick "Always allow".
 */
package com.omeda.arc;

import android.content.Context;
import android.util.Log;

import java.io.File;

import dadb.AdbKeyPair;
import dadb.AdbShellResponse;
import dadb.Dadb;

public final class AmadiSelfAdb {
    private static final String TAG = "AmadiSelfAdb";
    private static final Object LOCK = new Object();
    private static volatile String lastError = "";
    private static volatile boolean lastOk = false;

    private AmadiSelfAdb() {}

    public static String lastError() { return lastError; }
    public static boolean lastOk() { return lastOk; }

    private static AdbKeyPair keys(Context c) throws Exception {
        File dir = new File(c.getFilesDir(), "adbkey");
        if (!dir.exists()) dir.mkdirs();
        File priv = new File(dir, "adbkey");
        File pub = new File(dir, "adbkey.pub");
        if (!priv.exists() || !pub.exists()) {
            AdbKeyPair.Companion.generate(priv, pub);
        }
        return AdbKeyPair.Companion.read(priv, pub);
    }

    /** Runs one shell command on this TV. Blocking; call off the main thread. */
    public static String shell(Context c, String command) {
        synchronized (LOCK) {
            Dadb dadb = null;
            try {
                dadb = Dadb.Companion.create("127.0.0.1", 5555, keys(c.getApplicationContext()));
                AdbShellResponse r = dadb.shell(command);
                lastOk = true;
                lastError = "";
                return r.getAllOutput();
            } catch (Throwable t) {
                lastOk = false;
                lastError = String.valueOf(t.getMessage());
                Log.w(TAG, "shell failed: " + command, t);
                return null;
            } finally {
                if (dadb != null) {
                    try { dadb.close(); } catch (Throwable ignored) {}
                }
            }
        }
    }

    public static void shellAsync(Context c, String command) {
        final Context app = c.getApplicationContext();
        new Thread(() -> shell(app, command)).start();
    }
}
