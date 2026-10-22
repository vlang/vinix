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
hold a native reference until the last unlock. OpenSL ES uses the runtime's
packaged audio provider. This is a limited NDK subset, not compatibility with
arbitrary native APK libraries.

`libnativewindow.so` maps to a CPU surface producer in this backend. SurfaceView
layout notifies its holder callbacks; acquired NDK windows retain their buffer
queue, and Java Surfaces retain their owning view. RGBA locks expose real pixel
storage, expand the dirty rectangle to the full buffer, and post through the WS
compositor. CPU-only, single-layer RGBA hardware buffers support reference
counting, description and balanced locks; GPU usages and external fences fail.
NDK one-shot frame callbacks run on the WS main Looper with monotonic timestamps.
Secondary NDK Loopers, refresh-rate notifications and SurfaceHolder Canvas
locking are not implemented.
Window refresh-rate preferences are retained as Java attributes; the native
compositor does not currently select display modes from these hints.

Handle-based JNI symbol lookup searches the library and its dependencies in
breadth-first order, including defined weak symbols. The bootstrap APK includes
a JNI method exported only by a dependent DSO to exercise this path in ART.

The loader resolves ARM64 dynamic TLS and TLSDESC relocations using the
defining library's TLS offsets. Per-thread blocks copy initialized data, zero
BSS and honor alignment; the vector grows after later library loads. Thread
exit frees those blocks, and library unload releases descriptor arguments.
The TLSDESC entry preserves integer and SIMD registers and returns an offset
from the host thread pointer. Undefined weak TLS addresses resolve to null.
Initial-exec TLS is rejected because static TLS allocation is not implemented.
The bootstrap fixture checks real compiler-generated descriptors across two
libraries and eight worker threads (`BOOTSTRAP-TLSDESC-PASS`).

Pinned Mesa GLES dispatch libraries and a surfaceless EGL provider run software
GLES through Gallium softpipe. EGL windows render to pbuffers and post flipped
RGBA pixels through the native WS buffer queue; X11, GTK and Wayland are absent.
The Java EGL10 bridge handles displays, configurations, contexts, surfaces and
current-thread queries. Java GL10 and GLES20 string queries use the current
renderer, and GLES20 error queries consume its actual error state. GLES20 integer
queries copy renderer state into Java arrays or heap/direct IntBuffers, respect
positions and limits, and reject undersized or read-only output. Variable format
lists use the renderer's advertised element count.
Java GLES20 scalar state, object and uniform calls use the same renderer. Shader
source, compilation, linking, locations, status and compiler logs come from Mesa;
the regression APK checks valid and invalid shaders, array offsets and object
lifetimes through the Java APIs.
Buffer and texture uploads accept heap and direct NIO storage with byte-range
validation and preserve Java buffer cursors. Heap storage is copied and unpinned
before calling Mesa. ReadPixels copies results back to writable buffers;
integer vertex and index offsets address bound GL buffers. The fixture checks
an indexed triangle and a texture subimage through actual pixel readback.
Client-memory vertex arrays are not implemented by these offset overloads.
Destruction retains a current window until every thread
unbinds it. Readback preserves framebuffer and ES3 pixel-pack state. CPU and EGL
producers cannot own the same window simultaneously.

The backing pbuffer retains its creation dimensions; a resized WS view scales
that buffer until the app recreates its EGL surface. Pixmaps, native fences,
external images, Vulkan, AR and video contexts remain unavailable. This is a
CPU renderer; no GPU acceleration is selected. The V build packages the pinned
software DRI closure, verifies its ELF dependencies, and retains upstream
sources, notices and a SHA256 receipt. The regression APK checks shader output,
window presentation, thread isolation, deferred destruction and Java array
validation; these checks alone do not establish compatibility with Maps.
View drawing preserves the destination Canvas through backgrounds and child
views, including bitmap targets used by the window composition regression.

