# NSLocale preferred languages checkpoint — 2026-10-27

Runtime, fixtures and auditor source:
`1edc8350dc2353c4fbbb438b199186a3cd74f070`. Advertising remains skipped.

`NSLocale preferredLanguages` now returns an autoreleased immutable array of
language strings through the existing CoreFoundation encoder. Class method
metadata, its `@16@0:8` signature and direct IMP are exposed. Each call owns an
independent snapshot. Retained arrays and strings survive pool drains; runtime
shutdown leaves zero live objects.

The shared native/runtime fixture passes exact native CF order, immutable
container, class-only lookup, metadata, direct IMP, eight concurrent readers,
retained values and pool-drain checks. Runtime tests additionally cover two
balanced runtimes, changed `LANGUAGE` priorities, unchanged older snapshots and
`LC_ALL` fallback. Both regular and deterministic ASan/UBSan runs pass. The
existing CoreFoundation preferred-language fixture passes the same sanitizer
runs. All 26 guest fixtures pass.

The frozen V toolchain now runs child compilations from its own root with a
module marker, keeping `@VEXEROOT` and library resolution within the recorded
toolchain. This avoids accidentally compiling against concurrently updated host
libraries. `pthread_self` uses the same V `usize` declaration as the frozen
macOS standard library; native C headers still determine its platform type.

Fortnite 42.30.1 passes the locale call and then branches through the unresolved
weak `_MTLCreateSystemDefaultDevice` import to address zero:

```text
preferred return address: 0x10062952c
call:                    0x100629528
branch veneer:           0x107c28630
Metal stub:              0x10c63cf0c
indirect pointer:        0x10dc99f70
fault PC / x16:          0 / 0
```

The saved inspector checks the BL and B instructions, all three import-stub
instructions, the weak import's library and both indirect-symbol entries.
This identifies a missing Metal device entry point. The existing CoreVideo
Metal cache imports textures from an externally supplied device; it does not
provide a Metal device, shader translation, command execution or presentation
backend. No GPU device or game frame is verified.

Three images load, nine Objective-C `+load` calls and three initializer groups
complete, and application entry is reached. Fault recovery captures all 31 ARM64
registers. The tagged 24 GiB reservation, enforced 2 GiB game memory budget and
UIKit window protocol fixture pass in the 8 GiB guest with an 1800-second limit.
The game exits 139 and capture exits 0. The desktop peer reports 31 builds,
30 polls, a broken pipe and no supervisor kill; final cgroup usage is 191,984
bytes with zero OOM counters. Its first tree has one node, zero images and
336 bytes. The peer has no compositor or input device.

Progress remains **4/8 observable gates**: load/bind, `+load`, initialization and
application entry. Frame, menu, login and playable match remain unverified.
This fraction does not estimate remaining time or effort.

The saved auditor rejects 52 guest-log mutations, 32 host-log mutations, unsafe
IPA members, malformed manifests and changed, missing or extra resources.
Changed fault LR and branch-register values are rejected. The auditor extracts
the guest resources and binaries and compares them with the original inputs,
fixtures, runtime and supervisor, including desktop and memory configuration.
Seal and independent complete-bundle verification both pass.

The complete approximately 8 GiB bundle is retained on persistent external state
storage, including source snapshots, IPA, resources, generated C, binaries, boot
media, firmware state, logs, fault analysis and the saved auditor:

```text
/Users/alex/Library/Caches/vinix-ios/locale-preferred-20261027
VM state: probe-no-ads-1067625
Manifest SHA-256:
d4990c489920783d90caefb5db27121bf25f5b6f277ce0a1af967860b9a26379

Prior complete bundle:
/Users/alex/Library/Caches/vinix-ios/bundle-info-20261027
Prior manifest SHA-256:
f9b40aa2bed88f9580899957a3274185c371f0c43e2d4ddc0e5c4fa8caf899f3

IPA SHA-256:
47a17e723f8fae91595ac897d8f59cd3b453c43113a20bb1ff31ab656167332e
Executable SHA-256:
6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373
```

Validation logs remain outside the sealed bundle at
`/Users/alex/Library/Caches/vinix-ios/locale-preferred-20261027-work`.
An initial gzip-level-9 staging attempt was stopped before QEMU launch and is
retained there under `compression-level9-aborted`. The completed probe uses
gzip level 1 with unchanged content and guards. No expanded historical evidence
was removed.

The original IPA, application and 95 resource files (1,831,863,828 bytes) are
unchanged. All 25 prior fixture binaries and their generated C are checked
against the prior manifest; the locale fixture, runtime and supervisor are
rebuilt. The overlay is not a complete installation. The kernel is reused and
inventoried. The 706 selected build-input hashes do not seal complete compiler,
header and library closures. Native macOS Foundation is a proxy for iOS.

To reproduce, build `tests/ios/locale-preferred.v` with the recorded frozen V
compiler using `-nocache -gc none -cc clang -cflags -O2` and a module path
including `tests/ios`. Run `prepare OUT PRIOR`, `fixture OUT`, `build OUT`,
`host OUT`, `regression-host OUT`, `probe OUT`, `audit OUT FULL_REVISION`,
`seal OUT`, `check OUT`, and `selftest OUT`. Build fixture and runtime
sequentially. `VINIX_IOS_AUDIT_V` selects the audit compiler;
`VINIX_IOS_AUDIT_TMPDIR` selects external extraction scratch storage.
The retained saved auditor can run `check` without rebuilding the toolchain.
