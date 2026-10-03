package org.vinix.tests;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.autofill.AutofillManager;
import android.view.View;
import android.widget.EditText;
import java.util.Arrays;

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
    private static String[] verifyHintMetadata(View view, View other) {
        view.setAutofillHints((String[]) null); // Exercise the client-proven setter before its getter.
        require(view.getAutofillHints() == null && other.getAutofillHints() == null,
                "cleared or new view unexpectedly has hints");
        view.setAutofillHints("username", "password");
        require(Arrays.equals(view.getAutofillHints(), new String[] {"username", "password"}),
                "hint roundtrip changed order or values");
        view.setAutofillHints((String[]) null);
        require(view.getAutofillHints() == null, "null hint array did not clear metadata");
        view.setAutofillHints("username");
        view.setAutofillHints();
        require(view.getAutofillHints() == null, "empty hint array did not clear metadata");
        String[] hints = {"username", "password", "", null, "userName", "username"};
        view.setAutofillHints(hints);
        require(view.getAutofillHints() == hints, "setter did not retain Android 26 array ownership");
        require(Arrays.equals(view.getAutofillHints(),
                new String[] {"username", "password", "", null, "userName", "username"}),
                "hint metadata was filtered or reordered");
        hints[0] = "vinix-hint-input-alias";
        require("vinix-hint-input-alias".equals(view.getAutofillHints()[0]),
                "caller array mutation was not visible");
        view.getAutofillHints()[1] = "vinix-hint-output-alias";
        require("vinix-hint-output-alias".equals(hints[1]),
                "getter did not expose Android 26 array ownership");
        other.setAutofillHints("emailAddress");
        require(Arrays.equals(other.getAutofillHints(), new String[] {"emailAddress"})
                && view.getAutofillHints() == hints, "hint metadata leaked between views");
        return hints;
    }
    public static final class BootstrapActivity extends Activity {
        private AutofillManager manager;
        private EditText edit;
        private String[] retainedHints;
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
                retainedHints = verifyHintMetadata(edit, new View(this));
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
                            require(edit.getAutofillHints() == retainedHints && Arrays.equals(retainedHints,
                                    new String[] {"vinix-hint-input-alias", "vinix-hint-output-alias", "", null, "userName", "username"}),
                                    "manager calls changed hint metadata");
                            require("vinix-autofill-sentinel".equals(edit.getText().toString()),
                                    "autofill methods changed application input");
                            require(!getPackageManager().hasSystemFeature("android.software.autofill"),
                                    "autofill methods enabled unsupported autofill");
                            System.out.println("ANDROID-AUTOFILL-PASS service=production no-service=returned apis=cancel-request-notify hints=android26-metadata repeated=main-worker input=preserved handler=live");
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
