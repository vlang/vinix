The maintained iOS C++ and graphics staging tools run in V:

```sh
build-support/ios/build-cxx --output /tmp/ios-cxx --sysroot build-aarch64-userland/staging
build-support/ios/stage-gles --output /tmp/ios-stage --sysroot build-aarch64-userland/staging \
  --mesa-sysroot build-aarch64-x11/sysroot --readelf /path/to/llvm-readelf
build-support/ios/generate-cxx-symbols
```

`scripts/build-ios-aarch64.sh` invokes the native tools for its optional C++ and
graphics builds. `LLVM_BIN` selects LLVM; `V` selects the host V compiler.
Symbol generation keeps the curated symbol order and excludes `__Unwind_Resume`
from the linker stub. Its declaration header changes only the generator comment.
Use `--output REPOSITORY` to inspect generated symbol files in a private tree.

`iosbuild` verifies the four original archive pins, reads regular tar/APK files
without running package hooks, and retains the original ctype, TLS-key, string
and mbstate ABI patches and compiler flags. At most four compiler jobs run at
once; every started job is joined before an error returns. Compiler stdout and
stderr share the original ordered stream. Object hashes and compiler input
content qualify cache hits, and archive publication preserves the old library
on failure. Only the compiler's source and header directories enter the source
key; unrelated upstream documentation and tests do not affect the build.

Graphics staging keeps the original source search order, dependency traversal,
ARM64 ELF checks and private Gallium/linker aliases. Library copies preserve
bytes, permission bits, nanosecond times, extended attributes and platform flags.
Existing aliases can be refreshed without replacing desktop libraries.

Six cold program/profile builds and native cases pass on ARM, x86 and
ASan/UBSan. The cases cover exact symbol outputs, archive paths and skipped links,
checksum publication, four-worker limits, warm/corrupt caches, joined compiler
failures, old-library preservation, source priority, dependency cycles, metadata
and missing/invalid ELF dependencies. A real build produces 47 ARM64 libc++
objects; independent compiler assertions check the 24-byte string, 128-byte
mbstate with 8-byte alignment, and 32-bit ctype mask. Public commands pass real
warm-cache and corrupt-object repair checks, and stage all 40 libraries from the
recorded Mesa dependency set with matching bytes and timestamps. These are host
tool and cross-build checks, not an iOS application or Vinix guest runtime test.
No Python was executed.

The three retired Python originals total 10,889 bytes and 213 lines at
`d6d9af30`. Frozen inputs, binaries, logs, failure attempts and review receipts
are retained in `~/.cache/vinix-ios-build-tools-native-20261012`.
