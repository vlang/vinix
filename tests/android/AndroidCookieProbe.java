package org.vinix.tests;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.webkit.CookieManager;
import android.webkit.ValueCallback;

/** Genuine application fixture: all cookie behavior comes from the installed ATL. */
public final class AndroidCookieProbe {
    private static final String HTTPS = "https://cookie-probe.vinix.invalid";
    private static final String HTTP = "http://cookie-probe.vinix.invalid";
    private static final String SUBDOMAIN = "https://sub.cookie-probe.vinix.invalid";
    private static final String OTHER = "https://other.vinix.invalid";
    private static final String PREFIX = "vinix_test_";
    private static final String SUPPLEMENTARY = "\uD83D\uDE00";
    private static CookieManager cookies;
    private static Handler main;
    private static final int[] callbacks = new int[7];

    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    private static void fail(Throwable error) {
        System.out.println("ANDROID-COOKIE-FAIL");
        error.printStackTrace();
        System.exit(1);
    }

    private static boolean has(String header, String name, String value) {
        if (header == null) return false;
        for (String pair : header.split(";")) {
            if (pair.trim().equals(name + "=" + value)) return true;
        }
        return false;
    }

    private static void expect(String url, String name, String value) {
        require(has(cookies.getCookie(url), name, value), "cookie missing at " + url + ": " + name);
    }

    private static void absent(String url, String name) {
        String header = cookies.getCookie(url);
        if (header == null) return;
        for (String pair : header.split(";")) {
            require(!pair.trim().startsWith(name + "="), "unexpected cookie at " + url + ": " + name);
        }
    }

    private static void basicChecks() {
        cookies = CookieManager.getInstance();
        require(cookies == CookieManager.getInstance(), "CookieManager is not a singleton");
        require(cookies.acceptCookie(), "initial accept policy must be true");
        require(cookies.getCookie("https://empty-cookie-probe.invalid/") == null, "empty store result is not null");

        cookies.setCookie(HTTPS + "/", PREFIX + "host=one; Path=/; HttpOnly");
        expect(HTTPS + "/", PREFIX + "host", "one");
        expect(HTTP + "/", PREFIX + "host", "one");
        absent(SUBDOMAIN + "/", PREFIX + "host");
        absent(OTHER + "/", PREFIX + "host");
        cookies.setCookie("cookie-probe.vinix.invalid", PREFIX + "bare_url=one; Path=/");
        expect("cookie-probe.vinix.invalid", PREFIX + "bare_url", "one");
        expect(HTTP + "/", PREFIX + "bare_url", "one");

        cookies.setCookie(HTTPS + "/", PREFIX + "domain=one; Domain=vinix.invalid; Path=/");
        expect(SUBDOMAIN + "/", PREFIX + "domain", "one");
        expect(OTHER + "/", PREFIX + "domain", "one");

        cookies.setCookie(HTTPS + "/scope/entry", PREFIX + "path=one; Path=/scope");
        expect(HTTPS + "/scope", PREFIX + "path", "one");
        expect(HTTPS + "/scope/child", PREFIX + "path", "one");
        absent(HTTPS + "/scoped", PREFIX + "path");
        absent(HTTPS + "/outside", PREFIX + "path");
        cookies.setCookie(HTTPS + "/dir/entry", PREFIX + "default_path=one");
        expect(HTTPS + "/dir/child", PREFIX + "default_path", "one");
        absent(HTTPS + "/outside", PREFIX + "default_path");

        cookies.setCookie(HTTPS + "/", PREFIX + "secure=one; Secure; Path=/; HttpOnly");
        expect(HTTPS + "/", PREFIX + "secure", "one");
        absent(HTTP + "/", PREFIX + "secure");
        cookies.setCookie(HTTP + "/", PREFIX + "secure=overwritten; Path=/");
        expect(HTTPS + "/", PREFIX + "secure", "one");
        absent(HTTP + "/", PREFIX + "secure");
        cookies.setCookie(HTTP + "/", PREFIX + "insecure_secure=bad; Secure; Path=/");
        absent(HTTPS + "/", PREFIX + "insecure_secure");

        cookies.setCookie(HTTPS + "/", PREFIX + "bad_domain=bad; Domain=unrelated.invalid; Path=/");
        absent(HTTPS + "/", PREFIX + "bad_domain");
        absent("https://unrelated.invalid/", PREFIX + "bad_domain");
        // co.uk reaches the jar's public-suffix check, beyond domain parsing.
        cookies.setCookie("https://vinix-cookie-probe.co.uk/", PREFIX + "public_suffix=bad; Domain=co.uk; Path=/");
        absent("https://vinix-cookie-probe.co.uk/", PREFIX + "public_suffix");
        absent("https://other.co.uk/", PREFIX + "public_suffix");

        cookies.setCookie(HTTPS + "/", "__Host-" + PREFIX + "host=one; Secure; Path=/");
        expect(HTTPS + "/", "__Host-" + PREFIX + "host", "one");
        cookies.setCookie(HTTPS + "/scope", "__Host-" + PREFIX + "bad_path=bad; Secure; Path=/scope");
        absent(HTTPS + "/scope", "__Host-" + PREFIX + "bad_path");
        cookies.setCookie(HTTPS + "/", "__Host-" + PREFIX + "bad_domain=bad; Secure; Domain=vinix.invalid; Path=/");
        absent(HTTPS + "/", "__Host-" + PREFIX + "bad_domain");
        cookies.setCookie(HTTPS + "/", "__Secure-" + PREFIX + "insecure=bad; Path=/");
        absent(HTTPS + "/", "__Secure-" + PREFIX + "insecure");

        cookies.setCookie(HTTPS + "/", PREFIX + "expired=one; Max-Age=86400; Path=/");
        expect(HTTPS + "/", PREFIX + "expired", "one");
        cookies.setCookie(HTTPS + "/", PREFIX + "expired=gone; Expires=Wed, 10 May 2000 23:59:59 GMT; Path=/");
        absent(HTTPS + "/", PREFIX + "expired");
        cookies.setCookie(HTTPS + "/", PREFIX + "removed=one; Path=/");
        cookies.setCookie(HTTPS + "/", PREFIX + "removed=gone; Max-Age=0; Path=/");
        absent(HTTPS + "/", PREFIX + "removed");

        cookies.setAcceptCookie(false);
        require(!cookies.acceptCookie(), "accept policy not updated");
        // Acceptance policy controls automatic WebView cookies, not this manual API.
        cookies.setCookie(HTTPS + "/", PREFIX + "manual_policy=one; Path=/");
        expect(HTTPS + "/", PREFIX + "manual_policy", "one");
        cookies.setAcceptCookie(true);
        require(cookies.acceptCookie(), "accept policy not restored");
    }

