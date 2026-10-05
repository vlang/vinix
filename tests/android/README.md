# Android calculator smoke test

Build the native 16 KiB ART, bionic and coherent ATL overlays as described in
[Android APKs](../../docs/android.md),
then build the Android runtime and sample APK, desktop and kernel:

```sh
./scripts/build-android-aarch64.sh --with-calculator
./scripts/build-desktop-aarch64.sh --no-initramfs
make -C kernel ARCH=aarch64 CC=clang LIMINE_MP=1
python3 tests/android/run.py
```

The test starts a separate Vinix QEMU guest with a private boot disk, EFI
variables, package store and kernel snapshot. It uses the existing Alpine
minirootfs with the Android runtime, X11 and the desktop under test. The test
assembles a compact initramfs and deduplicates library aliases as hardlinks.
It never writes the normal desktop's persistent volume.

The native desktop opens **Android Calculator**. The test waits for the actual
APK's X11 window to draw, clicks its input field, sends `123+456` through QEMU's
keyboard, and requires the APK to display `579`. It waits for the actual input
text to acknowledge each character and bounds retries for dropped key events.
A test-only preload library observes GTK and Pango text calls to verify the
input and result; it leaves the APK and runtime behavior intact.
QMP captures the guest framebuffer as `build/android-smoke/calculator.png`.
`serial.log` retains startup diagnostics and `result.json` records the verdict.
A failed test also attempts to capture the screen.

Useful options:

```sh
python3 tests/android/run.py --desktop /path/to/vinix-desktop \
    --kernel-dir /path/to/kernel --state-dir /tmp/vinix-android-test
python3 tests/android/run.py --apk /path/to/calculator.apk \
    --activity calculator/Calculator --keys '123+456' --expect 579
./scripts/build-desktop-aarch64.sh --compact-initramfs --with-android
python3 tests/android/run.py --initramfs build-support/init-aarch64/initramfs-desktop.tar \
    --memory 12288
python3 tests/android/run.py --boot-probe build/android-native-java/probe/ArtBootProbe.jar \
    --memory 12288
```

`--initramfs` selects another base image, with the test files added as a boot
overlay. Its existing X11 and libraries are retained for production image
verification. `--runtime` selects another staged Android layer; `--runtime-arch
x86_64` compiles the result observer for an x86 runtime translated by QEMU.
`--mode direct` brings up the same APK on the X11 bridge before
desktop integration, sends XTEST keyboard input, and displays its real pixels
on fbdev for a QMP screenshot. The normal desktop test exercises compositor
keyboard forwarding. The host needs `aarch64-linux-musl-gcc` and Python Pillow.
The default runtime is native ARM64; no CPU translator is installed or invoked.
Before launching the APK, the test checks mapped stack bounds, the finite stack
limit, worker stack guards and ART's memory mapping prerequisites in the real
guest. The native fork probe checks Android and host callback ordering, DSO
finalization, child registration and the bounded callback table against the
actual compatibility library. The configuration probe allocates and copies real
ATL configuration objects from actual asset-manager snapshots, checks their
density, locale, SDK and screen qualifiers, and verifies that later asset-manager
updates leave existing snapshots intact. This fixture links the same configuration
object built for libandroid with the verified androidfw provider. The fortified I/O
probe checks actual file, symlink and socket transfers, Android standard-stream
conversion, stream error flags and bounds aborts. Both probe verdicts are
recorded in `result.json`. The legacy `--runtime-arch x86_64` diagnostic option requires
`x86_64-linux-musl-gcc`; `--strace` applies to that translated diagnostic path.
`--click X Y` changes the desktop screen position clicked before typing;
`--focus X Y` changes the APK window position clicked in direct mode.

`--boot-probe JAR` adds an optional Java platform preflight before opening the
APK. Supply a DEX JAR containing [ArtBootProbe](ArtBootProbe.java). The guest
runs it with the private native ARM64 `dalvikvm`, the runtime's stack correction
and ART's interpreter options. The probe requires correct date parsing,
UTC formatting and stream ordering from the real boot libraries. Both a zero
exit status and its `ANDROID-BOOTCLASSPATH-PASS` assertion marker are required.
`serial.log` retains its output; `result.json` records the probe hash and verdict.
Build this fixture with the pinned bootclasspath tools and a JDK on the host:

