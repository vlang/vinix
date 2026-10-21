# Android on native Vinix WS

This V backend runs unchanged APK DEX through ARM64 ART and presents directly
to the desktop's native surface protocol. `desktop/android_app.v` starts it
with a VSF1 double-buffered XRGB surface and a VNI1 input pipe. The desktop owns
the sole title bar and close controls. No X server or GTK display backend is
started.

`runtime.v` creates the real ART VM, loads the extended ATL framework DEX,
registers the reusable V framework APIs, and runs Android lifecycle callbacks
and the main Looper. Secondary Loopers have wakeable native queues. Resources
use the existing toolkit-independent `libandroidfw` ABI. SQLite connections,
statements, cursor windows and ICU collations use real database providers.

Android's Java view trees retain layout, listeners and application state.
Native widgets and Canvas rasterize text, rectangles, lines, simple paths and
bitmaps into WS pixels. Dialogs compose another Java view tree within the same
surface. Keyboard edits notify real TextWatchers; pointer events reach Android
MotionEvent handlers and adapter row callbacks. Closing the WS input pipe
delivers pause, stop and destroy callbacks before the process exits.

`bindings.txt` explicitly selects implemented native methods. The build reads
their descriptors from the extended framework's smali and generates exact JNI
wrappers, including overload suffixes and UTF-16 name mangling. An absent API
remains a linkage failure. The historical Java class name `GskCanvas` is an ABI
detail: its invoked native methods are implemented here in V without GSK.

The private `wsloader` library builds the pinned upstream Bionic linker with
an optional V symbol lookup that does not load EGL or X11. The launcher installs
the APK's ARM64 native libraries in an atomic, content-hashed directory and
passes that directory to ART and Bionic. Its private library mapping routes
`libandroid.so` asset operations to this backend's existing `libandroidfw`
provider and `libjnigraphics.so` bitmap access to the WS CPU pixels. Pixel locks
hold a native reference until the last unlock. GLES rendering remains unsupported
and fails explicitly. This is a limited NDK subset, not compatibility with
arbitrary native APK libraries.

Application attachment precedes main-process content providers (descending
`initOrder`), then `Application.onCreate`, then Activity construction. Disabled
providers and providers assigned to another process are not instantiated.
ApplicationInfo and PackageManager share the actual APK, data and native library
paths. Elapsed realtime uses the boot clock in the API's requested units.
View layout direction inherits from ancestors on demand. WebP images decode
through the runtime's libwebp alongside the existing bitmap decoders.
Matrix rotation/scaling supports pivots and overlap-safe point mapping; rounded
paths retain independent corner radii. Network availability reads the guest's
configured non-loopback interfaces. Local ContentProviderClient handles resolve
registered authorities, dispatch type/call operations and release their provider
reference on close. Uninstalled service providers return null.

The normal ATL build assembles this backend and hashes its output with the
framework. Runtime staging installs the native executable as `run-android`.
For an isolated build against an existing private runtime:

```sh
build-support/android/native-tool extend-framework original-api-impl.jar \
  build/android-ws/api-impl.jar --work build/android-ws/framework
build-support/android/native-tool compile-native-ws \
  build/android-ws/framework/smali /path/to/private-runtime build/android-ws
build-support/run-v-tool.sh tests/native-android-tools/check-native-ws.v
```

The host needs V (including its stb headers), a musl ARM64 compiler, SQLite
headers and Java for framework assembly. The resource ABI header is fetched
from a pinned upstream commit and verified by SHA256. The builder uses the
staged `libandroidfw`, PNG and SQLite libraries and compiles JNI with
`-Wall -Wextra -Werror` and 64 KiB ELF alignment. Bionic source and header
downloads are pinned and hashed; the staged receipt and NOTICE record their
provenance. The guest also needs libwebp.so.7 and libunwind.so.8.

The launcher requires `VINIX_SURFACE_PATH` and the inherited WS input pipe;
dimensions default to 480 by 640 and can be supplied through
`VINIX_SURFACE_WIDTH`/`HEIGHT` or `-w`/`-h`. `-l` selects a slash-separated
activity name. `ANDROID_APP_DATA_DIR` overrides the per-APK directory under
`$XDG_DATA_HOME/vinix/android`. `VINIX_ANDROID_TRACE_TEXT` and
`VINIX_ANDROID_TRACE_TREE` enable test-only diagnostic logging of app content.

The verified subset covers Arity calculation, Editor save/reopen and Open
Sudoku touch entry/database persistence. Advanced Canvas paths/transforms,
text selection/shaping, on-screen keyboards, mouse wheel/drag scrolling, popup tabs, services and
modern Android APIs remain incomplete. NinePatch images currently stretch.
WebView supports static HTML/text help panels without JavaScript, CSS layout
or network navigation. Unsupported native APIs fail explicitly. This backend
does not establish general APK compatibility or phone hardware support.

The [popular-app startup matrix](../../../tests/android/results/2026-10-21/popular-ws/README.md)
records the current blockers for eleven widely installed Play app identities,
including application initialization, resources, JNI clocks, launcher resolution
and split delivery. None reached a usable UI in that run; the basic APK checks
above should not be extrapolated to those applications.

`tests/native-android-ws/bootstrap-fixture.v` builds a separate signed regression
APK from smali and V. It checks provider ordering and filtering, startup paths,
clock units, 64-bit process reporting, real NDK asset reads/seeks, inherited
layout direction and lossless WebP decoding. It also checks pivot rotation, live
network detection, provider-client lookup and
actual NDK bitmap metadata, pixels and balanced nested locks.
Pass its APK to the native WS suite; the assertion marker is `BOOTSTRAP-NDK-PASS`.
This fixture does not modify or
stand in for the publisher's WhatsApp APK.
