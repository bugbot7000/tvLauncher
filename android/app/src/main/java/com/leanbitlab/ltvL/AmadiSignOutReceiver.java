/*
 * Amadi additions to Arc Launcher (GPL-3.0-or-later).
 * Fires daily at 11:30 to sign guests out of the streaming apps.
 */
package com.omeda.arc;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class AmadiSignOutReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        final PendingResult pending = goAsync();
        final Context app = context.getApplicationContext();
        new Thread(() -> {
            try {
                AmadiDeviceOwner.signOutAll(app);
                AmadiDeviceOwner.scheduleDailySignOut(app);
            } finally {
                pending.finish();
            }
        }).start();
    }
}
