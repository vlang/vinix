# Audio session activity checkpoint — 2026-10-27

Runtime, fixtures and auditor source:
`3b07d1e248fafb744aef62c4b96bd603ebc1b66e`. Advertising remains skipped.

`AVAudioSession isOtherAudioPlaying` now returns false when no cross-application
audio-session provider is attached. Method discovery, BOOL metadata and direct
IMP invocation match that contract. The shared session cache now serializes
concurrent first access and owns its instance until runtime shutdown. This is
an absent-provider fallback: independent OSS clients cannot be detected, and
offline AudioUnit rendering does not establish another application's playback.
This change does not provide system-wide audio coordination or an output backend.

The focused fixture checks signatures, direct IMP results, eight concurrent
singleton workers, ownership and two fully drained runtimes. It passes regular
and deterministic ASan/UBSan runs, as does the existing thirteen audio-constant
regression fixture. Native Catalyst comparisons check class/instance method
availability, type encodings and nonnull IMPs. Calling the native shared session
stalled in the Apple audio server's synchronous XPC reply; that attempt and its
process sample are preserved in `attempts/`. Native session calls and system-wide
activity behavior remain unverified. All 29 ARM64 guest fixtures pass.

With the original cooked content, Fortnite passes the activity query and reaches:

```text
iOS: unimplemented Objective-C method AVAudioSession category
```

Three images, nine Objective-C `+load` calls, three initializer groups and
application entry complete. The application exits 1 at the missing method;
capture exits 0 without an application signal fault. The 8 GiB guest retains
the tagged 24 GiB reservation, enforced 2 GiB game budget, 1800-second limit and
desktop window protocol checks. The desktop peer reports 43 builds, 42 polls,
a broken pipe and no supervisor kill. Final cgroup usage is 327,686 bytes with
zero OOM counters. Its first tree contains one node, zero images and 336 bytes.
The peer has no compositor or input device. No game frame is verified.

Progress remains **4/8 observable gates**: load/bind, `+load`, initialization and
application entry. Frame, menu, login and playable match remain unverified.
This fraction does not estimate remaining time or effort. Vinix still has no
Metal execution or presentation backend; `MTLCreateSystemDefaultDevice` returns nil.

The saved auditor rejects 57 guest-log mutations, 32 host-log mutations, unsafe
IPA members, malformed manifests and changed, missing or extra resources. It
extracts guest resources and binaries for comparison with the original inputs
and recorded runtime, fixtures and supervisor, including memory and desktop
configuration. Seal and independent complete-bundle verification pass.

The complete expanded bundle is retained on persistent external state storage,
including sources, IPA, resources, generated C, binaries, boot media, firmware
state, logs and its saved auditor:

```text
/Users/alex/Library/Caches/vinix-ios/audio-activity-20261027
VM state: probe-no-ads-778166
Manifest SHA-256:
57e4233a27ea5ede140e958ab92e0ed85c457d2c17b4baa3113460e813cfbc3c

Prior complete bundle:
/Users/alex/Library/Caches/vinix-ios/notification-block-20261027
Prior manifest SHA-256:
968985d829aa21976093d59107a7b9b447609081375158d84d7acc2896bf2dad

IPA SHA-256:
47a17e723f8fae91595ac897d8f59cd3b453c43113a20bb1ff31ab656167332e
Executable SHA-256:
6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373
```

Independent validation logs are outside the sealed bundle at
`/Users/alex/Library/Caches/vinix-ios/audio-activity-20261027-work`.
No expanded historical evidence was removed.

The original IPA, application and 95 resource files (1,831,863,828 bytes) are
unchanged. All 28 prior fixture binaries and their generated C match the prior
manifest; the audio activity fixture, runtime and supervisor are rebuilt. The
overlay is not a complete installation. The kernel is reused and inventoried.
The 708 selected input hashes do not seal complete compiler, header and library
closures.

To reproduce, build `tests/ios/audio-activity.v` with the recorded frozen V
compiler using `-nocache -gc none -cc clang -cflags -O2` and a module path
including `tests/ios`. Run `prepare OUT PRIOR`, `fixture OUT`, `build OUT`,
`host OUT`, `regression-host OUT`, `probe OUT`, `audit OUT FULL_REVISION`,
`seal OUT`, `check OUT` and `selftest OUT`. Build fixture and runtime
sequentially. `VINIX_IOS_AUDIT_V` selects the audit compiler;
`VINIX_IOS_AUDIT_TMPDIR` selects external extraction scratch storage. The
retained auditor can run `check` without rebuilding the toolchain.
