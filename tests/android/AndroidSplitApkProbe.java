package org.vinix.tests;

import android.app.Activity;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.os.Bundle;
import java.io.File;
import java.io.InputStream;
import java.util.Arrays;

/** A normal app: metadata from the base, a resource and JNI library from a dexless split. */
public final class AndroidSplitApkProbe {
    private static native int nativeSentinel();
    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }
    private static void checkPaths(ApplicationInfo info) throws Exception {
        require(info.sourceDir.endsWith("android-split-probe.apk"), "sourceDir is not the base: " + info.sourceDir);
        require(info.sourceDir.equals(info.publicSourceDir), "base public source differs");
        require(info.splitSourceDirs != null && info.splitSourceDirs.length == 1,
                "split source metadata missing");
        require(info.splitSourceDirs[0].endsWith("config.arm64_v8a.apk"), "wrong split source");
        require(Arrays.equals(info.splitSourceDirs, info.splitPublicSourceDirs), "public split paths differ");
        require(new File(info.sourceDir).getCanonicalPath().equals(info.sourceDir), "base path is not canonical");
        require(!info.sourceDir.contains(":"), "sourceDir contains archive list");
    }
    public static final class BootstrapActivity extends Activity {
        @Override protected void onCreate(Bundle state) {
            super.onCreate(state);
            try {
                PackageManager manager = getPackageManager();
                PackageInfo pkg = manager.getPackageInfo(getPackageName(), PackageManager.GET_META_DATA);
                require("org.vinix.tests.split".equals(pkg.packageName), "split manifest replaced base package");
                require(pkg.versionCode == 7007 && "7.0.fixture".equals(pkg.versionName), "base version lost");
                require(Arrays.equals(pkg.splitNames, new String[] { "config.arm64_v8a" }), "split name metadata missing");
                checkPaths(pkg.applicationInfo); // GET_META_DATA forces the ApplicationInfo copy path.
                checkPaths(manager.getApplicationInfo(getPackageName(), PackageManager.GET_META_DATA));
                require("base-value".equals(pkg.applicationInfo.metaData.getString("vinix.base.marker")), "base metadata lost");
                InputStream stream = getAssets().open("vinix-split-marker.txt");
                try { require(stream.read() == 'S' && stream.read() == 'P', "split asset unavailable"); }
                finally { stream.close(); }
                System.loadLibrary("vinix_split_probe");
                require(nativeSentinel() == 0xA64, "genuine split JNI library unavailable");
                System.out.println("ANDROID-SPLIT-PASS base-metadata=correct split-paths=visible split-asset=read native-split=loaded");
                System.exit(0);
            } catch (Throwable failure) {
                failure.printStackTrace();
                System.exit(1);
            }
        }
    }
}
