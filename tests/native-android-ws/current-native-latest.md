# Current V native builds

Normal two-argument invocations of `build-current-native.v` now compile and
execute `build-current-native-latest.v` with `/Users/alex/code/v/v`. They use
current repository sources and do not require historical compiler identities,
sealed baseline bundles or expected artifact hashes. Historical frozen replay
and hash diagnostics retain their original implementation.

Compile the entry point with current V and the module path
`-path '@vlib|/Users/alex/code/vinix/tests/native-android-tools'`, then pass
the framework directory (containing `smali`) and a fresh output directory.
The entry point retains a sibling `OUTPUT-latest-builder` executable.

`VINIX_ANDROID_NATIVE_HEADERS` selects the directory containing
`androidfw_c_api.h`, `sqlite3.h`, `stb_image.h` and `stb_truetype.h`.
It defaults to the available `account-native-compile-2026-10-26-r1` directory
under `/Users/alex/.local/state/vinix/android`; these files have no pin checks.
`VINIX_ANDROID_RUNTIME` selects the runtime root; by default the build uses
`build/android-framework/calculator/overlay/opt/vinix-android-aarch64`.
The builder generates JNI from the supplied framework, links with Werror and
undefined-symbol checking, and validates the AArch64 ELF shared-library header.
Commands, compiler version, sources, generated C and build metadata stay in
the output directory.

On 2026-11-12, V `0.5.2 f2edf66` built the native library directly and through
the normal entry point. The final entry-point run used
`/Users/alex/.local/state/vinix/android/current-native-build-2026-11-12-latest-r4`
and the default-network-active framework `r5`. Its guard and child exited 0/0,
with complete cleanup, in 10,033 ms: sampled aggregate RSS 459,898,880 bytes,
shared growth 12,435,456 bytes. The receipt and log are sibling files
`native-latest-20261112-r4.guard.json` and `native-latest-20261112-r4.log`.
The original 600 MiB RSS, 300 second, 512 MiB growth, 1 GiB reserve and 4 MiB
output limits were retained. Earlier r2/r3 compiler attempts exceeded RSS and
remain retained; using V's default GC/compiler settings passed in r4.
This is a host build result; guest execution remains pending.