    private static void mainAsync(final int index, final String value, final boolean expected,
                                  final Runnable continuation) {
        mainAsyncAt(index, HTTPS + "/", value, expected, continuation);
    }

    private static void mainAsyncAt(final int index, final String url, final String value,
                                    final boolean expected, final Runnable continuation) {
        final boolean[] returned = {false};
        cookies.setCookie(url, value, new ValueCallback<Boolean>() {
            @Override public void onReceiveValue(Boolean result) {
                try {
                    require(returned[0], "callback executed before setter returned");
                    require(Looper.myLooper() == Looper.getMainLooper(), "callback left caller's main Looper");
                    require(++callbacks[index] == 1, "callback repeated: " + index);
                    require(result != null && result.booleanValue() == expected, "wrong callback result: " + index);
                    main.post(continuation);
                } catch (Throwable error) { fail(error); }
            }
        });
        returned[0] = true;
        require(callbacks[index] == 0, "callback was synchronous: " + index);
    }

    private static void noLooperWorker() {
        new Thread(new Runnable() {
            @Override public void run() {
                try {
                    require(Looper.myLooper() == null, "worker unexpectedly has a Looper");
                    cookies.setCookie(HTTPS + "/", PREFIX + "null_worker=one; Path=/", null);
                    expect(HTTPS + "/", PREFIX + "null_worker", "one");
                    cookies.setCookie(HTTPS + "/", PREFIX + "no_looper=gone; Max-Age=0; Path=/");
                    boolean rejected = false;
                    try {
                        cookies.setCookie(HTTPS + "/", PREFIX + "no_looper=bad; Path=/", new ValueCallback<Boolean>() {
                            @Override public void onReceiveValue(Boolean result) { fail(new AssertionError("no-Looper callback invoked")); }
                        });
                    } catch (RuntimeException expected) { rejected = true; }
                    require(rejected, "nonnull callback without Looper accepted");
                    absent(HTTPS + "/", PREFIX + "no_looper");
                    main.post(new Runnable() {
                        @Override public void run() { looperWorker(); }
                    });
                } catch (Throwable error) { fail(error); }
            }
        }, "cookie-no-looper-probe").start();
    }

    private static void looperWorker() {
        new Thread(new Runnable() {
            @Override public void run() {
                try {
                    Looper.prepare();
                    final Looper caller = Looper.myLooper();
                    final Thread thread = Thread.currentThread();
                    final boolean[] returned = {false};
                    cookies.setCookie(HTTPS + "/", PREFIX + "looper_worker=one; Path=/", new ValueCallback<Boolean>() {
                        @Override public void onReceiveValue(Boolean result) {
                            try {
                                require(returned[0], "worker callback was synchronous");
                                require(Looper.myLooper() == caller && Thread.currentThread() == thread,
                                        "callback left worker caller's Looper/thread");
                                require(++callbacks[6] == 1 && Boolean.TRUE.equals(result), "worker callback count/result");
                                expect(HTTPS + "/", PREFIX + "looper_worker", "one");
                                caller.quit();
                            } catch (Throwable error) { fail(error); }
                        }
                    });
                    returned[0] = true;
                    require(callbacks[6] == 0, "worker callback ran before Looper loop");
                    Looper.loop();
                    main.post(new Runnable() {
                        @Override public void run() {
                            try { finish(); } catch (Throwable error) { fail(error); }
                        }
                    });
                } catch (Throwable error) { fail(error); }
            }
        }, "cookie-caller-looper-probe").start();
    }