```sh
python3 build-support/android/art-bootclasspath.py \
    --build-dir build/android-native-java \
    --art-runtime build-aarch64-android/aarch64/art-runtime \
    --build-probe build/android-native-java/probe/ArtBootProbe.jar
```

For bring-up of another APK, capture its actual window and startup diagnostics
without the calculator observer or simulated input:

```sh
python3 tests/android/run.py --apk /path/to/application.apk \
    --activity package/Activity --title package --observe \
    --mode direct --state-dir /tmp/vinix-apk-observation
python3 tests/android/run.py --launcher roblox --apk /path/to/Roblox.apk \
    --observe \
    --mode direct --runtime-arg=-X --runtime-arg=-verbose:jni \
    --state-dir /tmp/vinix-roblox-observation
```

`--observe` requires a drawable APK X11 window to remain mapped for 30 seconds
(`--observation-seconds` changes this duration). It captures `application.png`
and records `observed: true` with `passed: null` in `result.json`; this only
establishes that a window was observed, not that the application's functionality
works. Startup failures retain a screenshot where possible, diagnostic logs
and an explicit failure reason. A proprietary APK must be supplied locally;
the harness does not modify or redistribute it.

`--runtime-arg` passes an additional argument to ATL and can be repeated.
Use `=` for arguments beginning with a hyphen. The JNI verbosity example
records the original native-library load error before a later unresolved JNI
method obscures it. Failure diagnostics retain the first 256 KiB of each
application log, its final 40 lines and the last 80 native-load/exception lines.

`--split-apk /path/to/config.arm64_v8a.apk` supplies an unchanged configuration
APK beside `--apk /path/to/base.apk`. Repeat it for additional splits. The
harness copies each archive separately, records its SHA256 in `result.json`,
and passes it through the normal ATL split option in direct and desktop mode.
It does not merge or re-sign archives. Package and version matching is checked
by the runtime; verify the base and splits' signatures before execution.

`--split-probe /path/to/fixture-directory` first launches a normal fixture APK
with a separate configuration split. It requires base package/version metadata,
split paths through copied `ApplicationInfo`, an asset from the split and a
real JNI library loaded from it. The directory contains
`android-split-probe.apk`, `config.arm64_v8a.apk` and `test-cases.json`, whose
`cases` entries name invalid APKs in `splits` and an expected diagnostic in
`error`. Every rejection must exit with status 1 before application code runs;
an abort or missing pass marker fails the preflight. The result records all
fixture archive hashes and `split_probe_passed` separately from window observation.
The fixture build script is `tests/android/split-test.py`; build it against
the same genuine ATL hax classes as the runtime under test.

`--launcher roblox` validates and stages the production Roblox launchers alongside
its shared native runtime. Direct mode runs `run-roblox`; desktop mode opens the
real **Roblox** entry and supplies the APK through `VINIX_ROBLOX_APK`. Use
`--mode desktop` without `--runtime-arg` to exercise that entry. The Roblox
observation command exercises its Java activity through native ATL/ART. The
regular Roblox desktop entry uses the same native ATL/ART runtime
described in [Roblox APK](../../docs/roblox.md).

## Native loader and HTTPS preflights

Every native ARM64 run checks the actual Bionic resolver's Android flags,
positive EAI error codes, address layout, scoped IPv6, 64-bit reverse-lookup
bounds and freeing returned lists. These numeric-address checks need no network.
`--linker-diagnostics` enables bounded loader phase, relocation progress and
constructor diagnostics; normal library loading stays quiet.

`--loader-probe DIR` also runs a native `loader-test` executable and
`packed-relocation-probe.so` built from [bionic-loader-test.c](bionic-loader-test.c)
against the pinned Bionic sources. Compile the payload with
`-DBIONIC_LOADER_PAYLOAD -shared -fPIC -nostdlib -Wl,--pack-dyn-relocs=android`
and `-Wl,-z,max-page-size=65536` using Clang/LLD. Link the executable with the
pinned `main_executable/bionic_compat.c` and `-ldl`; it needs the real Android
TLS bootstrap. The constructor opens and closes itself, then loads libc,
resolves and calls its page-size query and closes it. The fixture proves packed
relocation and recursive loader lifetimes inside Vinix.

