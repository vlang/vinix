# Audio session recording-policy checkpoint — 2026-10-28

Runtime, fixtures and saved auditor:
`d6b82d4e2b10c88ea3c8626bf913b02a8cbaa293`. Advertising remains skipped.

`AVAudioSession setAllowHapticsAndSystemSoundsDuringRecording:error:` now
stores a desired inactive-session policy. The getter defaults to false and
returns a canonical BOOL. Updates are synchronized, preserve the independent
category configuration, and leave the caller's NSError output untouched on
success. This policy starts no audio, recording or haptics provider.

Regular and deterministic ASan/UBSan runs pass for the new fixture and the
configuration regression. Tests cover instance-only metadata, direct IMP calls,
BOOL register decoding, nil error output, unchanged error sentinels, category
success/failure independence, eight concurrent workers and two fully drained
runtime lifetimes. Native Catalyst metadata agrees; native audio-server calls
remain unverified.

All 33 ARM64 guest fixtures pass. With original cooked content, Fortnite passes
the policy setter and stops at `AVAudioSession setActive:error:`. Three images,
nine `+load` calls, three initializer groups and application entry complete.
The game exits 1 and the capture exits 0, without an application signal fault,
OOM event or supervisor kill. The desktop peer records 12 builds and 11 polls;
its first tree has one node, zero images and 336 bytes. It has no compositor.

The single-CPU 8 GiB guest retains the tagged 24 GiB reservation, enforced 2 GiB
application budget and 1,800-second limit. Budget enforcement and supervisor
isolation checks pass. Final application usage is 327,862 bytes; all OOM
counters are zero. Progress remains **4/8 observable launch gates (50% of the
checklist)**: load/bind, `+load`, initialization and application entry. Frame,
menu, login and playable match remain unverified. This fraction estimates
neither remaining effort nor time. Audio output and Metal execution and
presentation still need backends.

The preceding complete configuration bundle passes its unchanged auditor.
Its original IPA, 95 resource files (1,831,863,828 bytes), and 32 fixture
binaries and generated C are reused unchanged. The runtime, supervisor and
recording-policy fixture are rebuilt. The 708 selected input hashes do not
cover complete compiler, header and library closures. The retained kernel hash
is `1aaa1a692fffb653d75787af7df0848b62a0db17af86705f111bfdaf4384a0b6`;
its historical dirty worktree prevents a reproducible-source claim.

The checker rejects 65 guest-log mutations, 32 host-log mutations and five
replay-media mutations, unsafe IPA members and changed/missing/extra resources.
Missing, truncated and x86-64 kernels are rejected before touching serial or
firmware state. The full auditor compares extracted guest resources and
binaries with the recorded inputs.

The sealed 8.3 GiB bundle was restored into a fresh directory from its 80 MiB
delta archive. Every recorded file, type, permission, size and hash matches.
The restored bundle's unchanged saved auditor passes at the original path.
Independent check, archive, restore, comparison and restored-audit logs remain
in `audio-category-20261027-work` under the cache root below.

```text
Cache root: /Users/alex/Library/Caches/vinix-ios
Recorded expanded path:
/Volumes/VinixAudioHaptics20261028/audio-haptics-20261028
VM state: probe-no-ads-151375
Manifest SHA-256:
2f4014cddde3ce74fe5a99143e6e325001b47008f77ddf9c1c6205cf7e609a4a

Persistent delta archive directory: audio-haptics-20261028-archive
archive.sha256 SHA-256:
7bcc2dac54ed493a4f66f0fea5a3cb20f5f4cc57f131f1392e6016f811e474e3

Required complete prior bundle: audio-configuration-20261028
Prior manifest SHA-256:
2479d14793419e1915cbf818e49ccacbf00a0f728bf5a59819e225796e429bf1
```

The expanded capture uses temporary RAM storage; the archive is on persistent
disk. Restore its complete prior bundle first, following the
[configuration checkpoint](audio-configuration-checkpoint-20261028.md), which
also requires the complete comparison bundle. Build
`tests/ios/evidence-delta-archive.v` with the recorded frozen V compiler, then
use `verify ARCHIVE` and `restore ARCHIVE FRESH_TARGET FRESH_WORK`. The archive
includes the archiver source, compression executables and non-system libraries;
the ARM64 macOS system libraries remain prerequisites. Recreate the recorded
expanded path before running the saved `audio-haptics check OUT`, using external
scratch selected through `VINIX_IOS_AUDIT_TMPDIR`.
