# Audio session activation checkpoint — 2026-10-28

Runtime, fixtures and saved auditor:
`df1002df04d0df91bfbfa5d00c102d348c4d3df6`. Advertising remains skipped.

`AVAudioSession setActive:error:` now reports the absent audio provider:
activation returns false and an autoreleased NSError with domain
`NSOSStatusErrorDomain` and code 561145203 (`!res`). Deactivation succeeds and
preserves the caller's error output. Neither operation changes the desired
configuration or claims an active session. Only the low BOOL byte is decoded.

Regular and deterministic ASan/UBSan runs pass for activation and the
configuration regression. Tests cover native Catalyst ABI metadata, direct IMP
calls, nil error output, error ownership across pool drainage, unchanged
configuration, eight workers and two drained runtime lifetimes. Native
audio-server calls remain unverified. All 34 ARM64 guest fixtures pass.

Fortnite passes the activation setter and stops at `NSError description`.
Three images, nine `+load` calls, three initializer groups and application entry
complete. The application exits 1 and capture exits 0, without an application
signal fault, OOM event or supervisor kill. The desktop peer records 12 builds
and 11 polls; its first tree has one node, zero images and 336 bytes. The peer
has no compositor, so these exchanges establish no rendered game frame.

The single-CPU 8 GiB guest retains the tagged 24 GiB reservation, enforced
2 GiB application budget and 1,800-second limit. Budget enforcement and
supervisor isolation checks pass. Final application usage is 327,862 bytes;
all OOM counters are zero. Progress remains **4/8 observable launch gates
(50% of the checklist)**. Frame, menu, login and playable match remain
unverified. The fraction estimates neither remaining effort nor time. Audio
output and Metal execution and presentation still need backends.

The preceding complete recording-policy bundle passes its unchanged auditor.
Its original IPA, 95 resource files (1,831,863,828 bytes), and 33 fixture
binaries and generated C are reused unchanged. Runtime, supervisor and
activation fixture are rebuilt. The 708 selected input hashes do not cover
complete compiler, header and library closures. The retained kernel hash is
`1aaa1a692fffb653d75787af7df0848b62a0db17af86705f111bfdaf4384a0b6`;
its historical dirty worktree prevents a reproducible-source claim.

The checker rejects 67 guest-log, 32 host-log and five replay-media mutations,
unsafe IPA members and changed/missing/extra resources. Missing, truncated and
x86-64 kernels are rejected before touching serial or firmware state. The full
auditor compares extracted guest resources and binaries with recorded inputs.

The sealed 8.3 GiB bundle restores exactly from its persistent delta archive:
files, types, permissions, sizes and hashes match, and the restored bundle's
unchanged auditor passes at its original path. The boot image exceeded zstd's
2 GiB patch limit; archiver revision `327787ff3` uses streaming compression for
that image. Full archive self-tests, including boundary checks and corruption
rejection, pass. Independent archive, restore, comparison and audit logs remain
in `audio-category-20261027-work` under the cache root below.

```text
Cache root: /Users/alex/Library/Caches/vinix-ios
Recorded expanded path:
/Volumes/VinixAudioHaptics20261028/audio-activation-20261028
VM state: probe-no-ads-514500
Manifest SHA-256:
de7250fa32fa839b75c69b51798c554bbd703c9d09c1c07b23db8a007296357f

Persistent delta archive directory: audio-activation-20261028-archive
archive.sha256 SHA-256:
cd8da1fee2daa07797cfc25355e0ed46083c4ac84b31da37c367a180cc2daa1f

Required complete prior bundle: audio-haptics-20261028
Prior manifest SHA-256:
2f4014cddde3ce74fe5a99143e6e325001b47008f77ddf9c1c6205cf7e609a4a
```

The expanded capture uses temporary RAM storage; the archive is on persistent
disk. Restore its complete prior bundle first, following the
[recording-policy checkpoint](audio-haptics-checkpoint-20261028.md). Build
`tests/ios/evidence-delta-archive.v` at the recorded archiver revision with the
frozen V compiler, then use `verify ARCHIVE` and
`restore ARCHIVE FRESH_TARGET FRESH_WORK`. The archive includes its archiver
source, compression executables and non-system libraries; ARM64 macOS system
libraries remain prerequisites. Recreate the recorded expanded path before
running the saved `audio-activation check OUT`, with external scratch selected
through `VINIX_IOS_AUDIT_TMPDIR`.