`--tls-probe /path/to/android-tls-probe.jar` runs
[AndroidTlsProbe.java](AndroidTlsProbe.java) before the APK. Compile it with
Java 8, then convert its class files with the pinned D8 8.3.37 and `--min-api 26`.
The guest waits for DHCP's resolver configuration and selects the same private
JKS file as the launcher. It requires nonempty default trusted issuers, rejects
a local self-signed certificate, and requests the genuine
`https://clientsettingscdn.roblox.com/` endpoint with chain and hostname
verification. The endpoint's normal HTTP error response still proves TLS;
no authentication or APK change is involved. Each optional preflight requires
zero exit status plus its assertion marker. Results record fixture hashes and
verdicts; neither preflight establishes gameplay.

`--layout-probe /path/to/android-layout-focus-probe.jar` checks the actual
framework's inflater and default-focus dispatch before the APK. Build it on
the native framework build host with [layout-focus-test.py](layout-focus-test.py):

```sh
python3 tests/android/layout-focus-test.py \
    --framework-classes /path/to/atl/output/src/api-impl/hax.jar \
    --stub-classes /path/to/atl/output/src/gstub/gstub.jar \
    --r8 /path/to/r8-8.3.37.jar --output /path/to/android-layout-focus-probe.jar
```

The fixture uses observing ViewGroups without GTK constructors and a separate
logging adapter. The real inflater, default-focus delegate and hidden-view gate
run unchanged. Assertions cover tag order, attached children, nested parents,
metadata subtree consumption, repeated tags, hidden views and merge roots.
Fixture classes are used only in a separate preflight VM; they never enter the
runtime overlay or APK. A zero exit status and assertion marker are required,
and `result.json` records its hash and verdict.

`--lifecycle-probe /path/to/android-activity-lifecycle-probe.apk` runs
[AndroidActivityLifecycleProbe.java](AndroidActivityLifecycleProbe.java) against
the production activity and fragment dispatcher through ATL's real application
bootstrap, on a separate X11 display in Vinix.
The guest requires zero exit status and its assertion marker, and records the
probe hash and verdict. The test APK contains only fixture classes and its own
manifest/resources. It leaves the application's APK and runtime providers intact.

Build the fixture against the same coherently built ATL framework and resources
using [activity-lifecycle-test.py](activity-lifecycle-test.py):

```sh
python3 tests/android/activity-lifecycle-test.py \
    --framework-classes /path/to/atl/output/src/api-impl/hax.jar \
    --framework-res /path/to/atl/output/res/framework-res/framework-res.apk \
    --core-classes /path/to/core-all_classes.jar \
    --r8 /path/to/r8-8.3.37.jar --output /path/to/lifecycle-probe
```

The builder pins the core classes and D8 compiler, rejects extra provider
classes, and records input/output hashes in `lifecycle-probe-build.json`.
The Java fixture checks lifecycle callbacks after complete activity overrides,
queued transaction catchup through the real main Handler, reentrant destruction,
and exception propagation. Its controlled cases bypass activity constructors;
the late-commit case runs in a normally constructed ATL activity.

[run-activity-dispatch-test.sh](run-activity-dispatch-test.sh) separately compiles
the verified production C dispatcher unchanged on native Linux:

```sh
tests/android/run-activity-dispatch-test.sh \
    /path/to/atl/src/api-impl-jni/app/android_app_Activity.c
```

It requires GTK 4.10 or newer, libportal development packages, and JDK JNI
headers (`ATL_JNI_INCLUDE` may select the header directory). Checked JNI doubles
exercise finishing during start or pause, callback exceptions, reentrant activity starts,
reference-allocation failures, and method-lookup failure. They reject deleted
handles and mismatched local/global deletion. The `pins=0` verdict counts explicit
dispatcher pins; class locals released by JNI at native return are excluded.
This C test does not run ART or establish application gameplay.

`--cookie-probe /path/to/android-cookie-probe.apk` runs
[AndroidCookieProbe.java](AndroidCookieProbe.java) through the normal ATL
application loader in two separate processes. The bootstrap activity checks the
installed public cookie APIs, then flushes test cookies. The persistence activity
reloads the same APK's private cookie store and checks session cookies, secure
and HttpOnly cookies, domain matching, and distinct paths for the same name.
Both processes must exit zero and print their respective `ANDROID-COOKIE-PASS`
and `ANDROID-COOKIE-RELOAD-PASS` markers.

Build it against the coherently built production framework and resources:

