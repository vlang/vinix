# Popular Google Play app startup probes, 21 October 2026

None of the eleven popular app identities reached a usable UI in this run.
The Arity control calculated `123+456=579` through the same native WS runner.
These are startup observations of the exact inputs below, not a claim about
every release or feature of these apps.

The sample uses apps whose linked Google Play listings show at least one
billion downloads. It is a selection by cumulative installs, not an ordered
country-specific daily chart. APKs were obtained from publisher downloads or
a public mirror; they were not extracted from an authenticated Play account.
The report records actual versions, package IDs, APK/container SHA256 values,
SDK requirements, native ABIs and Android signature-verifier output. No APK
or application bytecode was patched or bundled into this repository.

| App / exact version | Input tested | First observed blocker |
| --- | --- | --- |
| [WhatsApp](https://play.google.com/store/apps/details?id=com.whatsapp) 2.26.41.78 | Complete publisher APK | `AppContext.set has not been invoked` in the Main constructor. |
| [TikTok](https://play.google.com/store/apps/details?id=com.zhiliaoapp.musically) 47.4.3 | Standalone APK, ARM64 included | Static initialization calls `getFilesDir()` with a null application context. |
| [Telegram](https://play.google.com/store/apps/details?id=org.telegram.messenger) 13.0.3 | Play package base; ABI/density splits required | LaunchActivity constructor calls `getSharedPreferences()` on a null context. |
| Telegram 13.1.0 | Complete [publisher APK](https://telegram.org/android), package `org.telegram.messenger.web` | Reproduces the same null-context failure; this is a separate distribution/version. |
| [Facebook](https://play.google.com/store/apps/details?id=com.facebook.katana) 583.0.0.39.55 | Signed base from XAPK; density split verified but not installed | `AppContext.set has not been invoked` when creating the activity delegate. |
| [Instagram](https://play.google.com/store/apps/details?id=com.instagram.android) 452.0.0.48.64 | Signed base from XAPK; density split verified but not installed | Null `Resources.updateConfiguration` call while attaching the AppCompat base context. |
| [Facebook Lite](https://play.google.com/store/apps/details?id=com.facebook.lite) 533.0.0.11.105 | Standalone ARM64 APK | `ClassNotFoundException: com.facebook.lite.MainActivity`. |
| [YouTube](https://play.google.com/store/apps/details?id=com.google.android.youtube) 21.42.243 | Standalone APK, ARM64 included | Missing `android.os.SystemClock.elapsedRealtimeNanos()` JNI binding. |
| [Snapchat](https://play.google.com/store/apps/details?id=com.snapchat.android) 14.28.0.54 | Standalone APK, ARM64 included | Same missing nanosecond-clock JNI binding during MainActivity construction. |
| [Spotify](https://play.google.com/store/apps/details?id=com.spotify.music) 9.1.92.3058 | Standalone APK, ARM64 included | `ATLLoadedApp.createActivity` calls the app's overridden `setTitle()`, which throws an assertion. |
| [Chrome](https://play.google.com/store/apps/details?id=com.android.chrome) 155.0.8059.84 | Base requiring splits; supplied mirror variant declares ARMv7 only | ATL reports `Failed to find main Activity` and exits. A complete ARM64 package remains untested. |
| [Roblox](https://play.google.com/store/apps/details?id=com.roblox.client) 2.743.1136 | Base requiring ABI split; no native libraries in base | Missing `NativeSettingsInterface.nativeSetBaseUrl` JNI implementation. This does not test the complete native engine package. |

Required splits are **not installed** by the native WS runtime. Base-only
rows therefore do not establish whole-package compatibility. The XAPK bases
and their included density splits were separately signature-verified. The
same application-context failure in Telegram's complete publisher APK shows
that its observed startup issue is not limited to the base-only input.

Every popular-app attempt entered the native WS launcher, was observed with
`libvinix-android-native.so` mapped, and exited with status 1. No popular app
produced the backend-ready marker. The observer reported GTK/GDK/X11 absent;
there was no X server fallback. Each app had fresh guest state and a dedicated
12 GiB ARM64 QEMU/HVF boot on the preserved 16 KiB-page Vinix kernel/runtime.
The earlier runtime's newer fork ABI preflight remains outside these checks.
No authentication, messaging, playback, gameplay or phone hardware pass is
claimed. `functional_passed` remains null for the failed startup probes.

The next work suggested by the traces is application/context initialization
before Activity construction, split installation and class/native-library
loading, the clock JNI binding, launcher resolution, and framework calls that
dispatch into app overrides too early. Those are diagnoses of the captured
first failures; later barriers remain unknown. This run changes the test
tooling, not the runtime implementation.

`results.json` contains the exact metadata, artifact/source hashes, outcomes,
and evidence links. Each `*.serial.log.gz` retains the full guest serial log;
each `*.png` is an unmodified QMP framebuffer capture. Failed-launch captures
show the desktop's exit placeholder and are not screenshots of a working app.
The tests reuse the Android Calculator desktop launcher slot, so its outer
caption and icon remain; APK hashes and the serial traces identify each app.
`manual-review.json` records the separately authored visual/root-cause review.

## Reproduction

Use the prepared native WS boot image and runtime artifacts described in the
[preceding investigation](../native-ws/README.md). The maintained V driver is
[suite.v](../../../../native-android-ws/suite.v), with the sample inputs in
[popular-apps.json](../../../../native-android-ws/popular-apps.json). Paths in
that manifest describe this macOS/HVF workspace and can be changed for another
prepared private VM. Stop that VM before running the driver; the driver
serializes its own invocations with a lock alongside the boot image.

Fetch the manifest's public source URLs into the named files, preserving the
bytes. Some URLs deliver an XAPK container despite the `.apk` destination;
the driver detects it, extracts only safe flat APK members, and verifies each
with Android's signer tool. A required split still produces an explicitly
limited base-APK probe, not an installation pass.

The host tools used here are Google's
[AAPT2 8.7.3-12006047 macOS artifact](https://dl.google.com/android/maven2/com/android/tools/build/aapt2/8.7.3-12006047/aapt2-8.7.3-12006047-osx.jar)
and `android-15/lib/apksigner.jar` from the
[SDK Build Tools 35 archive](https://dl.google.com/android/repository/build-tools_r35_linux.zip).
The SDK archive SHA1 was checked against Google's repository metadata:
`2cfaa0bbb2336e9ec18ed3ecea84fa2e2af607bc`. `tools-sha256.json` records the
actual extracted tools and metadata hashes. Java 25 ran the signer tool;
these tools inspect APKs on the host and are not the guest Android runtime.
Source URLs can update; use the recorded hashes and cached inputs when
repeating the exact versions in this report.

```sh
v -os linux -arch arm64 -cc aarch64-linux-musl-gcc -gc none \
  -o build/android-native-ws/popular-launcher tests/native-android-ws/launcher.v
v -cc cc -o build/android-native-ws/suite tests/native-android-ws/suite.v
build/android-native-ws/suite --self-test
build/android-native-ws/suite tests/native-android-ws/popular-apps.json
```

The sample manifest selects eleven app identities and the Arity control. The
extra Telegram publisher variant was run with the same settings and its
publisher package ID/path. The collector merges later successful test setup
over initial container-detection attempts, checks screenshot hashes, and
applies the separate authored review:

```sh
v run tests/native-android-ws/retain-suite.v OUTPUT REVIEW.json BATCH_DIR...
```

The runner never marks a live window as a functional pass. Its self-check
also verifies that a ready marker followed by a runtime failure or process
exit cannot become a window success. The control's actual arithmetic result
was entered and inspected separately through QMP.
