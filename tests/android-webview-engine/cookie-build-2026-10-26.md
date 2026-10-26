# Cookie engine cross-build

The cookie persistence and clearing implementation from `88a28c24e` passed the
AArch64 cross-build, host callback/storage checks, and the 99-symbol runtime API
audit. No guest execution or Google login is established by these checks.

The complete retained bundle is outside Git:

`/Users/alex/.local/state/vinix/android/account-contract-webview-cookie-engine-build-2026-10-26-r2`

- Captured source revision: `a8a5c2ddebf4c7d40d3b24be2cc6043916ff337f`.
- Complete 346-file `sha256.json`: `b3304762ce3dec16191ece43cee0cc3332694217e14d1a48dc339d2d2e4840d8`.
- Original build manifest: `3c0a6407fdb54389771a949f170bc42d97bee4d82a0e3abb1e22341c040b31c2`.
- AArch64 `webview-engine`: `99d18add16b75657dea30e3f792532252fae6c626521afe1f167e8911473d221`.
- Compiler: `0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`.

Both engine test suites, the cookie storage suite, and all three protocol suites
passed. The actual target executable linked, its ELF checks passed, and its
symbols include `vgc_gc_run`, `vgc_mark_roots`, and `v3_vgc_runtime_init`.
The API audit found all 99 required exports in the supplied runtime libraries.
The maintained retention checker verified the complete bundle after sealing.

The bundle retains 319 V source snapshots, the builder and compiler executables,
command receipts, logs, source and runtime-library hashes, and the output. The
engine build consumes copied application sources and the compiler's live V
library, whose captured files are checked again afterward. Host test-specific
V library files, compiler C helpers, native toolchain headers and linker inputs
are environmental dependencies; this is not a complete isolated toolchain
build. Independent read-only review confirmed this scope.

The earlier `account-contract-webview-cookie-engine-build-2026-10-26-r1` remains
preserved. It failed during host tests because the selected compiler and V
library disagreed on atomic pointer types; no target build ran in that attempt.
The successful retry explicitly selected the frozen compiler and its matching
library. Sandbox-enabled startup, real WebKit cookie flush/clear/restart and
the Google sign-in flow still require guest execution.