```sh
python3 tests/android/cookie-test.py \
    --framework-classes /path/to/atl/output/src/api-impl/hax.jar \
    --framework-res /path/to/atl/output/res/framework-res/framework-res.apk \
    --core-classes /path/to/core-all_classes.jar \
    --r8 /path/to/r8-8.3.37.jar --output /path/to/cookie-probe
```

The builder pins core classes and D8, packages only probe classes and their own
manifest, and records input/output hashes in `cookie-probe-build.json`.
Callbacks must be deferred, run exactly once on the caller's main or worker
Looper, and report unchanged valid cookies as accepted. A plain worker without
a Looper can use a null callback; a nonnull callback must be rejected before
mutating the store. Matching checks cover host-only cookies, domains, paths,
secure transport, HttpOnly visibility, expiry, deletion, public suffix rejection,
and cookie prefixes. A supplementary Unicode value must survive the Java/native
boundary and reload. Test names use `vinix_test_`; host fixtures use `.invalid`
and the public-suffix check uses `co.uk`. No network request is made.
The fixture APK never changes application APKs, framework providers, or real
authentication cookies. It does not establish WebView sharing or gameplay.

[run-cookie-store-test.sh](run-cookie-store-test.sh) separately compiles the
verified production cookie backend with real libsoup and SQLite on ARM64 Linux:

```sh
tests/android/run-cookie-store-test.sh \
    /path/to/atl/src/api-impl-jni/widgets/android_webkit_CookieManager.c
```

It requires libsoup 3 and SQLite development packages and JDK JNI headers
(`ATL_COOKIE_JNI_ROOT` may select the header directory). The fixture checks
provider acceptance and matching, session and persistent-cookie reload,
independent paths, saved security and expiry attributes, and checked rollback
when a real second SQLite connection blocks commit. A delayed insertion still
calls real libsoup and checks expiry at the acceptance snapshot boundary.
Corrupt rows must reject initialization without publishing an empty store.
The fixture uses a temporary private directory and does not run ART or
establish gameplay.

`--egl-probe /path/to/egl-interop-test` runs
[egl-interop-test.c](egl-interop-test.c) on the APK's actual X11 display, using
the installed private Mesa and GTK libraries. Build the executable on ARM64
Linux with the matching development libraries:

```sh
cc -O2 -Wall -Wextra -Werror -Wl,-z,max-page-size=65536 \
    tests/android/egl-interop-test.c \
    $(pkg-config --cflags --libs gtk4 egl glesv2) -o /path/to/egl-interop-test
```

It requires real green pixel readback from an ES2 framebuffer, transfers an
EGLImage into a separate GDK GLES context, and verifies the downloaded GTK
texture pixels. It runs on a separate private X11 display before launching
the application. The guest requires zero exit status plus `ANDROID-EGL-PASS`;
results record the executable hash and verdict. This checks the rendering
dependency path, and does not establish that Roblox draws or accepts input.

## Disabled Autofill preflight

`--autofill-probe /path/to/android-autofill-probe.apk` runs
[AndroidAutofillProbe.java](AndroidAutofillProbe.java) through the normal ATL
application loader with the production typed system service. The fixture checks
that the platform reports no Autofill feature, focuses a real EditText, and calls
`cancel()`, `requestAutofill(View)` and `notifyValueChanged(View)` repeatedly on
the main thread and a worker without a Looper. A later main Handler callback
checks that input text is preserved and the feature remains disabled.
The same fixture verifies View hint metadata: ordered values, null and empty
arrays, unfiltered elements, the Android 26 shared-array behavior of the setter
and getter, and independent properties on separate views. Manager calls preserve
that metadata while the platform still reports no Autofill feature.

Build the fixture on the native framework host with the coherent production
class archive and resource APK:

```sh
python3 tests/android/autofill-test.py \
    --framework-classes /path/to/atl/output/src/api-impl/hax.jar \
    --framework-res /path/to/atl/output/res/framework-res/framework-res.apk \
    --core-classes /path/to/core-all_classes.jar --r8 /path/to/r8-8.3.37.jar \
    --output /tmp/android-autofill-probe
```

The helper pins the core and R8 inputs and packages only fixture classes in the
normal APK. It adds no framework providers. The guest runs this preflight on
private display `:94` before starting the application and requires the actual
APK child to exit zero plus an anchored `ANDROID-AUTOFILL-PASS` marker. Results
record the fixture hash and preflight verdict separately from application
functionality. This verifies Android's no-service behavior; an enabled Autofill
service and Roblox gameplay require separate support and checks.

