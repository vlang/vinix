# Asset locale native bridge: host checks

`AssetManager.getLocales()` now enumerates the manager's loaded resource tables
through the existing `libandroidfw` C API. It includes system resources and merges
equivalent language tags, matching [AOSP's native locale entry point](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-9.0.0_r1/core/jni/android_util_AssetManager.cpp).
It returns a fresh Java array without changing the default locale or adding
synthetic language tags. The SDK already declares this method; the JNI binding is
the only appended binding.

The [pinned C API implementation](https://gitlab.com/android_translation_layer/art_standalone/-/raw/e78bf68917bcaaf58fef3960cd88793b3b7f39cc/libandroidfw/androidfw_c_api.cpp)
allocates the null-terminated pointer vector with C++ `new[]` and each string with
`strdup`. The bridge resolves the matching loaded C++ array deallocator before
allocation, frees each string with `free`, and releases the vector with
`operator delete[]`. Enumeration holds the existing global resource mutex then
the manager mutex. The returned copies permit releasing both locks before JNI.
Class, temporary string and failed result-array references are released while
preserving pending exceptions. The inherited C API does not report an interior
`strdup` failure separately from its terminator; these checks do not qualify that
internal C++ allocation-failure path.

Source parent: `2aa63fa85808649f2e86f313968e101fc8058fb3`. Tested source hashes:

- `asset_locales.v`: `da7712f01e12748363a7afcbe25aa9c052b86ad01538d782f97c486e65b327fd`
- `bindings.txt`: `2264b7af0bf4a5b39da876e2ef82a291983d7ea9bd2c5f7374d8448b4f1a03ba`
- `check-asset-locales-native.v`: `6f4c0b41d913403ca7c219191632d5dc0583045eb6566066febd168a725ae44e`

The host checker executes the exact production locale helper, entry point and
JNI helpers against recording C API, resource-lock, allocator and JNI boundaries.
It checks three datasets including an empty manager, fresh arrays, caller
mutation isolation, exact enumeration flags, lock ordering, paired native frees,
initial pending exceptions, manager/deallocator/enumeration failures, and every
class/array/string/set JNI failure path. All six negative controls were detected:
missing enter, missing leave, missing string free, missing vector delete, wrong
flags, and a fabricated result count. This establishes adapter behavior; actual
ART and APK resource enumeration require the separate ARM fixture.

Evidence is retained outside Git:

- `~/.local/state/vinix/android/asset-locales-native-check-2026-11-02-r1`
  contains copied inputs, generated probe/project, commands and PASS receipt
  `e20b410df74b2fcc69cd994b4b7fe73b5e16b74c191bbb90ac39c66bc42d0ca7`.
- `~/.local/state/vinix/android/asset-locales-native-controls-2026-11-02-r1`
  contains the serial V project/Makefile build and guard logs.

All three host phases passed under the unchanged 600 MiB aggregate RSS,
300-second, 512 MiB growth, 1 GiB reserve and file/output caps. Detailed maximum
RSS also stayed below the cap: 262,651,904 bytes for checker generation,
74,563,584 bytes for its Makefile build, and 106,446,848 bytes for the final run.
The final run took 3.538 seconds, sampled 123,387,904 bytes aggregate RSS, recorded
zero process swaps and 14,258,176 bytes observed volume growth, and cleaned up
completely. Coupled ARM production and live GMS behavior remain separate checks.
