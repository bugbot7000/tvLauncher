/*
 * Amadi additions to Arc Launcher (GPL-3.0-or-later).
 * Device admin receiver so the launcher can be set as device owner over ADB:
 *   adb shell dpm set-device-owner in.amadi.tvlauncher/com.omeda.arc.AmadiAdminReceiver
 */
package com.omeda.arc;

import android.app.admin.DeviceAdminReceiver;

public class AmadiAdminReceiver extends DeviceAdminReceiver {
}
