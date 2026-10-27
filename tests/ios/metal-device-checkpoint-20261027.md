# Metal device availability checkpoint — 2026-10-27

Runtime, fixtures and auditor source:
`7bfc986b91ebd7b07b3b9a00b9387c674f138be3`. Advertising remains skipped.

The Metal framework now resolves `MTLCreateSystemDefaultDevice` with its native
no-argument, nullable, retained-result API. Vinix returns nil because it has no
Metal execution backend. This lets callers handle unavailable hardware without
branching through an unresolved weak import. It does not provide a GPU device,
shader translation, command execution or presentation.

The native/runtime fixture checks the API, exact framework and symbol scope,
eight concurrent callers, invalid-device cache rejection and two fully drained
runtimes. The native machine supplies a device, whose protocol and ownership
are checked. Vinix exercises the permitted nil result. The existing Metal cache
fixture also passes, including externally supplied devices, shared BGRA/YUV
textures, independent lifetimes, failure paths and concurrent readers. Both
fixtures pass regular and deterministic ASan/UBSan runs. All 27 guest fixtures
pass.

With the original cooked content, Fortnite passes this import and reaches:

```text
iOS: unimplemented Objective-C method NSNotificationCenter addObserverForName:object:queue:usingBlock:
```

The saved Mach-O inspector verifies the weak import, its library, both indirect
symbol entries, branch veneer, three stub instructions, and the caller's
`cbz x0` nil branch from `0x100629530` to `0x100629660`. The application no longer
reports a signal fault at this boundary. It exits 1 at the missing observer
method; capture exits 0.

Three images, nine Objective-C `+load` calls, three initializer groups and
application entry complete. The 8 GiB guest retains the tagged 24 GiB reservation,
enforced 2 GiB game budget, 1800-second limit and desktop window protocol checks.
The desktop peer reports 33 builds, 32 polls, a broken pipe and no supervisor
kill. Final cgroup usage is 327,686 bytes with zero OOM counters. Its first tree
contains one node, zero images and 336 bytes. The peer has no compositor or input
device. No game frame is verified.

Progress remains **4/8 observable gates**: load/bind, `+load`, initialization and
application entry. Frame, menu, login and playable match remain unverified.
This fraction does not estimate remaining time or effort.

The saved auditor rejects 53 guest-log mutations, 32 host-log mutations, unsafe
IPA members, malformed manifests and changed, missing or extra resources. It
extracts guest resources and binaries for comparison with the original inputs
and recorded runtime, fixtures and supervisor, including memory and desktop
configuration. Seal and independent complete-bundle verification pass.

The complete approximately 8 GiB bundle is retained on persistent external state
storage, including sources, IPA, resources, generated C, binaries, boot media,
firmware state, logs, static analysis and its saved auditor:

```text
/Users/alex/Library/Caches/vinix-ios/metal-device-20261027
VM state: probe-no-ads-475125
Manifest SHA-256:
861032aa63e32609305f2874846030fab11cd32157250e8c73a8efacb12be47c

Prior complete bundle:
/Users/alex/Library/Caches/vinix-ios/locale-preferred-20261027
Prior manifest SHA-256:
d4990c489920783d90caefb5db27121bf25f5b6f277ce0a1af967860b9a26379

IPA SHA-256:
47a17e723f8fae91595ac897d8f59cd3b453c43113a20bb1ff31ab656167332e
Executable SHA-256:
6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373
```

Independent validation logs are outside the sealed bundle at
`/Users/alex/Library/Caches/vinix-ios/metal-device-20261027-work`.
No expanded historical evidence was removed.

The original IPA, application and 95 resource files (1,831,863,828 bytes) are
unchanged. All 26 prior fixture binaries and their generated C match the prior
manifest; the Metal fixture, runtime and supervisor are rebuilt. The overlay is
not a complete installation. The kernel is reused and inventoried. The 707
selected input hashes do not seal complete compiler, header and library closures.
Native macOS Foundation and Metal are proxies for their iOS APIs.

To reproduce, build `tests/ios/metal-device.v` with the recorded frozen V compiler
using `-nocache -gc none -cc clang -cflags -O2` and a module path including
`tests/ios`. Run `prepare OUT PRIOR`, `fixture OUT`, `build OUT`, `host OUT`,
`regression-host OUT`, `probe OUT`, `audit OUT FULL_REVISION`, `seal OUT`,
`check OUT` and `selftest OUT`. Build fixture and runtime sequentially.
`VINIX_IOS_AUDIT_V` selects the audit compiler; `VINIX_IOS_AUDIT_TMPDIR` selects
external extraction scratch storage. The retained auditor can run `check`
without rebuilding the toolchain.