Application attachment precedes main-process content providers (descending
`initOrder`), then `Application.onCreate`, then Activity construction. Disabled
providers and providers assigned to another process are not instantiated.
ApplicationInfo and PackageManager share the actual APK, data and native library
paths. Elapsed realtime uses the boot clock in the API's requested units.
Current-thread CPU clocks use the kernel's thread clock in milliseconds or
microseconds, excluding time spent asleep.
View layout direction inherits from ancestors on demand. WebP images decode
through the runtime's libwebp alongside the existing bitmap decoders.
Matrix rotation/scaling supports pivots and overlap-safe point mapping; rounded
paths retain independent corner radii. Network availability reads the guest's
configured non-loopback interfaces. Connectivity callbacks poll that state on
their Handler, filter requests against capability snapshots, and report link
arrival, changes and loss. Unregistering cancels queued and future delivery,
including when called inside a callback. Internet capability requires a kernel
default route; validation and unmetered access are not advertised. Link snapshots
include the interface name, MTU and addresses. Local ContentProviderClient handles resolve
registered authorities, dispatch type/call operations and release their provider
reference on close. Uninstalled service providers return null.
ART receives the private runtime's generated JKS path, type and password before
WolfJSSE creates its default SSLContext. Native builds also carry `cacerts` into
the APK suite's staged runtime, including when its baseline image is older.
`tests/native-android-ws/https-fixture.v` builds a separate network regression
APK from an existing bootstrap fixture directory. Its arguments are `OUTPUT
FIXTURE_DIR SMALI_TOOLS JAVA APKSIGNER`. Run it as `org.vinix.bootstrap` with at
least 100 startup seconds and Internet access. `HTTPS-FIXTURE-PASS` requires a
verified HTTPS response from Google and certificate failures for both
`self-signed.badssl.com` and `wrong.host.badssl.com`; socket timeouts do not count
as certificate rejection. The probe leaves the default trust manager and
hostname verifier intact. TCP diagnostics separately expose unreachable routes.
Account listeners retain their registrations and deliver an empty snapshot on
the requested Handler (or the main Looper). Duplicate registrations fail and
removal permits registration again. Vinix has no account authenticator.
External-storage path queries validate the runtime's ordinary, non-removable
directory. Process CPU time reads the kernel's process CPU clock.
BatteryManager is available through both Context service lookup forms. With
no battery driver, properties return Android's unsupported sentinels (including
the older target-SDK integer behavior), charging is false and the remaining
charge-time estimate is unavailable.

AssetManager directory enumeration uses the merged framework and APK assets.
Asset file descriptors expose stored APK entries through the provider's real
backing descriptor, offset and length; compressed or missing entries fail with
FileNotFoundException. Each descriptor owns its duplicate until closed.
The build converts the pinned runtime's IANA TZif files and aliases into
Android's indexed tzdata container, preserving transition records. The launcher
sets Android's root/data paths so libcore finds it. Guest regression checks
cover UTC, northern and southern daylight saving, and fractional-hour offsets.

Bitmap-backed Canvas instances own independent pixel targets and save/restore
stacks. Scoped thread-local selection keeps offscreen drawing separate from
the WS framebuffer; native references keep the bitmap storage alive. Pixel
array reads/writes, cropped blits, paint alpha and cubic/quadratic vector paths
use the same CPU renderer. Canvas matrix concatenation currently accepts
translation and scaling; rotation, skew and perspective remain unsupported.

Plain Android notifications post to the native Vinix session broker and cancel
by Android ID. The broker authenticates the posting PID and permits withdrawal
only of that process's keyed notices. The runtime requires an available broker
and reports service failures. PendingIntent actions and media notifications
remain unsupported. The bootstrap APK exercises real posting/cancellation as
well as bitmap pixels, Canvas target isolation and save/restore in a Vinix VM.

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
`VINIX_ANDROID_TRACE_THREADS` logs Java thread stacks every 30 seconds for the
first five minutes, including before the main Looper starts. Its diagnostic
worker attaches as an ART daemon and keeps a separate JNI environment.
`VINIX_ANDROID_TRACE_TLS=1` enables WolfJSSE and wolfJNI diagnostics before
the VM initializes its TLS provider, plus Java logging at FINE level to expose
connection errors that clients catch internally.
Uncaught Java exceptions are printed before the app's crash handler runs;
the app's handler still receives the exception. Thread tracing also records
VM-requested exits with their Java stacks.
With tree tracing enabled, `VINIX_ANDROID_TRACE_SURFACE_DUMP` selects an
application SurfaceView diagnostic method with a `(String, PrintWriter)`
signature. At most three calls report the application's own surface state;
production launchers leave this unset.

Single-pointer WS input enters `dispatchTouchEvent` at the window root.
ViewGroups retain the consuming child for the gesture, translate local
coordinates, preserve raw coordinates/downTime and deliver cancellation when
intercepted. Passive overlays fall through to lower children. The guest
bootstrap fixture checks capture outside bounds, interception/disallow,
cancellation, disabled controls and click delivery. Multitouch splitting,
transformed hit testing and long-press gestures remain incomplete.
WS Enter dispatches TextView editor actions, preserving IME options and flags.
Explicit actions such as Search and Done call the registered listener with a
null KeyEvent; ordinary Enter uses IME_NULL and KEYCODE_ENTER. Unconsumed Enter
inserts a newline only for multiline editors. The bootstrap regression covers
EditText's native listener registration, action dispatch, no-enter-action flags,
hardware Enter consumption and listener removal. Default Next/Done focus
navigation and on-screen keyboard control remain incomplete.
`Window.isFloating()` resolves `windowIsFloating` from the window context's
theme. The guest regression checks both activity and dialog themes.

The verified subset covers Arity calculation, Editor save/reopen and Open
Sudoku touch entry/database persistence. Advanced Canvas paths/transforms,
text selection/shaping, on-screen keyboards, drag scrolling, popup tabs, services and
modern Android APIs remain incomplete. NinePatch images currently stretch.
WebView supports static HTML/text help panels without JavaScript, CSS layout
or network navigation. Unsupported native APIs fail explicitly. This backend
does not establish general APK compatibility or phone hardware support.

