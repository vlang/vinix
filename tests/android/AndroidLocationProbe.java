package org.vinix.tests;

import android.app.Activity;
import android.location.LocationManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;

/** Exercise the production location service without requesting or inventing a fix. */
public final class AndroidLocationProbe {
    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    private static void verify(LocationManager manager) {
        String[] names = {"gps", "network", "passive", "fused", "xdgportal", "", " ",
                          "GPS", "vinix-unregistered-provider"};
        for (String name : names) {
            require(!manager.isProviderEnabled(name), "unavailable provider reported enabled: " + name);
        }
        try {
            manager.isProviderEnabled(null);
            throw new AssertionError("null provider did not throw IllegalArgumentException");
        } catch (IllegalArgumentException expected) {
            // Android 26 rejects null; non-null unknown names simply return false.
        }
        require(manager.getAllProviders().isEmpty(), "platform unexpectedly advertises a provider");
        require(manager.getProviders(true).isEmpty(), "platform unexpectedly advertises an enabled provider");
        require(manager.getProviders(false).isEmpty(), "provider query changed platform availability");
        require(manager.getLastKnownLocation("gps") == null, "query fabricated a location fix");
    }

    public static final class BootstrapActivity extends Activity {
        private LocationManager manager;
        private volatile Throwable workerFailure;

        @Override protected void onCreate(Bundle state) {
            super.onCreate(state);
            try {
                manager = (LocationManager) getSystemService(LocationManager.class);
                require(manager != null && manager.getClass() == LocationManager.class,
                        "actual typed location service unavailable");
                manager.isProviderEnabled("gps"); // First new API call makes the old-runtime control decisive.
                verify(manager);
                require(!getPackageManager().hasSystemFeature("android.hardware.location.gps")
                        && !getPackageManager().hasSystemFeature("android.hardware.location.network"),
                        "provider query enabled unsupported location hardware");
            } catch (Throwable failure) {
                failure.printStackTrace();
                System.exit(1);
            }
        }

        @Override protected void onPostResume() {
            super.onPostResume();
            try {
                require(Looper.myLooper() == Looper.getMainLooper(), "main callback has wrong Looper");
                Thread worker = new Thread(new Runnable() {
                    @Override public void run() {
                        try {
                            require(Looper.myLooper() == null, "plain worker unexpectedly has a Looper");
                            for (int i = 0; i < 32; i++) verify(manager);
                        } catch (Throwable failure) { workerFailure = failure; }
                    }
                }, "vinix-location-query");
                worker.start();
                worker.join(5000);
                require(!worker.isAlive(), "provider queries blocked the worker");
                if (workerFailure != null) throw new AssertionError("worker provider query failed", workerFailure);
                new Handler(Looper.getMainLooper()).post(new Runnable() {
                    @Override public void run() {
                        try {
                            require(Looper.myLooper() == Looper.getMainLooper(), "continuation has wrong Looper");
                            verify(manager);
                            System.out.println("ANDROID-LOCATION-PASS service=production providers=absent null=illegal-argument unknown=disabled worker=no-looper handler=live location=absent");
                            System.exit(0);
                        } catch (Throwable failure) {
                            failure.printStackTrace();
                            System.exit(1);
                        }
                    }
                });
            } catch (Throwable failure) {
                failure.printStackTrace();
                System.exit(1);
            }
        }
    }
}
