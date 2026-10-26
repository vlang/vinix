# Xvfb fault diagnostic

This V preload library records Linux AArch64 `SA_SIGINFO` fault registers and a bounded `/proc/self/maps` dump, then calls the application's original one or three argument signal handler. It preserves disposition queries, replacement, masks, reset flags and restoration. Fixed buffers and append-only disposition records avoid allocation, stdio, an unwinder or dynamic symbol lookup in the fault handler.

Use only for a credential-free diagnostic run. Apply the musl loader's `--preload` argument to the controlled fixture and Xvfb child, never the WebKit engine or a real account session. Keep `LD_PRELOAD` unset so Xvfb subprocesses do not inherit the shim. The shim wraps signals 4, 5, 6, 7, 8 and 11. It is a startup diagnostic, not a general purpose transparent interposer for concurrent handler replacement. After 1024 installations it preserves native behavior without adding diagnostics.

Build a fresh external audit bundle:

```
v run tests/android-x11-fault-probe/build.v REPO V_COMPILER FRESH_EXTERNAL_ROOT
```

On the guest, run the retained `known-fault` binary through the pinned musl loader with the library path used by Xvfb and `--preload /absolute/path/libx11-fault-probe.so` before the executable path. It accepts no arguments. Retain stdout and stderr together, require exit status zero, and verify the complete log with:

```
v run tests/android-x11-fault-probe/verify.v KNOWN_FAULT_LOG
```

Only after that preflight passes, add the same preload to Xvfb. `X11-FAULT` gives the data address and instruction pointer separately; `X11-REGS` includes the link register as `x30`. Use the captured executable mappings and unchanged binary hashes to identify the fault instruction. Build and host tests alone do not establish native fault delivery or resolve the Xvfb crash.

The retained host validation bundle is `/Users/alex/.local/state/vinix/android/x11-fault-probe-build-2026-10-26-r2`, based on revision `e40fe2512d4b77373fe50aa1c94ca5a8f5bb932f` plus the exact added sources frozen in `sources/`. Its `build-sha256.json` checksum is `8d26b007d374b2d66d3907ed9fbf17d0bb3b34835952504ac8c2fc7029ec9130`. Four host test functions passed; both Linux AArch64 binaries compiled, and the required preload exports passed inspection. Guest fault delivery remains unverified in this bundle.
