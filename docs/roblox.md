# Roblox APK on Vinix

The Roblox desktop entry launches the unchanged Android APK through Vinix's
native ARM64 [Android Translation Layer and ART runtime](android.md).
ART executes its Java/DEX splash activity, and the Android native-library
loader loads the APK's ARM64 engine and completes `JNI_OnLoad` on Vinix.
Roblox compatibility is still being implemented. HTTPS startup requests now
pass certificate verification and layout inflation handles `<requestFocus />`.
The framework now supplies `View.OnCapturedPointerListener` and native mouse
capture and the virtual display's supported refresh-rate query. Activity and
fragment callbacks now follow the framework lifecycle boundaries. The latest
launch reaches native shell startup, creates the rendering surface and starts
Roblox's Lua app, then aborts because ATL declares `android.webkit.ValueCallback`
as a class where the APK requires an interface.
A usable Roblox screen, authentication and gameplay remain unverified.

Build the coherent native Android runtime described in [Android APKs](android.md),
then stage the Roblox launchers and include both layers in the desktop:

```sh
./build-android-aarch64.sh --art-runtime /path/to/desugared-art-runtime \
    --bionic-runtime /path/to/bionic-runtime --atl-runtime /path/to/atl-runtime
./build-roblox-aarch64.sh
./build-desktop-aarch64.sh --compact-initramfs --with-roblox
```

`--with-roblox` includes the shared native Android layer. The Roblox builder
verifies the staged ART, native-library loader and coherent framework receipts,
including their payload hashes, private libc build, native architecture and
16 KiB page contract.
It stages two small launchers and a manifest which records their hashes and the
shared Android runtime's provenance. The default output is
`build-aarch64-roblox/aarch64/staging`. `VINIX_ANDROID_STAGING` selects the shared
Android layer; `VINIX_ROBLOX_STAGING` selects the Roblox launcher layer when
building the desktop. The builder's `--android-staging` and `--build-dir`
options select those paths explicitly.

Supply a complete genuine Roblox APK containing `lib/arm64-v8a/libroblox.so`
at `$HOME/Roblox.apk` in Vinix, normally `/root/Roblox.apk`. The builder does
not download or bundle the proprietary APK. Open **Roblox** from Start or
Quick Launch, or launch it on an existing X11 display:

```sh
VINIX_ROBLOX_APK=/root/Roblox.apk run-roblox-client
run-roblox /root/Roblox.apk
```

The launcher selects `com/roblox/client/startup/ActivitySplash` and a 1280×720
window. Additional arguments are passed to ATL. App data uses the same
`ANDROID_APP_DATA_DIR` setting as other Android APKs, normally
`$HOME/.local/share/vinix/android`. The APK and its native engine are unchanged.

The tested APK is Roblox **2.738.1397**, `com.roblox.client`, version code 3092,
with SHA256 `bbe00ae306cc251c4ea55b7a932d9c524ecb0d6d9203c2a6161bcf0fae792742`.
The coherent framework supplies `Build.SUPPORTED_64_BIT_ABIS`; the private
native-library loader's fork callbacks resolve its earlier `__register_atfork`
dependency. The real configuration implementation supplies asset-manager
snapshots and screen qualifiers, and checked I/O wrappers supply its fortified Android APIs.
The private source-built allocator provides Android's ARM64 `mallinfo` ABI with
real live, reusable and peak mapped allocation counters. The checked string
copy wrapper also provides `__strlcpy_chk`. Both pass native Vinix fixtures;
allocation tests cover resizing, alignment, threaded churn and concurrent fork.
A successful Android calculator or allocator test does not establish Roblox
compatibility.

Run the [Android observation harness](../tests/android/README.md) with the actual
APK to retain startup diagnostics and its framebuffer:

```sh
python3 tests/android/run.py --launcher roblox --apk /path/to/Roblox.apk \
    --observe --mode direct --runtime-arg=-X --runtime-arg=-verbose:jni \
    --state-dir /tmp/vinix-roblox-observation
python3 tests/android/run.py --launcher roblox --apk /path/to/Roblox.apk \
    --observe --mode desktop --state-dir /tmp/vinix-roblox-desktop-observation
```

Observation requires an X11 window to draw and remain mapped; a startup
failure is retained as a failed result. A window observation alone does not
establish a usable Roblox screen. The direct run on 3 October 2026 passed
Java, configuration, fortified I/O, allocator, Android netdb and nested loader
preflights, then completed the genuine engine's `JNI_OnLoad`. The native loader
now permits recursive constructor loads, retains the outer DSO before its
callbacks, and avoids unconditional per-relocation output. Android resolver
flags and positive EAI errors are translated at the Bionic ABI boundary.
The launcher selects the private Mozilla JKS trust store for WolfJSSE. The
native Vinix HTTPS fixture verifies a genuine Roblox CDN certificate chain and
rejects a local self-signed certificate, with 121 default trusted issuers. The
actual client now passes layout inflation: focus tags restore focus after
child attachment and before `onFinishInflate`, without focusing hidden views.
The captured-pointer listener and window-scoped capture APIs now supply owned
relative motion and button events to the focused view. The real ARM64/Xvfb
fixture checks relative motion beyond screen edges, button/wheel state, focus
loss, reentrant release/reacquire and subsequent normal clicks. Native capture
requires an active X11 window, XI2.1 and a mouse-only seat; unsupported seats and
requests during an existing ordinary input stream safely retain normal input.
Absolute-device recentering and actual Roblox camera input remain unverified.
The production-framework Java event probe passes on Vinix's 16 KiB ART, and
the desktop calculator still displays `579` after `123+456`, with zero retries.
The launcher prevents GTK's GLX fallback with `GDK_DISABLE=glx`, preserving
caller feature flags, so GTK can share ATL's EGL images. The latest real APK
run passes pointer class resolution and `Display.getSupportedRefreshRates()`.
That query returns the existing virtual display's nominal refresh rate; it
does not report a physical monitor mode or prove a rendered frame rate. The
framework now dispatches fragment `onActivityCreated` after the activity's
full `onCreate` override, then start and resume at their framework boundaries.
Queued fragment additions retain their tags and catch up to the host lifecycle
on the real main loop. The native dispatcher pins activity references across
reentrant app callbacks and preserves pending exceptions. A separate fixture APK
passes the production lifecycle assertions on Vinix, including late additions
through the real main-loop handler. The native dispatcher fixture separately
checks reference ownership, reentrancy and exception propagation with JNI doubles.
The real EGL fixture also reads green pixels through ES2, an exported EGLImage
and a GTK texture on Vinix. The actual Roblox run reaches `surfaceCreated` and
`Start the lua app`, then throws `IncompatibleClassChangeError` because its
callback implements `android.webkit.ValueCallback`, which ATL supplies as a
class. No usable client screen or gameplay has been verified.
Host launcher and shared-runtime validation checks are in `tests/roblox/launcher-test.py` and
`tests/roblox/build-test.py`.
