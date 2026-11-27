/*
 * Amadi additions to Arc Launcher (GPL-3.0-or-later).
 * Our own volume bar for when a maximum volume is set: the remote's volume
 * buttons are handled here (in every app, via accessibility key filtering) and
 * the bar is drawn so the cap is a full bar, instead of the TV's popup showing
 * the cap partway along. With no cap, or the setting off, the TV handles the
 * buttons as normal.
 */
package com.omeda.arc;

import android.accessibilityservice.AccessibilityService;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.PixelFormat;
import android.graphics.RectF;
import android.media.AudioManager;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;
import android.view.accessibility.AccessibilityEvent;

public class AmadiVolumeService extends AccessibilityService {
    public static final String COMPONENT = "in.amadi.tvlauncher/com.omeda.arc.AmadiVolumeService";

    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable hide = this::hideBar;
    private BarView bar;
    private boolean shown;

    /** Off when staff turn off "Amadi volume bar" in hotel settings. */
    @SuppressWarnings("deprecation")
    static boolean enabled(Context c) {
        android.content.SharedPreferences p = c.getSharedPreferences("FlutterSharedPreferences",
                Context.MODE_PRIVATE | Context.MODE_MULTI_PROCESS);
        return p.getBoolean("flutter.amadi_own_volume_bar", true);
    }

    @Override
    protected boolean onKeyEvent(KeyEvent event) {
        int code = event.getKeyCode();
        if (code != KeyEvent.KEYCODE_VOLUME_UP && code != KeyEvent.KEYCODE_VOLUME_DOWN) return false;
        int limit = AmadiWifiService.volumeLimit(this);
        if (limit <= 0 || !enabled(this)) return false; // no cap: the TV does it as usual
        AudioManager am = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
        if (am == null) return false;
        if (event.getAction() == KeyEvent.ACTION_DOWN) {
            int now = Math.min(am.getStreamVolume(AudioManager.STREAM_MUSIC), limit);
            int next = code == KeyEvent.KEYCODE_VOLUME_UP ? now + 1 : now - 1;
            next = Math.max(0, Math.min(limit, next));
            // Flag 0: no system volume popup; we draw our own.
            am.setStreamVolume(AudioManager.STREAM_MUSIC, next, 0);
            showBar(next, limit);
        }
        return true; // key down and key up are both ours
    }

    private void showBar(int level, int limit) {
        try {
            WindowManager wm = (WindowManager) getSystemService(Context.WINDOW_SERVICE);
            if (bar == null) bar = new BarView(this);
            bar.set(level, limit);
            if (!shown && wm != null) {
                float d = getResources().getDisplayMetrics().density;
                WindowManager.LayoutParams lp = new WindowManager.LayoutParams(
                        (int) (360 * d), (int) (64 * d),
                        WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                                | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                                | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                        PixelFormat.TRANSLUCENT);
                lp.gravity = Gravity.TOP | Gravity.CENTER_HORIZONTAL;
                lp.y = (int) (40 * d);
                wm.addView(bar, lp);
                shown = true;
            }
            handler.removeCallbacks(hide);
            handler.postDelayed(hide, 2500);
        } catch (Throwable ignored) {}
    }

    private void hideBar() {
        if (!shown || bar == null) return;
        try {
            ((WindowManager) getSystemService(Context.WINDOW_SERVICE)).removeView(bar);
        } catch (Throwable ignored) {}
        shown = false;
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {}

    @Override
    public void onInterrupt() {}

    @Override
    public void onDestroy() {
        handler.removeCallbacks(hide);
        hideBar();
        super.onDestroy();
    }

    /** Dark rounded panel: speaker mark, bar filled level/limit, and 0–100 number. */
    static final class BarView extends View {
        private final Paint bg = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint track = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint text = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final RectF r = new RectF();
        private int level, limit = 1;

        BarView(Context c) {
            super(c);
            bg.setColor(Color.argb(220, 4, 52, 44)); // Amadi teal
            track.setColor(Color.argb(70, 255, 255, 255));
            fill.setColor(Color.rgb(159, 225, 203)); // mint
            text.setColor(Color.WHITE);
            text.setTextAlign(Paint.Align.CENTER);
            text.setFakeBoldText(true);
        }

        void set(int level, int limit) {
            this.level = level;
            this.limit = Math.max(1, limit);
            invalidate();
        }

        @Override
        protected void onDraw(Canvas c) {
            float w = getWidth(), h = getHeight(), d = getResources().getDisplayMetrics().density;
            r.set(0, 0, w, h);
            c.drawRoundRect(r, h / 2, h / 2, bg);
            float pct = level / (float) limit;
            // Speaker: a small box and a triangle.
            float sx = 22 * d, cy = h / 2;
            c.drawRect(sx, cy - 6 * d, sx + 7 * d, cy + 6 * d, text);
            android.graphics.Path p = new android.graphics.Path();
            p.moveTo(sx + 7 * d, cy - 6 * d);
            p.lineTo(sx + 17 * d, cy - 13 * d);
            p.lineTo(sx + 17 * d, cy + 13 * d);
            p.lineTo(sx + 7 * d, cy + 6 * d);
            p.close();
            c.drawPath(p, text);
            float left = 56 * d, right = w - 64 * d, bh = 8 * d;
            r.set(left, cy - bh / 2, right, cy + bh / 2);
            c.drawRoundRect(r, bh / 2, bh / 2, track);
            r.set(left, cy - bh / 2, left + (right - left) * pct, cy + bh / 2);
            if (pct > 0) c.drawRoundRect(r, bh / 2, bh / 2, fill);
            text.setTextSize(20 * d);
            c.drawText(String.valueOf(Math.round(pct * 100)), w - 34 * d, cy + 7 * d, text);
        }
    }
}
