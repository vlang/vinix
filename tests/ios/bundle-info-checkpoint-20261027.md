# NSBundle info dictionary checkpoint — 2026-10-27

Runtime, fixtures and auditor source:
`0ba915509a8d7e4ca49451c6bb22014c6b5c55b5`. Advertising remains skipped.

`NSBundle infoDictionary` now loads and owns the complete supported XML or binary
Info.plist tree. It shares a lazily published cache with `bundleIdentifier`.
Dictionary and array containers are mutable; identifier replacement and removal
are visible through both properties. Missing, malformed and non-dictionary plists
produce a cached empty dictionary, matching the native observations. Competing
first reads release unused trees, and bundle destruction releases the winning tree.
The method also exposes its instance metadata, signature and direct IMP.

Native Foundation passes sixteen plist/property-order observations. The shared
native/runtime fixture and the existing identifier regression each pass regular
and deterministic ASan/UBSan runs. They cover Unicode, nested collections,
numbers, booleans, data, cache stability after file changes, mutation, eight
workers, autorelease-pool independence and runtime shutdown with zero live
objects. All 25 guest fixtures pass.

Fortnite 42.30.1 passes `infoDictionary` with the original cooked resources and
stops at:

```text
V panic: iOS: unimplemented Objective-C method NSLocale preferredLanguages
```

Three images load, nine Objective-C `+load` calls and three initializer groups
complete, and application entry is reached. Fault recovery captures all 31 ARM64
registers. The tagged 24 GiB reservation, enforced 2 GiB game memory budget and
UIKit window protocol fixture pass in the 8 GiB guest with an 1800-second limit.
The game exits 1 and capture exits 0. The desktop peer reports 52 builds, 51 polls,
a broken pipe and no supervisor kill; final cgroup usage is 191,984 bytes with
zero OOM counters. The first tree has one node, zero images and 336 bytes. The
peer has no compositor or input device. **No game frame is verified.**

Progress remains **4/8 observable gates**: load/bind, `+load`, initialization and
application entry. Frame, menu, login and playable match remain unverified.
This count does not estimate remaining time or effort.

The saved auditor rejects 49 guest-log mutations, 32 host-log mutations, unsafe
IPA members, malformed manifests and changed, missing or extra resources. It
extracts the guest resources and binaries and compares them with the saved
original inputs, fixtures, runtime and supervisor, including desktop and memory
configuration. Seal and complete-bundle verification pass.

The complete approximately 8 GiB bundle is retained on persistent external state
storage, including source snapshots, IPA, resources, generated C, binaries, boot
media, firmware state, logs and the saved auditor:

```text
/Users/alex/Library/Caches/vinix-ios/bundle-info-20261027
VM state: probe-no-ads-673125
Manifest SHA-256:
f9b40aa2bed88f9580899957a3274185c371f0c43e2d4ddc0e5c4fa8caf899f3

Prior complete bundle:
/Volumes/VinixAppendRestore20261027/get-cstring-guest
Prior manifest SHA-256:
0400b6061bb6983602eba8df0e60298a1141f8e249049fd6346300929c984b32

IPA SHA-256:
47a17e723f8fae91595ac897d8f59cd3b453c43113a20bb1ff31ab656167332e
Executable SHA-256:
6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373
```

Validation logs remain outside the sealed bundle at
`/Users/alex/Library/Caches/vinix-ios/bundle-info-20261027-work`.
The [prior checkpoint](string-get-cstring-checkpoint-20261027.md) records its
lossless archive and restore prerequisites. No expanded evidence was removed.

The original IPA, application and 95 resource files (1,831,863,828 bytes) are
unchanged. Twenty-three prior fixture binaries and their generated C are checked
against the prior manifest; the bundle-info and identifier fixtures, runtime and
supervisor are rebuilt. The overlay is not a complete installation. The kernel
is reused and inventoried. Selected input hashes do not seal complete compiler,
header and library closures. Native macOS Foundation is a proxy for iOS.

The frozen runtime compiler became incompatible with the concurrently updated
host V library while rebuilding the audit tools. Audit helpers instead use
`/Users/alex/code/v-macos-ci-cache-baseline-20261026/v`, recorded in
`audit-compiler.sha256` and the command/version logs. Runtime and fixture builds
retain their recorded compiler commands. Historical auditors are unchanged.

To reproduce, build `tests/ios/bundle-info.v` with a compatible host V compiler
using `-nocache -gc none -cc clang -cflags -O2`. Run `prepare OUT PRIOR`,
`oracle OUT`, `host OUT`, `regression-host OUT`, `fixture OUT`, `build OUT`,
`probe OUT`, `audit OUT FULL_REVISION`, `seal OUT`, `check OUT`, and `selftest OUT`.
Build fixture and runtime sequentially. `VINIX_IOS_AUDIT_V` selects the audit
compiler; `VINIX_IOS_AUDIT_TMPDIR` selects external extraction scratch storage.
The retained saved auditor can run `check` without rebuilding the toolchain.
