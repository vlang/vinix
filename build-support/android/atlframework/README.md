# V Android framework extension

This module fills gaps in the pinned ATL framework without modifying APKs.
`androidtools.extend_framework` disassembles ATL's original `api-impl.jar`,
adds JNI declarations and GC-owned state fields, and assembles the DEX again.
Smali and its dependencies have fixed Maven SHA256 hashes. The receipt records
the original JAR, output JAR, V sources and tool hashes. Reusing an already
extended input fails.

`libvinix-android-framework.so` registers the implementations when ART starts.
It lives beside `libart.so`: ATL finds its DEX directory relative to the
library exporting `JNI_CreateJavaVM`. The staged launcher preloads it after
the private libc compatibility library. The normal ATL build installs and
hashes both the library and extended DEX before writing its manifest.

The implementation provides ActionBar content, options menus, SearchView,
SimpleCursorAdapter, managed cursor lifecycle, ListActivity row dispatch,
cancelable View callbacks, dialog custom views and nullable button listeners.
Dialog dismissal hides the reusable window, and custom views participate in
the dialog's measured Java decor tree. Child activities have a Back control
without restoring the duplicate GTK title bar. ScrollView positions use real
GTK adjustments; smoothScrollTo currently reaches its target immediately.
Activity recreation makes a new instance and delivers the application's saved
Bundle; EditText values with stable positive IDs are restored as well.
Recreation checks the pinned ATL native handle-cache layout before replacing
its lifecycle dispatch methods. Other view state is not yet serialized.

Themes start with Android's SDK-selected base before applying app overlays.
The ICU 78 charset list includes only converters the installed ART provider
can construct. Unexpected provider exceptions still propagate.

Java owns the persistent objects. JNI arguments use fixed native stack storage,
and loops over ICU converters and recursive view state bound local references
with JNI frames. The library requires no V heap/runtime allocation support.
`jni.v` defines the stable JNI C ABI; Java `int` is explicitly `i32`.

The default desktop launcher uses the [native WS backend](../nativews/README.md),
which reuses this module's toolkit-independent framework APIs and supplies its
own View, Canvas, dialog, resource, database and input implementations in V.
It does not register this module's GTK-specific ScrollView/dialog functions
or preload the legacy VM interposer. The GTK behavior described above belongs
to the retained historical ATL entry point.

For an existing original ATL JAR, use:

```sh
build-support/android/native-tool extend-framework original-api-impl.jar extended-api-impl.jar
build-support/android/native-tool compile-framework libvinix-android-framework.so \
  --cc aarch64-linux-musl-gcc --arch arm64
build-support/run-v-tool.sh tests/native-android-tools/check-framework.v
tests/android/art-runtime-test
```

The normal runtime build performs these extension steps automatically. The
standalone commands are useful for isolated compatibility investigations;
manually replacing files in an older runtime does not establish that it passes
the current complete runtime preflight.