    private static void savedChecks() {
        expect(HTTPS + "/", PREFIX + "persist", "ready");
        expect(HTTPS + "/", PREFIX + "utf16", SUPPLEMENTARY);
        absent(HTTP + "/", PREFIX + "persist");
        expect(HTTPS + "/", PREFIX + "session", "ready");
        expect(HTTPS + "/outside", PREFIX + "multi", "root");
        require(!has(cookies.getCookie(HTTPS + "/outside"), PREFIX + "multi", "scoped"), "scoped cookie escaped its path");
        expect(HTTPS + "/scope/child", PREFIX + "multi", "root");
        expect(HTTPS + "/scope/child", PREFIX + "multi", "scoped");
        expect(OTHER + "/", PREFIX + "persist_domain", "ready");
        absent(SUBDOMAIN + "/", PREFIX + "persist");
    }

    private static void finish() {
        for (int count : callbacks) require(count == 1, "callback did not run exactly once");
        cookies.setCookie(HTTPS + "/", PREFIX + "persist=ready; Max-Age=86400; Path=/; Secure; HttpOnly");
        cookies.setCookie(HTTPS + "/", PREFIX + "utf16=" + SUPPLEMENTARY + "; Max-Age=86400; Path=/");
        cookies.setCookie(HTTPS + "/", PREFIX + "session=ready; Path=/");
        cookies.setCookie(HTTPS + "/", PREFIX + "multi=root; Max-Age=86400; Path=/");
        cookies.setCookie(HTTPS + "/scope/child", PREFIX + "multi=scoped; Max-Age=86400; Path=/scope");
        cookies.setCookie(HTTPS + "/", PREFIX + "persist_domain=ready; Domain=vinix.invalid; Max-Age=86400; Path=/");
        cookies.flush();
        savedChecks();
        System.out.println("ANDROID-COOKIE-PASS singleton=real matching=checked callbacks=deferred-on-caller-loopers unchanged=true no-looper=checked flush=returned");
        System.exit(0);
    }

    private static Runnable advance(final int step) {
        return new Runnable() {
            @Override public void run() { mainStep(step); }
        };
    }

    private static void mainStep(int step) {
        try {
            switch (step) {
                case 0:
                    mainAsync(0, PREFIX + "async=one; Path=/", true, advance(1));
                    break;
                case 1:
                    expect(HTTPS + "/", PREFIX + "async", "one");
                    mainAsync(1, PREFIX + "async=one; Path=/", true, advance(2));
                    break;
                case 2:
                    mainAsync(2, PREFIX + "async_bad=bad; Domain=unrelated.invalid; Path=/", false, advance(3));
                    break;
                case 3:
                    absent(HTTPS + "/", PREFIX + "async_bad");
                    absent(HTTPS + "/", PREFIX + "valid_expired_absent");
                    mainAsync(3, PREFIX + "valid_expired_absent=gone; Max-Age=0; Path=/", true, advance(4));
                    break;
                case 4:
                    absent(HTTPS + "/", PREFIX + "valid_expired_absent");
                    mainAsyncAt(4, HTTP + "/", PREFIX + "live_secure_over_http=bad; Secure; Path=/", false, advance(5));
                    break;
                case 5:
                    absent(HTTPS + "/", PREFIX + "live_secure_over_http");
                    mainAsyncAt(5, HTTP + "/", PREFIX + "invalid_expired_secure=gone; Secure; Max-Age=0; Path=/", false, advance(6));
                    break;
                case 6:
                    absent(HTTPS + "/", PREFIX + "invalid_expired_secure");
                    noLooperWorker();
                    break;
                default:
                    throw new AssertionError("unknown callback stage " + step);
            }
        } catch (Throwable error) { fail(error); }
    }

    public static final class BootstrapActivity extends Activity {
        @Override protected void onCreate(Bundle state) {
            super.onCreate(state);
            try {
                require(Looper.myLooper() == Looper.getMainLooper(), "bootstrap not on main Looper");
                main = new Handler(Looper.getMainLooper());
                basicChecks();
                mainStep(0);
            } catch (Throwable error) { fail(error); }
        }
    }

    /** Launch this activity in a second ATL process, using the same test APK. */
    public static final class PersistenceActivity extends Activity {
        @Override protected void onCreate(Bundle state) {
            super.onCreate(state);
            try {
                cookies = CookieManager.getInstance();
                savedChecks();
                System.out.println("ANDROID-COOKIE-RELOAD-PASS persistent=real session=restored paths=independent");
                System.exit(0);
            } catch (Throwable error) { fail(error); }
        }
    }
}
