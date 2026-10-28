# NSError description checkpoint — 2026-10-28

Runtime, fixtures and saved auditor:
`02fd022913ba85dc21173201e847e0dca2a7630e`. Advertising remains skipped.

`NSError description` now returns an independent autoreleased diagnostic string
with its domain, signed 64-bit code and string userInfo. Diagnostic text follows
Foundation's key precedence, including the separate debug suffix. Mutable
values remain shared with the copied userInfo dictionary; previous descriptions
remain independent. Embedded NULs and Unicode are preserved. Arbitrary object
descriptions and platform error catalogs remain partial; unsupported userInfo
objects and descriptions exceeding 1 MiB fail explicitly.

Regular and deterministic ASan/UBSan runs pass for this fixture and the
JSON/NSError regression. Native comparisons cover 20 diagnostic cases,
64-bit boundaries, Unicode, NULs, key precedence and shallow-copy mutation.
Runtime checks also cover direct IMP calls, pool drainage and retained results,
eight workers and two drained runtime lifetimes. All 35 ARM64 guest fixtures
pass.

Fortnite passes `NSError description` and stops with
`iOS: unsupported Swift mangled type suffix`. Three images, nine `+load` calls,
three initializer groups and application entry complete. Application exit is 1
and capture exit is 0, without an application signal fault, OOM event or
supervisor kill. The desktop peer records 11 builds and 10 polls; its first
tree has one node, zero images and 336 bytes. The peer has no compositor, so
these exchanges establish no rendered game frame.

The single-CPU 8 GiB guest retains the tagged 24 GiB reservation, enforced
2 GiB application budget and 1,800-second limit. Budget enforcement and
supervisor isolation checks pass. Final application usage is 327,862 bytes;
all OOM counters are zero. Progress remains **4/8 observable launch gates
(50% of the checklist)**. Frame, menu, login and playable match remain
unverified. The fraction estimates neither remaining effort nor time. Audio
output and Metal execution and presentation still need backends.

The preceding complete activation bundle passes its unchanged auditor. Its
original IPA, 95 resource files (1,831,863,828 bytes), and 34 fixture binaries
and generated C are reused unchanged. Runtime, supervisor and description
fixture are rebuilt. The source snapshot contains 1,283 files; 708 selected
input hashes do not cover complete compiler, header and library closures.
The retained kernel hash is
`1aaa1a692fffb653d75787af7df0848b62a0db17af86705f111bfdaf4384a0b6`;
its historical dirty worktree prevents a reproducible-source claim.

The checker rejects 69 guest-log, 36 host-log and five replay-media mutations,
unsafe IPA members and changed/missing/extra resources. Missing, truncated and
x86-64 kernels are rejected before touching serial or firmware state. The full
auditor compares extracted guest resources and binaries with recorded inputs.

Archive verification, full restoration, comparison of the complete typed
inventory and the unchanged saved auditor all pass. The restored capture was
returned to its recorded path before running that auditor; the original copy
remained available throughout validation. Archiver revision `af4784177` stores
changed large regular files as bounded chunks and reads archive versions 1, 2
and 3. Its self-test covers
all five codecs, growth and shrinkage, shifted tar members, exact restoration,
old-version compatibility and corruption rejection. The first archive attempt
exhausted scratch space; the successful retry uses a separate 24 GiB RAM
volume. Independent audit and archive logs remain in
`audio-category-20261027-work` under the cache root below.

```text
Cache root: /Users/alex/Library/Caches/vinix-ios
Recorded expanded path:
/Volumes/VinixAudioActivation20261028/error-description-20261028
VM state: probe-no-ads-445041
Manifest SHA-256:
8b4028c3d90c69e6b4e418820ab287eb93c8fdc4f6f0ecd10ce99346e069df09

Persistent delta archive directory: error-description-20261028-archive
archive.sha256 SHA-256:
f5bb12f68d17d5fb10dede15366eed7ac986788b58fe9d65b1a2322784ab42d9

Required complete prior bundle: audio-activation-20261028
Prior manifest SHA-256:
de7250fa32fa839b75c69b51798c554bbd703c9d09c1c07b23db8a007296357f
```

The expanded capture uses temporary RAM storage; the archive is on persistent
disk. Restore its complete prior bundle first, following the
[activation checkpoint](audio-activation-checkpoint-20261028.md). Build
`tests/ios/evidence-delta-archive.v` at the recorded archiver revision with the
frozen V compiler, then use `verify ARCHIVE` and
`restore ARCHIVE FRESH_TARGET FRESH_WORK`. The archive includes its archiver
source, compression executables and non-system libraries; ARM64 macOS system
libraries remain prerequisites. Recreate the recorded expanded path before
running the saved `error-description check OUT`, with external scratch selected
through `VINIX_IOS_AUDIT_TMPDIR`.