## Unavailable Location providers preflight

`--location-probe /path/to/android-location-probe.apk` runs
[AndroidLocationProbe.java](AndroidLocationProbe.java) as a normal APK against the
production typed location service. It checks that `isProviderEnabled(String)`
returns false for GPS, network and unknown names, rejects null with
`IllegalArgumentException`, and preserves ATL's empty provider lists and absent
last-known location. Repeated worker queries require no Looper; a main Handler
continuation checks that the queries leave the event loop usable.

Build it with the coherent production class archive and resource APK:

```sh
python3 tests/android/location-test.py \
    --framework-classes /path/to/atl/output/src/api-impl/hax.jar \
    --framework-res /path/to/atl/output/framework-res.apk \
    --core-classes /path/to/core-all_classes.jar --r8 /path/to/r8-8.3.37.jar \
    --output /tmp/android-location-probe
```

The helper pins core and R8 and includes only fixture classes. The guest runs it
on private display `:93` before the application, requires the actual APK child
to exit zero plus an anchored `ANDROID-LOCATION-PASS` marker, then emits
`ANDROID-LOCATION-VERIFIED`. Results record its unchanged APK hash and verdict.
The same APK on the preceding runtime must fail at the missing
`isProviderEnabled(String)` method. This checks provider availability metadata;
it creates no location provider or position and does not establish gameplay.

## Pointer capture preflights

`--pointer-probe /path/to/android-pointer-capture-probe.jar` runs
[AndroidPointerCaptureProbe.java](AndroidPointerCaptureProbe.java) in a separate
Vinix ART VM against the installed production framework. Build the probe on the
native framework host with [pointer-capture-test.py](pointer-capture-test.py),
using the same `--framework-classes`, `--stub-classes` and `--r8` inputs as the
layout probe above. It checks listener ordering, fallback, exception propagation,
relative axes, button metadata, copied event ownership and pooled event reset.
Only capture state is a test double; actual capture is checked separately.
The guest requires zero exit status and its assertion marker, and records the
probe hash and verdict. Fixture classes never enter the runtime overlay or APK.

[atl-pointer-capture-test.c](atl-pointer-capture-test.c) links the patched native
helper and drives a real X11 server using XTest:

```sh
gcc -O2 -Wall -Wextra -Werror -Wno-deprecated-declarations \
    -I/path/to/atl/src/api-impl-jni/views \
    tests/android/atl-pointer-capture-test.c \
    /path/to/atl/src/api-impl-jni/views/PointerCapture.c \
    $(pkg-config --cflags --libs gtk4 x11 xi xtst) -lm -o /tmp/atl-pointer-test
DISPLAY=:99 GDK_BACKEND=x11 GSK_RENDERER=cairo /tmp/atl-pointer-test
```

Use a dedicated X server, such as Xvfb, at the selected display. The fixture
checks unheld capture, refusal during an ordinary held click, motion beyond
screen edges, button/wheel state, focused-view routing, requester removal,
reentrant release/reacquire, focus loss, cursor restoration and subsequent
normal clicks. It exercises a relative XTest device; absolute-device recentering
and real gameplay require separate checks in Vinix.

## Production EGL buffer queue regression

`AndroidEglQueueProbe.java` and `android-egl-queue-probe.c` form an ordinary APK
with a public `SurfaceView` and a JNI render worker. The worker uses production
`ANativeWindow`, EGL and GLES entrypoints. A finite main-thread pause delays GTK
consumption, exhausts the three-buffer queue and requires a bounded failed swap
with `EGL_BAD_ALLOC`. The fixture checks that the actual framebuffer binding and
existing green pixel survive both the failed swap and a default-framebuffer bind.
The UI thread checks its independent EGL error state before the worker consumes
and clears its error. Resuming GTK must recycle buffers for 32 further swaps;
normal window/EGL cleanup also runs with submitted callbacks still pending.

Build against the selected runtime's coherent framework classes and resources
on native ARM64 Alpine Linux:

```sh
python3 tests/android/egl-queue-test.py \
    --framework-classes /path/to/atl/output/src/api-impl/hax.jar \
    --framework-res /path/to/atl/res/framework-res/framework-res.apk \
    --core-classes /usr/lib/java/core-all_classes.jar \
    --r8 /path/to/r8-8.3.37.jar --jni-include /path/to/java8/include \
    --output /tmp/egl-queue-fixture
```

