package org.vinix.tests;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.autofill.AutofillManager;
import android.view.View;
import android.widget.EditText;

/** Normal app entry points exercise the production manager when no service is enabled. */
public final class AndroidAutofillProbe {
    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }
    private static void exercise(AutofillManager manager, View view) {
        manager.cancel();
        manager.requestAutofill(view);
        manager.notifyValueChanged(view);
    }
    public static final class BootstrapActivity extends Activity {
        private AutofillManager manager;
        private EditText edit;
        private volatile Throwable workerFailure;

        @Override protected void onCreate(Bundle state) {
            super.onCreate(state);
            try {
                require(!getPackageManager().hasSystemFeature("android.software.autofill"),
                        "fixture requires the actual platform's disabled autofill feature");
                manager = (AutofillManager) getSystemService(AutofillManager.class);
                require(manager != null && manager.getClass() == AutofillManager.class,
                        "actual typed system service unavailable");
                manager.cancel(); // No session exists and there is no enabled service.
                edit = new EditText(this);
                edit.setText("vinix-autofill-sentinel");
                setContentView(edit);
            } catch (Throwable failure) {
                failure.printStackTrace();
                System.exit(1);
            }
        }

        @Override protected void onPostResume() {
            super.onPostResume();
            try {
                require(Looper.myLooper() == Looper.getMainLooper(), "main callback has wrong Looper");
                require(edit.requestFocus(), "actual input failed to focus");
                for (int i = 0; i < 64; i++) exercise(manager, edit);
                Thread worker = new Thread(new Runnable() {
                    @Override public void run() {
                        try {
                            require(Looper.myLooper() == null, "plain worker unexpectedly has a Looper");
                            for (int i = 0; i < 64; i++) exercise(manager, edit);
                        } catch (Throwable failure) { workerFailure = failure; }
                    }
                }, "vinix-autofill-no-service");
                worker.start();
                worker.join(5000);
                require(!worker.isAlive(), "autofill methods blocked the worker");
                if (workerFailure != null) throw new AssertionError("worker autofill calls failed", workerFailure);
                new Handler(Looper.getMainLooper()).post(new Runnable() {
                    @Override public void run() {
                        try {
                            require(Looper.myLooper() == Looper.getMainLooper(), "continuation has wrong Looper");
                            exercise(manager, edit);
                            require("vinix-autofill-sentinel".equals(edit.getText().toString()),
                                    "autofill methods changed application input");
                            require(!getPackageManager().hasSystemFeature("android.software.autofill"),
                                    "autofill methods enabled unsupported autofill");
                            System.out.println("ANDROID-AUTOFILL-PASS service=production no-service=returned apis=cancel-request-notify repeated=main-worker input=preserved handler=live");
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
