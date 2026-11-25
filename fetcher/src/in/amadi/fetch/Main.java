/*
 * Amadi setup downloader (GPL-3.0-or-later).
 * Tiny app the setup script sends first. It downloads a file (the launcher) from
 * Google Drive to its own folder on /sdcard, resuming after Wi-Fi drops, then writes
 * <name>.done so the script knows it can install it.
 *   am start -n in.amadi.fetch/.Main --es url <url> --es name amadi-launcher.apk
 */
package in.amadi.fetch;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Environment;
import android.view.Gravity;
import android.view.WindowManager;
import android.widget.TextView;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;

public class Main extends Activity {
    private TextView text;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        text = new TextView(this);
        text.setTextColor(Color.WHITE);
        text.setTextSize(26);
        text.setGravity(Gravity.CENTER);
        text.setBackgroundColor(Color.rgb(14, 26, 26));
        setContentView(text);
        final String url = getIntent().getStringExtra("url");
        final String name = getIntent().getStringExtra("name");
        if (url == null || name == null) { show("Nothing to download."); return; }
        new Thread(() -> run(url, name)).start();
    }

    private void show(final String s) { runOnUiThread(() -> text.setText(s)); }

    private void run(String url, String name) {
        // App's own folder (/sdcard/Android/data/in.amadi.fetch/files): no permission needed,
        // and the ADB shell can read it to install.
        File dir = getExternalFilesDir(null);
        if (dir == null) dir = getFilesDir();
        dir.mkdirs();
        File out = new File(dir, name);
        File done = new File(dir, name + ".done");
        done.delete(); // keep any partial file: a restarted download resumes it
        // Keep Wi-Fi out of power-save while downloading (power-save causes drops on these TVs).
        android.net.wifi.WifiManager wm = (android.net.wifi.WifiManager) getApplicationContext().getSystemService(WIFI_SERVICE);
        android.net.wifi.WifiManager.WifiLock lock = wm == null ? null
                : wm.createWifiLock(android.net.wifi.WifiManager.WIFI_MODE_FULL_HIGH_PERF, "amadi-fetch");
        if (lock != null) lock.acquire();
        // Retry until done: a TV left overnight finishes whenever the Wi-Fi lets it.
        for (int attempt = 1; ; attempt++) {
            try {
                if (download(url, out)) {
                    new FileOutputStream(done).close();
                    if (lock != null) lock.release();
                    show("Setting up Amadi TV…\nInstalling");
                    return;
                }
            } catch (Throwable t) {
                android.util.Log.w("AmadiFetch", "attempt " + attempt, t);
                show("Setting up Amadi TV…\nRetrying (" + attempt + ")\n\n" + t.getClass().getSimpleName() + ": " + t.getMessage());
            }
            try { Thread.sleep(Math.min(3000L * attempt, 15000L)); } catch (InterruptedException ignored) {}
        }
    }

    /** Returns true when the whole file is on disk. Resumes from what is already there. */
    private boolean download(String url, File out) throws Exception {
        long have = out.exists() ? out.length() : 0;
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        c.setConnectTimeout(20000);
        c.setReadTimeout(30000);
        c.setInstanceFollowRedirects(true);
        if (have > 0) c.setRequestProperty("Range", "bytes=" + have + "-");
        int code = c.getResponseCode();
        if (code == 416) return true;
        boolean resumed = code == 206;
        if (code != 200 && !resumed) throw new Exception("HTTP " + code);
        String type = c.getContentType();
        if (type != null && type.startsWith("text/html")) throw new Exception("Got a web page, not the file");
        long start = resumed ? have : 0;
        long len = c.getContentLengthLong();
        long total = len < 0 ? -1 : len + start;
        long got = start;
        try (InputStream in = c.getInputStream(); FileOutputStream fo = new FileOutputStream(out, resumed)) {
            byte[] buf = new byte[64 * 1024];
            int n;
            long lastShow = 0;
            while ((n = in.read(buf)) > 0) {
                fo.write(buf, 0, n);
                got += n;
                long now = System.currentTimeMillis();
                if (total > 0 && now - lastShow > 500) {
                    lastShow = now;
                    show("Setting up Amadi TV…\nDownloading " + (got * 100 / total) + "%");
                }
            }
        } finally {
            c.disconnect();
        }
        return total < 0 || got >= total;
    }
}
