# Notification block observer checkpoint — 2026-10-27

Runtime, fixtures and auditor source:
`4816bb9fdb57b34cdd0d86369d85d96174f7fc52`. Advertising remains skipped.

`NSNotificationCenter addObserverForName:object:queue:usingBlock:` now supports
a nil queue, delivering callbacks synchronously on the posting thread. The
center owns the observer token and a copied block until removal. Nil names and
senders match all notifications. Callbacks and capture helpers run outside the
observer-table lock. Removal during delivery preserves the in-flight capture
and prevents subsequent deliveries. A nonnil operation queue remains explicitly
unsupported; this change does not implement worker scheduling.

Native Foundation comparisons check delivery, filters, copied captures, token
ownership and removal, including removal through another center or mismatched
filters. Vinix also checks center destruction, reentrant capture helpers, eight
concurrent workers and two fully drained runtimes. The focused fixture and
existing selector/queue ownership regression pass regular and deterministic
ASan/UBSan runs. All 28 ARM64 guest fixtures pass. Native Foundation is a macOS
proxy; center-destruction cleanup is tested only against Vinix.

With the original cooked content, Fortnite passes observer registration and
reaches:

```text
iOS: unimplemented Objective-C method AVAudioSession isOtherAudioPlaying
```

Three images, nine Objective-C `+load` calls, three initializer groups and
application entry complete. The application exits 1 at the missing method;
capture exits 0 without an application signal fault. The 8 GiB guest retains
the tagged 24 GiB reservation, enforced 2 GiB game budget, 1800-second limit and
desktop window protocol checks. The desktop peer reports 40 builds, 39 polls,
a broken pipe and no supervisor kill. Final cgroup usage is 327,686 bytes with
zero OOM counters. Its first tree contains one node, zero images and 336 bytes.
The peer has no compositor or input device. No game frame is verified.

Progress remains **4/8 observable gates**: load/bind, `+load`, initialization and
application entry. Frame, menu, login and playable match remain unverified.
This fraction does not estimate remaining time or effort. Vinix still has no
Metal execution or presentation backend; the preceding checkpoint returns nil
for `MTLCreateSystemDefaultDevice`.

The saved auditor rejects 55 guest-log mutations, 32 host-log mutations, unsafe
IPA members, malformed manifests and changed, missing or extra resources. It
extracts guest resources and binaries for comparison with the original inputs
and recorded runtime, fixtures and supervisor, including memory and desktop
configuration. Seal and independent complete-bundle verification pass.

The complete approximately 8 GiB expanded bundle is retained on persistent
external state storage, including sources, IPA, resources, generated C,
binaries, boot media, firmware state, logs and its saved auditor:

```text
/Users/alex/Library/Caches/vinix-ios/notification-block-20261027
VM state: probe-no-ads-1745166
Manifest SHA-256:
968985d829aa21976093d59107a7b9b447609081375158d84d7acc2896bf2dad

Prior complete bundle:
/Users/alex/Library/Caches/vinix-ios/metal-device-20261027
Prior manifest SHA-256:
861032aa63e32609305f2874846030fab11cd32157250e8c73a8efacb12be47c

IPA SHA-256:
47a17e723f8fae91595ac897d8f59cd3b453c43113a20bb1ff31ab656167332e
Executable SHA-256:
6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373
```

Independent validation logs are outside the sealed bundle at
`/Users/alex/Library/Caches/vinix-ios/notification-block-20261027-work`.
No expanded historical evidence was removed.

The original IPA, application and 95 resource files (1,831,863,828 bytes) are
unchanged. All 27 prior fixture binaries and their generated C match the prior
manifest; the notification fixture, runtime and supervisor are rebuilt. The
overlay is not a complete installation. The kernel is reused and inventoried.
The 707 selected input hashes do not seal complete compiler, header and library
closures.

To reproduce, build `tests/ios/notification-block.v` with the recorded frozen V
compiler using `-nocache -gc none -cc clang -cflags -O2` and a module path
including `tests/ios`. Run `prepare OUT PRIOR`, `fixture OUT`, `build OUT`,
`host OUT`, `regression-host OUT`, `probe OUT`, `audit OUT FULL_REVISION`,
`seal OUT`, `check OUT` and `selftest OUT`. Build fixture and runtime
sequentially. `VINIX_IOS_AUDIT_V` selects the audit compiler;
`VINIX_IOS_AUDIT_TMPDIR` selects external extraction scratch storage. The
retained auditor can run `check` without rebuilding the toolchain.
