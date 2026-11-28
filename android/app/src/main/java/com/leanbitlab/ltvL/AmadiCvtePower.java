/*
 * Amadi additions to Arc Launcher (GPL-3.0-or-later).
 * On CVTE TVs (Onwa): set the factory "Power Mode" to Bootup, so the TV turns
 * itself on whenever mains power comes back (like "Direct" on the MT series).
 *
 * Uses CVTE's own TV API service (com.cvte.tv.api.impl, action
 * com.cvte.tv.api.TV_API_SERVICE), the same call the hidden factory menu makes:
 *   ITvApiManager.getTVApiSystemAging()            = transaction 35
 *   ITVApiSystemAgingAidl.eventSystemAgingSetPowerMode = transaction 3
 *   ITVApiSystemAgingAidl.eventSystemAgingGetPowerMode = transaction 4
 *   EnumAcPowerMode: 0 STANDBY, 1 BOOTUP, 2 MEMORY (parcelled as its ordinal)
 * Does nothing on TVs without that service. Only writes if the mode isn't Bootup.
 */
package com.omeda.arc;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.os.IBinder;
import android.os.Parcel;
import android.util.Log;

public class AmadiCvtePower {
    private static final String TAG = "AmadiCvtePower";
    private static final String MGR = "com.cvte.tv.api.aidl.ITvApiManager";
    private static final String AGING = "com.cvte.tv.api.aidl.ITVApiSystemAgingAidl";
    private static final int BOOTUP = 1;

    public static void applyAsync(Context c) {
        final Context app = c.getApplicationContext();
        final Intent i = new Intent("com.cvte.tv.api.TV_API_SERVICE");
        i.setPackage("com.cvte.tv.api.impl");
        try {
            if (app.getPackageManager().resolveService(i, 0) == null) return; // not a CVTE TV
        } catch (Throwable t) { return; }
        ServiceConnection conn = new ServiceConnection() {
            @Override public void onServiceConnected(ComponentName n, final IBinder mgr) {
                final ServiceConnection self = this;
                new Thread(() -> {
                    try {
                        IBinder aging = getAging(mgr);
                        if (aging == null) { Log.w(TAG, "no aging api"); return; }
                        int cur = getMode(aging);
                        Log.i(TAG, "power mode now " + cur);
                        if (cur != BOOTUP) {
                            boolean ok = setMode(aging, BOOTUP);
                            Log.i(TAG, "set Bootup: " + ok + ", mode now " + getMode(aging));
                        }
                    } catch (Throwable t) {
                        Log.w(TAG, "power mode failed", t);
                    } finally {
                        try { app.unbindService(self); } catch (Throwable ignored) {}
                    }
                }).start();
            }
            @Override public void onServiceDisconnected(ComponentName n) {}
        };
        try {
            if (!app.bindService(i, conn, Context.BIND_AUTO_CREATE)) Log.w(TAG, "bind refused");
        } catch (Throwable t) {
            Log.w(TAG, "bind failed", t);
        }
    }

    private static IBinder getAging(IBinder mgr) throws Exception {
        Parcel d = Parcel.obtain(), r = Parcel.obtain();
        try {
            d.writeInterfaceToken(MGR);
            mgr.transact(35, d, r, 0);
            r.readException();
            return r.readStrongBinder();
        } finally { d.recycle(); r.recycle(); }
    }

    private static int getMode(IBinder aging) throws Exception {
        Parcel d = Parcel.obtain(), r = Parcel.obtain();
        try {
            d.writeInterfaceToken(AGING);
            aging.transact(4, d, r, 0);
            r.readException();
            if (r.readInt() == 0) return -1;
            return r.readInt();
        } finally { d.recycle(); r.recycle(); }
    }

    private static boolean setMode(IBinder aging, int mode) throws Exception {
        Parcel d = Parcel.obtain(), r = Parcel.obtain();
        try {
            d.writeInterfaceToken(AGING);
            d.writeInt(1);
            d.writeInt(mode);
            aging.transact(3, d, r, 0);
            r.readException();
            return r.readInt() != 0;
        } finally { d.recycle(); r.recycle(); }
    }
}
