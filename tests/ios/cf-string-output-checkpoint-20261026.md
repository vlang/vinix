# CFString UTF-16 output checkpoint — 2026-10-26

Implementation revision: `0c5e8f54445e873fae4421eae5d121d96a69a621`.
Final evidence tools and inventoried source revision:
`0607e5a5ba82b9ac0dbd7c8034ff40d765546890`. Advertising work remains skipped.

`CFStringGetBytes` now supports native, little-endian and big-endian UTF-16.
Ranges and returned counts use UTF-16 units, including individual surrogate
halves. Sizing queries, embedded NULs, partial/odd buffers, unaligned output and
native-endian external BOMs are covered. The existing UTF-8/ASCII conversion and
`CFStringGetCString` encoding scope are preserved. One deliberate divergence
from observed macOS behavior bounds native UTF-16 external output: capacities
zero or one write nothing and return zero bytes, instead of writing a two-byte
BOM beyond the declared capacity.

The native inspector records 1,280 unique observations over three strings,
five encodings, external/nonexternal output, ranges, capacities and sizing
queries. Native and emulated host fixtures pass under ASan/UBSan with normal
and deterministic Swift hashing. They cover the by-value CFRange C ABI,
surrogate splits, BOM/endian behavior, protected boundaries, canaries, null
used-byte pointers, the game's sizing/conversion sequence, eight concurrent
workers and two drained emulated runtimes. Sanitizer leak detection is disabled;
tracked emulated live objects must return to zero.

All nine ARM64 guest builds pass: init, CFString output, search paths, home
directory, inline pthread-self, dictionary snapshots, Blocks byref, VM probe
and the game runner. The guest CFString fixture and existing regression
fixtures finish with wait status zero. The unchanged Fortnite 42.30.1 executable
has SHA-256 `6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
Static evidence identifies the CFString import/forwarding thunk, three direct
callers and the game's little-endian UTF-16 arguments. The prior encoding panic
is gone. All initializers return and application entry is reached, followed by
a Documents search-path query. The next observed stop is:

```text
V panic: iOS: unimplemented Objective-C method NSBundle appStoreReceiptURL
```

Progress is **4 of 8 observable gates (50% of this checklist)**: image loading/
binding, all nine `+load` calls, initializer completion and application entry
pass. A rendered frame, interactive menu, login and playable match remain
unverified. This fraction does not estimate remaining engineering effort or time.
The explicit `--probe-no-ads` diagnostic binds SKAdNetwork to nil and changes
application behavior; these observations do not establish a normal launch.

The probe binds/registers all three images and translates all 13 inline
pthread-self reads. Its exact 24 GiB tagged virtual reservation succeeds at
`0x800a68ec000`; errno 22 is stale after success. This does not commit 24 GiB of
physical memory. Seven headroom queries return 663,143,334 or 662,610,470 bytes.
The final application cgroup has zero `oom`/`oom_kill` events under a 2 GiB limit.
The only fault is the deliberate signal fixture, which captures all 31 ARM64
registers and restores execution. The application exits 1 (wait status 256),
and the complete diagnostic harness exits zero.

Complete evidence is preserved outside Git at
`/Users/alex/Library/Caches/vinix-ios/cf-string-output-20261026`.
It contains 1,173 source records, 694 selected input records and 1,512 manifest
records, including application/frameworks, generated C, sanitizer objects,
TLS archives, tools, commands/status logs and complete guest media.
`probe-no-ads-state.txt` selects `probe-no-ads-1337875`.
SHA-256 of `manifest.sha256`:

```text
4e3cb335b8b506cb371070ba391c2e9ae289e02e1c52d8ac774eb2d7016ecf56
```

The CFString evidence tool's seal, independent check and selftest pass. It
rejects missing media, changed VM diagnostics, changed/missing/duplicate native
observations, missing fixture validation, failed waits, changed search arguments/
paths/counts, missing/repeated/misordered application entry, changed translation/
panic/exit boundaries, extra faults/panics, altered logs and unmanifested files.
Historical checkers remain unchanged. The prebuilt ARM64 kernel is inventoried;
concurrent kernel edits were not rebuilt. Selected input hashes do not seal
complete compiler, header or host-library closures.

Reproduce from the inventoried revision using the frozen toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`, setting `V_RESOURCE_PATH`
there and `V_MACOS_V3_NO_FALLBACK=1`. Compile `notification-checks.v`,
`notification-vm.v`, `cf-string-output-run.v`, `inspect-cf-string-output.v`,
`image-initializers-input-inventory.v` and `cf-string-output-evidence.v` with
`-nocache -prod -gc none -cc clang`; notification tools need the `tests/ios`
module path. Preserve the application/frameworks and import/caller disassembly.
Run the notification wrapper's `cf-string-output-host` mode in a new external
bundle, then the checkpoint runner's `build` and `probe` modes. The runner sets
the 2 GiB cgroup budget and gzip level 9. Run the inspector with the bundle and
application paths to capture native behavior and argument disassembly. Capture
source/input inventories using the full revision above, then run the evidence
tool's `seal`, `check`, `selftest` and `hash` modes.
