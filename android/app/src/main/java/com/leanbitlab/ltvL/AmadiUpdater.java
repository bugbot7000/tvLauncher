/*
 * Amadi additions to Arc Launcher (GPL-3.0-or-later).
 * Automatic launcher updates. The TV reads amadi-release.json from the repo's
 * amadi branch; when it names a newer build than the one installed, the TV
 * downloads that APK from the GitHub release, checks its SHA-256, and installs
 * it through its own ADB connection. Only builds tested and marked released in
 * that file are installed. To avoid interrupting a guest, the install happens
 * when the screen is off or between 3 and 5 AM (or right away from settings).
 */
package com.omeda.arc;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.PowerManager;

import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;
import java.util.Calendar;

public final class AmadiUpdater {
    private static final String RELEASE_URL =
            "https://raw.githubusercontent.com/bugbot7000/tvLauncher/amadi/amadi-release.json";
    private static final Object LOCK = new Object();

    private AmadiUpdater() {}

    private static SharedPreferences prefs(Context c) {
        return c.getSharedPreferences("amadi_update", Context.MODE_PRIVATE | Context.MODE_MULTI_PROCESS);
    }

    /** Build number of the installed launcher ("amadi-60" -> 60), or 0 if unknown. */
    public static int installedBuild(Context c) {
        try {
            String v = c.getPackageManager().getPackageInfo(c.getPackageName(), 0).versionName;
            return Integer.parseInt(v.replaceAll("\\D+", ""));
        } catch (Exception e) {
            return 0;
        }
    }

    /** For the settings page: installed build, latest released build, last result. */
    public static java.util.HashMap<String, Object> status(Context c) {
        SharedPreferences p = prefs(c);
        java.util.HashMap<String, Object> m = new java.util.HashMap<>();
        m.put("installed", installedBuild(c));
        m.put("latest", p.getInt("latest", 0));
        m.put("lastCheck", p.getLong("lastCheck", 0));
        m.put("result", p.getString("result", ""));
        return m;
    }

    public static void checkAsync(Context c, boolean installNow) {
        final Context app = c.getApplicationContext();
        new Thread(() -> check(app, installNow), "amadi-update").start();
    }

    /** Returns a short result line (also saved for the settings page). */
    public static String check(Context c, boolean installNow) {
        synchronized (LOCK) {
            String r;
            try {
                r = run(c, installNow);
            } catch (Throwable t) {
                r = "Check failed: " + t.getMessage();
            }
            prefs(c).edit().putLong("lastCheck", System.currentTimeMillis()).putString("result", r).commit();
            return r;
        }
    }

    private static String run(Context c, boolean installNow) throws Exception {
        JSONObject rel = new JSONObject(readText(RELEASE_URL + "?t=" + System.currentTimeMillis()));
        int latest = rel.getInt("build");
        String url = rel.getString("url");
        String sha = rel.optString("sha256", "").toLowerCase();
        prefs(c).edit().putInt("latest", latest).commit();
        int installed = installedBuild(c);
        if (latest <= installed) return "Up to date (build " + installed + ")";

        File dir = c.getExternalFilesDir(null);
        if (dir == null) dir = c.getFilesDir();
        File apk = new File(dir, "amadi-update-" + latest + ".apk");
        if (!apk.exists() || (!sha.isEmpty() && !sha.equals(sha256(apk)))) {
            // Clear older downloads first: the TVs have little free space.
            File[] old = dir.listFiles((d, n) -> n.startsWith("amadi-update-"));
            if (old != null) for (File f : old) f.delete();
            download(url, apk);
            if (!sha.isEmpty() && !sha.equals(sha256(apk))) {
                apk.delete();
                return "Build " + latest + " download was damaged; will retry";
            }
        }
        if (!installNow && !quietTime(c)) return "Build " + latest + " ready; installs when the TV is off";

        // Installing replaces this app and stops it, so the install runs on its own in the TV's shell.
        String tmp = "/data/local/tmp/amadi_update.apk";
        String out = AmadiSelfAdb.shell(c, "cp '" + apk.getAbsolutePath() + "' " + tmp
                + " && (nohup sh -c 'pm install -r " + tmp + "; rm -f " + tmp + "' >/dev/null 2>&1 &) && echo started");
        if (out == null || !out.contains("started")) {
            return "Install of build " + latest + " couldn't start: " + (out == null ? AmadiSelfAdb.lastError() : out.trim());
        }
        return "Installing build " + latest;
    }

    /** Screen off, or between 3 and 5 AM. */
    private static boolean quietTime(Context c) {
        PowerManager pm = (PowerManager) c.getSystemService(Context.POWER_SERVICE);
        if (pm != null && !pm.isInteractive()) return true;
        int h = Calendar.getInstance().get(Calendar.HOUR_OF_DAY);
        return h >= 3 && h < 5;
    }

    private static HttpURLConnection open(String url) throws Exception {
        HttpURLConnection con = (HttpURLConnection) new URL(url).openConnection();
        con.setConnectTimeout(20000);
        con.setReadTimeout(60000);
        con.setInstanceFollowRedirects(true);
        con.setRequestProperty("User-Agent", "AmadiTV");
        return con;
    }

    private static String readText(String url) throws Exception {
        HttpURLConnection con = open(url);
        try {
            if (con.getResponseCode() != 200) throw new Exception("HTTP " + con.getResponseCode());
            try (InputStream in = con.getInputStream()) {
                java.io.ByteArrayOutputStream b = new java.io.ByteArrayOutputStream();
                byte[] buf = new byte[8192];
                int n;
                while ((n = in.read(buf)) > 0) b.write(buf, 0, n);
                return b.toString("UTF-8");
            }
        } finally {
            con.disconnect();
        }
    }

    private static void download(String url, File to) throws Exception {
        HttpURLConnection con = open(url);
        try {
            if (con.getResponseCode() != 200) throw new Exception("download HTTP " + con.getResponseCode());
            File part = new File(to.getPath() + ".part");
            try (InputStream in = con.getInputStream(); FileOutputStream out = new FileOutputStream(part)) {
                byte[] buf = new byte[65536];
                int n;
                while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            }
            if (!part.renameTo(to)) throw new Exception("couldn't save download");
        } finally {
            con.disconnect();
        }
    }

    private static String sha256(File f) throws Exception {
        MessageDigest md = MessageDigest.getInstance("SHA-256");
        try (InputStream in = new FileInputStream(f)) {
            byte[] buf = new byte[65536];
            int n;
            while ((n = in.read(buf)) > 0) md.update(buf, 0, n);
        }
        StringBuilder sb = new StringBuilder();
        for (byte b : md.digest()) sb.append(String.format("%02x", b));
        return sb.toString();
    }
}
