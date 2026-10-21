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

The private `wsloader` library supplies ART's Linux JNI loading ABI. It avoids
the packaged Bionic bridge's EGL/X11 dependency. This supports the tested Java
APKs and ART's Linux JNI providers; it does not implement the Bionic NDK or GLES
ABI for arbitrary native APK libraries.

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
`-Wall -Wextra -Werror` and 64 KiB ELF alignment.

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