The small ARM64 JNI library imports public platform APIs without host-library
`DT_NEEDED` entries. The builder checks its ELF architecture and 16 KiB load
alignment, pins the DEX compiler inputs, restricts packaged classes to the test
app, and records exact source, runtime-input and APK hashes.

Pass `--egl-queue-probe /tmp/egl-queue-fixture/android-egl-queue-probe.apk` to
`tests/android/run.py` alongside the normal native preflights. The guest uses a
private X display `:92` after the common preflights, records the numeric child
exit in `ANDROID-EGL-QUEUE-CHILD`, and accepts the probe only after the child
exits zero and emits an anchored `ANDROID-EGL-QUEUE-PASS` line. The host requires
the resulting `ANDROID-EGL-QUEUE-VERIFIED` line and records fixture identity,
status and `egl_queue_probe_exit_status`. Run the same APK on the old and new
runtime for a decisive control;
the new-runtime fixture passing does not by itself establish Roblox gameplay.

## Interactive Roblox session

After staging the native Android runtime and Roblox launcher, keep the real
desktop window open for a local user to sign in:

```sh
python3 tests/android/run.py --launcher roblox --apk /path/to/Roblox.apk \
    --observe --mode desktop --interactive \
    --state-dir /tmp/vinix-roblox-interactive
```

Supply `--runtime`, `--roblox-staging`, `--desktop`, `--kernel-dir` and
`--initramfs` when using separately built inputs. On macOS this opens QEMU's
Cocoa window. The supervisor continues draining the serial console until
Ctrl-C or the QEMU window is closed; it stays attached for the whole session.
`--timeout` does not end an interactive session; `--startup-timeout` still
bounds the guest's initial window check. Its state directory is private
(mode 0700), including when an existing session directory is reused.
`--interactive` requires `--observe --mode desktop` and retains the normal
native runtime preflights and X11 window check. Its guest does not open a
second console shell, so the desktop keeps receiving keyboard input.
The desktop's Terminal icon is available for explicit local diagnostics.
The minimal test image includes zsh and its modules from the staged userland;
a supplied `--initramfs` keeps its existing shell.

This mode does not send keys, load the calculator text observer, capture any
screenshots, or copy application diagnostic logs to the host, including on
failure and shutdown. The local user signs in through the QEMU window.
`serial.log` contains the guest's preflight and status output. After stopping,
`result.json` records `check: "interactive-observation"`, `passed: null` and
`functionality: "unchecked"`; an observed login window is not gameplay proof.

Once the user confirms that sign-in is finished and an experience is open,
capture a frame explicitly through the session's local QMP socket:

```sh
python3 - <<'PY'
import importlib.util
from pathlib import Path
spec = importlib.util.spec_from_file_location("android_test", "tests/android/run.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
state = Path("/tmp/vinix-roblox-interactive")
module.screenshot(state / "qmp.sock", state / "gameplay-before.png")
PY
```

The explicit capture command needs Python Pillow. Use the actual frame size
and choose control coordinates from that frame. These examples assume a
1024×768 desktop: a left-button drag holds the mobile movement control,
a click presses jump, and a drag on an empty part of the world moves the
mobile camera. Replace the example coordinates with the visible controls:

```sh
python3 desktop/tools/input.py --socket /tmp/vinix-roblox-interactive/qmp.sock \
    --size 1024x768 --settle 1 drag 140 650 140 570
python3 desktop/tools/input.py --socket /tmp/vinix-roblox-interactive/qmp.sock \
    --size 1024x768 click 900 650
python3 desktop/tools/input.py --socket /tmp/vinix-roblox-interactive/qmp.sock \
    --size 1024x768 drag 750 350 650 350
```

These gestures exercise the production desktop pointer bridge. Capture
separate before/after frames for movement, jump and camera changes, verify
that they show a joined experience and an avatar reacting to input, and
check that leaving and rejoining works. Pixel changes alone can also come
from a loading screen and do not establish gameplay. Keyboard holding is a
separate check: the desktop currently forwards text, and its Roblox host
deliberately taps each character to support login fields. QMP down/up events
therefore do not establish held WASD behavior through this bridge.

Host lifecycle checks use a real PTY and a mock VM process, without booting:

```sh
python3 tests/android/interactive-test.py
```
