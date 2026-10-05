package org.vinix.tests;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Surface;
import android.view.SurfaceHolder;
import android.view.SurfaceView;

/** A normal app exercising production window, EGL and GTK buffer ownership. */
public final class AndroidEglQueueProbe {
    private static native void nativePhase(int phase);
    private static native int nativeError();
    private static native int nativeRun(Surface surface, BootstrapActivity activity);

    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    public static final class BootstrapActivity extends Activity implements SurfaceHolder.Callback {
        private boolean started;

        @Override protected void onCreate(Bundle state) {
            super.onCreate(state);
            try {
                System.loadLibrary("vinix_egl_queue_probe");
                SurfaceView view = new SurfaceView(this);
                view.getHolder().addCallback(this);
                setContentView(view);
            } catch (Throwable failure) { fail(failure); }
        }

        /** Called by the JNI worker; only ordinary main-thread scheduling is used. */
        public void pauseConsumer(final int phase) {
            Runnable action = new Runnable() {
                @Override public void run() {
                    try {
                        require(Looper.myLooper() == Looper.getMainLooper(), "pause has wrong Looper");
                        nativePhase(phase);
                        Thread.sleep(1200);
                        require(nativeError() == 0x3000, "worker EGL error leaked to the UI thread");
                        nativePhase(phase + 1);
                    } catch (Throwable failure) { fail(failure); }
                }
            };
            if (phase == 3) new Handler(Looper.getMainLooper()).postDelayed(action, 200);
            else runOnUiThread(action);
        }

        @Override public void surfaceCreated(SurfaceHolder holder) {}

        @Override public void surfaceChanged(final SurfaceHolder holder, int format, int width, int height) {
            if (started || width <= 0 || height <= 0) return;
            started = true;
            new Thread(new Runnable() {
                @Override public void run() {
                    try {
                        require(nativeRun(holder.getSurface(), BootstrapActivity.this) >= 32,
                                "too few recovered frames");
                        new Handler(Looper.getMainLooper()).postDelayed(new Runnable() {
                            @Override public void run() {
                                try {
                                    finish();
                                    System.out.println("ANDROID-EGL-QUEUE-PASS surface=production starvation=bounded error=thread-local pixels=preserved recovery=32 shutdown=pending-callbacks");
                                    System.exit(0);
                                } catch (Throwable failure) { fail(failure); }
                            }
                        }, 500);
                    } catch (Throwable failure) { fail(failure); }
                }
            }, "vinix-egl-queue-render").start();
        }

        @Override public void surfaceDestroyed(SurfaceHolder holder) {}

        private static void fail(Throwable failure) {
            failure.printStackTrace();
            System.out.println("ANDROID-EGL-QUEUE-FAIL");
            System.exit(1);
        }
    }
}