TextView measurement and painting wrap at word boundaries, honor line limits
and gravity, and preserve explicit single-line controls. `Html.fromHtml` decodes
text/entities and retains anchor URL spans with UTF-16 offsets; rich font styling
and link interaction remain incomplete. No-title themes keep their app-owned
toolbar without a second runtime header. An image selecting another APK may
write its label (up to 128 bytes, without a newline) to
`/usr/share/vinix/android-app-label` for the outer title bar and taskbar.

`Resources.getFont` loads bundled TTF files and the first font in an XML family.
Paint, text layouts and TextView retain their native font while it is in use,
including across Paint copies. Provider families with a system fallback use
the backend's default font; remote font downloads, weight selection and shaping
remain incomplete. SensorManager reports an empty device list and rejects
registration because this backend has no sensor driver. Its barometric altitude
calculation works on supplied pressure values without requiring a device.
PowerManager reports the guest's current policy: no thermal throttling, device
idle or location power saving. Thermal listeners receive this initial policy on
their Executor or the main Handler; duplicate registrations and missing removals
fail. Vinix has no temperature driver or thermal feedback loop, so this status
does not measure physical device temperature or provide overheating protection.
Vibrator reports no motor or amplitude control. Haptic requests and cancellation
have no effect; they do not call a missing driver or spawn pattern threads.
MediaRouter shares one disabled default route between service instances. It
advertises no supported media types and no presentation display; callback
registration does not invent output devices. Remote and app-provided routes
remain unimplemented.

Dynamic receivers support the registration overloads with flags and handlers,
main-Looper delivery by default, action and package filtering, and unregistering.
Delivery currently covers broadcasts sent inside the app process. Sticky system
broadcasts, cross-process delivery and full IntentFilter data matching remain
incomplete.

AppOps validates the current APK package against the real Unix process UID.
It permits the existing external-storage operations and reports unavailable
location, phone, camera, microphone and sensor operations as ignored. Operations
without a policy return the default mode for the caller's permission check;
cross-process AppOps auditing is not implemented.

URI delegation checks return permission denied because no Binder URI-grant
service is connected. Ordinary access to a local provider is separate; these
checks do not grant other processes access to it.

AtomicFile writes a sibling `.new` file, syncs and closes it, then replaces the
base file with a filesystem rename. Failed writes preserve the committed copy;
reads recover legacy `.bak` files and discard interrupted replacements. Callers
must serialize access. TrafficStats retains tags separately for each thread;
per-UID byte counters return `UNSUPPORTED` because Vinix does not account for
traffic by UID. Tags are not yet attached to kernel sockets.

The native loader checks mapped extents rather than adding page-rounded segment
lengths. Shared PT_LOAD pages therefore do not falsely exceed the reserved
mapping, while out-of-range and overflowing extents still fail validation.
Libraries aligned to 4 KiB use an anonymous copy mapping when their file and
virtual offsets cannot share a 16 KiB file mapping. The mapper preserves BSS
and adjacent segment bytes, flushes executable code, and protects complete
RELRO pages after relocation. A host page shared by executable and writable
segments needs their combined permissions, including RWX in that case.

CheckBox and RadioButton retain checked state, deliver change listeners and
toggle through Android clicks. Native wheel input scrolls the nearest scrollable
ancestor through its Java scroll methods. Rendering and hit testing account for
scroll offsets in custom ViewGroups, including AndroidX NestedScrollView.
ProgressBar exposes determinate progress and animates visible indeterminate
indicators. App-supplied button backgrounds are drawn without a generic button
fill covering them. The bootstrap fixture's NDK library intentionally uses
4 KiB ELF alignment to exercise executable copy mapping in a 16 KiB guest.

The [popular-app startup matrix](../../../tests/android/results/2026-10-21/popular-ws/README.md)
records baseline blockers for eleven widely installed Play app identities,
including application initialization, resources, JNI clocks, launcher resolution
and split delivery. None reached a usable UI in that run; the basic APK checks
above should not be extrapolated to those applications.

`tests/native-android-ws/bootstrap-fixture.v` builds a separate signed regression
APK from smali and V. It checks provider ordering and filtering, startup paths,
clock units, 64-bit process reporting, real NDK asset reads/seeks, inherited
layout direction and lossless WebP decoding. It also checks pivot rotation, live
network detection, provider-client lookup, actual NDK bitmap metadata and pixels,
balanced nested locks, graphics procedure lookup and software EGL rendering.
Pass its APK to the native WS suite; the assertion marker is `BOOTSTRAP-NDK-PASS`.
This fixture does not modify or stand in for the publisher's WhatsApp APK.

The subsequent [WhatsApp probe](../../../tests/android/results/2026-10-21/whatsapp-ws/README.md)
records its welcome screen, scrolling and language selection on native WS.
Account registration, messaging and calls remain untested.
