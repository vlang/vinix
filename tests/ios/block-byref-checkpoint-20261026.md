# Blocks capture checkpoint — 2026-10-26

Tested fix and evidence tools revision:
`040ecff9dea6b94bba6ea5d996e30aa7ec4b7b28`. Advertising work remains skipped.

The runtime now implements `__block` forwarding and shared ownership,
compiler copy/dispose helpers and extended layouts. Native Apple Blocks
reference cases and the runtime fixture pass under ASan/UBSan with normal
and deterministic Swift hashing. They cover stack/heap cleanup orders, ARC
strong/weak moves and concurrent retain/release of an already promoted
capture. Concurrent first promotion remains unverified. Existing Block IMP
regressions also pass under both sanitizer configurations.

The ARM64 Vinix fixture passes before the next Fortnite launch. The unchanged
42.30.1 executable has SHA-256
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
The explicit `--probe-no-ads` diagnostic binds SKAdNetwork to nil and changes
application behavior. All three images bind and register, all nine Objective-C
`+load` methods finish, and initializer-stage markers appear for EOSSDK,
MarketplaceKitWrapper and the main executable. The exact 24 GiB tagged virtual
reservation succeeds at `0x800a36a0000`; its errno 22 is stale after success.
The range is not fully committed physical memory.

The previous capture-disposal panic is gone. Startup now stops at an
unimplemented `NSMutableDictionary allKeys` call. The panic interleaves with
another thread's VM trace, so its words are split in the raw serial log.
The application exits with status 1 (wait status 256); the harness exits 0
after completing the diagnostic. The final application cgroup counters show
zero `oom` and `oom_kill` events with `memory.max=2147483648`. Seven headroom
queries return 663,528,358 or 662,995,494 bytes. The budget and native signal
fixtures also pass, including isolated 64 MiB OOM handling, all 31 ARM64
registers on a protection fault, and signal handler restoration.

Progress is **2 of 8 observable gates (25% of this checklist)**: image
loading/binding and all `+load` calls pass. Initializer completion, application
entry, a rendered frame, an interactive menu, login and a playable match remain
unverified. This fraction does not estimate remaining engineering effort or time.

Complete evidence is preserved outside Git at
`/Users/alex/Library/Caches/vinix-ios/block-captures-20261026/fixed`.
It contains 1,158 source records, 692 selected input records and 1,609 manifest
records, including the application/frameworks, generated C, host sanitizer
objects and TLS archives, helpers/runners, command/status logs and complete
guest media. `probe-no-ads-state.txt` selects `probe-no-ads-858750`.
SHA-256 of `manifest.sha256`:

```text
5af89ec219224bc44d9c69c98a013cc8d75b823e1e5094ddaa8bc0bac886b52e
```

`block-byref-evidence.v` seal, independent check and selftest pass. The checker
requires the complete bundle and rejects missing media, changed VM size/tag,
failed/null reservation results, missing VM traces or capture validation,
changed application boundaries, altered logs and unmanifested files. Historical
checkers remain unchanged. The prebuilt ARM64 kernel is inventoried; concurrent
kernel edits were not rebuilt. Selected hashes do not seal the complete compiler,
header or host-library closures.

Reproduce with the frozen toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`, setting `V_RESOURCE_PATH`
there and `V_MACOS_V3_NO_FALLBACK=1`. Compile `notification-checks.v`,
`notification-vm.v`, `image-initializers-input-inventory.v` and
`block-byref-evidence.v` with `-nocache -prod -gc none -cc clang`; the first
two need the `tests/ios` module path. Run host modes `block-byref-host` and
`block-imp-host` (the latter in `imp-regression/`), then guest builds
`build-init`, `build-block-byref`, `build-vm-probe` and `build-run-ios-gles`.
Run `probe-no-ads` with `VINIX_IOS_PROBE_MEMORY_MAX=2147483648` and
`VINIX_IOS_VM_GZIP_LEVEL=9`, preserve the application and source/input inventory,
then run the evidence tool's `seal DIR`, `check DIR`, `selftest DIR` and
`hash FILE` modes. Use the source snapshot for this historical bundle: later
fixture additions require their own builds and evidence checks.
