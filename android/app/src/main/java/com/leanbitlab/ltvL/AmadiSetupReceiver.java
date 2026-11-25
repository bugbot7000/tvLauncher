/*
 * Amadi additions to Arc Launcher (GPL-3.0-or-later).
 * Lets the setup script set the room number and start the app installer:
 *   am broadcast -f 32 -n in.amadi.tvlauncher/com.omeda.arc.AmadiSetupReceiver --es room 207 --ez setup true
 * Protected by the DUMP permission, which only the ADB shell (not apps) holds.
 */
package com.omeda.arc;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;

public class AmadiSetupReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        // Same file and key prefix the Flutter shared_preferences plugin uses.
        SharedPreferences p = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);
        SharedPreferences.Editor e = p.edit();
        String room = intent.getStringExtra("room");
        if (room != null && !room.trim().isEmpty()) e.putString("flutter.amadi_room", room.trim());
        String zoom = intent.getStringExtra("zoom");
        if (zoom != null && !zoom.trim().isEmpty()) e.putString("flutter.amadi_ui_zoom", zoom.trim());
        if (intent.getBooleanExtra("setup", false)) e.putString("flutter.amadi_run_setup", "1");
        e.commit();
        setResultData("ok");
    }
}
