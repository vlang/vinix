# Bundle receipt checkpoint — 2026-10-26

Implementation, evidence tools and inventoried source revision:
`48d373e4860ea8896c3a33c618a71181c57b219c`. Advertising work remains skipped.

`NSBundle appStoreReceiptURL` now returns nil because this runtime has no App
Store receipt support. Instance method metadata, its object return signature
(`@16@0:8`), direct IMP calls and `respondsToSelector:` agree; the getter is not
advertised as a class method. This does not implement receipt validation,
refresh, purchases or App Store services.

Native observations distinguish two cases: an unbundled macOS executable
returns nil, while a macOS `.app` returns a file URL ending in
`Contents/_MASReceipt/receipt` even when the receipt is absent. Vinix's nil
result represents unavailable App Store support; it does not claim parity with
the bundled macOS result. The inspector records 256 unbundled reads, and the
shared fixture checks the native bundled URL separately from the runtime's nil.

Native and runtime host fixtures pass under ASan/UBSan with normal and
deterministic Swift hashing. They check instance/class selector scope, unknown
selectors, method encoding/signatures, direct IMP calls, stable main-bundle
identity, eight workers with 256 iterations each and pool draining. Two runtime
lifetimes finish with zero tracked live objects. Sanitizer leak detection is
disabled. All ten ARM64 guest builds pass: init, receipt, CFString output,
search paths, home directory, inline pthread-self, dictionary snapshots, Blocks
byref, VM probe and the game runner. All eight guest regression fixtures finish
with wait status zero.

The unchanged Fortnite 42.30.1 executable has SHA-256
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
The receipt panic is gone. All three images bind/register, all nine `+load`
calls and three initializer groups return, and application entry is reached.
The next observed stop is:

```text
V panic: iOS: unimplemented Objective-C method NSString stringWithCString:encoding:
```

Progress remains **4 of 8 observable gates (50% of this checklist)**: image
loading/binding, `+load` completion, initializer completion and application
entry pass. A rendered frame, interactive menu, login and playable match remain
unverified. This fraction does not estimate remaining engineering effort or
time. The explicit `--probe-no-ads` diagnostic binds SKAdNetwork to nil and
changes application behavior; these results do not establish a normal launch.

All 13 inline pthread-self reads are translated. The exact 24 GiB tagged
virtual reservation succeeds at `0x800a2250000`; errno 22 is stale after
success. This does not commit 24 GiB of physical memory. Seven headroom queries
return 663,159,718 or 662,626,854 bytes. The final application cgroup has zero
`oom`/`oom_kill` events under a 2 GiB limit. The only fault is the deliberate
signal fixture, which captures all 31 ARM64 registers and restores execution.
The application exits 1 (wait status 256); the complete diagnostic harness exits
zero.

Complete evidence is preserved outside Git at
`/Users/alex/Library/Caches/vinix-ios/bundle-receipt-20261026`.
It contains 1,177 source records, 695 selected input records and 1,524 manifest
records, including application/frameworks, generated C, sanitizer objects,
TLS archives, tools, command/status logs and complete guest media.
`probe-no-ads-state.txt` selects `probe-no-ads-898416`.
SHA-256 of `manifest.sha256`:

```text
d10cf1facae48d47a06894efb71b8f7883f67bc25494d8d1c0b4fd0d126cafea
```

The receipt evidence tool's seal, independent check and selftest pass. It
rejects changed native receipt observations, missing receipt validation, failed
receipt waits, and the existing VM/native-CFString/search-path/startup-boundary
mutations, missing media, altered logs and unmanifested files. Historical
checkers remain unchanged. CFString static/native observations are inherited
from source `0607e5a5ba82b9ac0dbd7c8034ff40d765546890` and complete bundle
`/Users/alex/Library/Caches/vinix-ios/cf-string-output-20261026`, whose manifest
SHA-256 is `4e3cb335b8b506cb371070ba391c2e9ae289e02e1c52d8ac774eb2d7016ecf56`.
Their provenance is recorded in `inherited-evidence.txt`. The prebuilt ARM64
kernel is inventoried; concurrent kernel edits were not rebuilt. Selected
input hashes do not seal complete compiler, header or host-library closures.

Reproduce from the inventoried revision using the frozen compiler at
`build/ios/fortnite/ns-calendar-checks/toolchain/v`, with `V_RESOURCE_PATH`
pointing to that toolchain and `V_MACOS_V3_NO_FALLBACK=1`. Compile
`notification-checks.v`, `notification-vm.v`, `bundle-receipt-run.v`,
`image-initializers-input-inventory.v` and `bundle-receipt-evidence.v` with
`-nocache -prod -gc none -cc clang` and the `tests/ios` module path. Preserve
the application/frameworks and inherited CFString static/native observations
with their provenance. In a new external bundle, run the notification wrapper's
`bundle-receipt-host`, `bundle-receipt-inspector-build` and
`bundle-receipt-inspect` modes, then the checkpoint runner's `build` and `probe`
modes. The runner sets the 2 GiB cgroup budget and gzip level 9. Capture
source/input inventories using the full revision above, then run the evidence
tool's `seal`, `check`, `selftest` and `hash` modes.
