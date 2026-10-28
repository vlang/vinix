# Audio session configuration checkpoint — 2026-10-28

Runtime, fixtures and saved auditor:
`84ac521908769463e17a343766784947d7c41ce3`. Advertising remains skipped.

`AVAudioSession setCategory:mode:options:error:` now stores validated desired
configuration for an inactive output session. SoloAmbient, Ambient and Playback
with the default mode support their implemented output options. The getters
return immutable canonical values, including implied mixing options. Invalid
arguments return `NSOSStatusErrorDomain` error -50; input, processing, multiroute
and valid nondefault mode requests return resource-unavailable error
561145203. Failures preserve the prior configuration. Activation, recording,
routes and audio output still require a backend.

Regular and deterministic ASan/UBSan runs pass for both the new fixture and the
category regression. The tests cover BOOL/NSUInteger/NSError ABI, concrete IMP
calls, mutable arguments, option validation, eight concurrent workers and two
fully drained runtime lifetimes. Native Catalyst metadata agrees; native audio
server behavior is unverified.

All 32 ARM64 guest fixtures pass. With the original cooked content, Fortnite
passes the category setter and stops at
`AVAudioSession setAllowHapticsAndSystemSoundsDuringRecording:error:`. Three
images, nine `+load` calls, three initializer groups and application entry
complete. The game exits 1 and the capture exits 0. No application signal fault,
OOM event or supervisor kill occurs. The desktop peer records 14 builds and
13 polls before its pipe closes; its first tree has one node, zero images and
336 bytes. This peer has no compositor.

The single-CPU 8 GiB guest retains the tagged 24 GiB reservation, enforced 2 GiB
application budget and 1,800-second limit. Budget enforcement and supervisor
isolation checks pass. Final application usage is 327,862 bytes; all OOM
counters are zero. Progress remains **4/8 observable launch gates (50% of the
checklist)**: load/bind, `+load`, initialization and application entry. A frame,
menu, login and playable match remain unverified. This fraction estimates
neither remaining work nor time. A Metal execution and presentation backend is
still absent.

The complete preceding string-comparison bundle passes its unchanged auditor.
Its original IPA, 95 resource files (1,831,863,828 bytes) and 31 fixture binaries
and generated C are reused unchanged. The runtime, supervisor and audio
configuration fixture are rebuilt. The 708 selected input hashes do not cover
complete compiler, header and library closures. The retained kernel's hash is
`1aaa1a692fffb653d75787af7df0848b62a0db17af86705f111bfdaf4384a0b6`;
its historical dirty worktree prevents a reproducible-source claim.

The checker rejects 63 guest-log mutations, 32 host-log mutations and five
replay-media mutations, unsafe IPA members and changed/missing/extra resources.
Missing, truncated and x86-64 kernels are rejected before touching serial or
firmware state. The full auditor compares extracted guest resources and
binaries with the recorded inputs.

The sealed 8.3 GiB bundle was restored into a fresh directory from the 86 MiB
delta archive. Every recorded file, type, permission, size and hash matches.
The restored bundle's unchanged saved auditor passes at the original path.
Its first resource extraction exhausted disk space; a second check with
RAM-disk scratch passed without modifying the sealed bundle. Only the redundant
pre-restore expanded copy was removed after that pass. Independent logs remain
outside the bundle in `audio-category-20261027-work` under the cache root below.

```text
Cache root: /Users/alex/Library/Caches/vinix-ios
Expanded bundle: audio-configuration-20261028
VM state: probe-no-ads-2038083
Manifest SHA-256:
2479d14793419e1915cbf818e49ccacbf00a0f728bf5a59819e225796e429bf1

Delta archive directory: audio-configuration-20261028-archive
archive.sha256 SHA-256:
d9bdf37dcb7fdcb8ab18c591837829ea9bd3ea8b5d685dcbd5e75e3200f54a69

Required complete prior bundle: string-compare-20261028
Prior manifest SHA-256:
032551d6c59da7fd7118dc4111c127e6b6e67f6709f9765541b02f95ea9b72f9
```

The delta archive requires the preceding complete comparison bundle; its
standalone archive and checksum are recorded in the
[comparison checkpoint](string-compare-checkpoint-20261028.md). Build
`tests/ios/evidence-delta-archive.v` with the recorded frozen V compiler, then
use `verify ARCHIVE` and `restore ARCHIVE FRESH_TARGET FRESH_WORK`. The archive
includes the archiver source, compression executables and non-system libraries;
the ARM64 macOS system libraries remain prerequisites. Restore the complete
bundle to its recorded path before running its saved `audio-configuration check
OUT`, with external scratch selected through `VINIX_IOS_AUDIT_TMPDIR`.
