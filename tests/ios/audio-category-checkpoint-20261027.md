# Audio session category checkpoint — 2026-10-27

Runtime and fixture: `b57e19d2ab245d69cbad8346ad1a372c30b7ae26`.
Audited replay runner and source snapshot:
`88c1947bcf0f79c7aff8c9ffb9d197b1fd1b5ae4`. Advertising remains skipped.

`AVAudioSession category` returns the shared `AVAudioSessionCategorySoloAmbient`
constant, the documented default. Instance-only method discovery, object return
metadata, direct IMP invocation, framework aliases and cache ownership pass.
Eight workers exercise both first-lookup orders and two drained runtimes.
Regular and deterministic ASan/UBSan runs pass, including the prior activity
query regression. Native Catalyst checks cover metadata and the constant;
native session calls remain unverified after the earlier audio-server XPC stall.
This change supplies no audio output backend or category setters.

All 30 ARM64 guest fixtures pass. With the original cooked content, Fortnite
passes the category getter and reaches `NSString compare:`. Three images, nine
Objective-C `+load` calls, three initializer groups and application entry complete.
The application exits 1, capture exits 0, and no application signal fault, OOM
event or supervisor kill occurs. The diagnostic desktop peer completes its
handshake, reports 12 builds and 11 polls, then observes a closed pipe. The first
tree has one node, zero images and 336 bytes; it establishes no game frame.

The 8 GiB guest retains the tagged 24 GiB reservation, enforced 2 GiB game budget
and 1800-second limit. Under-budget, over-budget and supervisor-isolation checks
pass unchanged. Final application cgroup usage is 327,862 bytes with zero OOM
counters. The peer supplies no compositor or input device.

Progress remains **4/8 observable launch gates (50% of this checklist)**:
load/bind, `+load`, initialization and application entry. Frame, menu, login and
playable match remain unverified. This fraction estimates neither remaining
effort nor time. Metal execution and presentation remain absent; the default
Metal device query returns nil.

The evidence preserves the original kernel's over-budget self-test failure,
the replacement kernel's provenance and disassembly, an interleaved four-CPU
capture, a stale-log replay and the incomplete firmware attempt. A stale log
was incorrectly accepted before QEMU opened its serial device; it is not counted
as an independent boot. The runner now clears the capture before launching.
One virtual CPU avoids interleaved serial characters. Invalid CPU configuration
is rejected before replacing firmware; the negative check preserves its hash.
The final capture is a fresh boot with complete firmware evidence.

The replacement kernel is an existing binary, SHA-256
`1aaa1a692fffb653d75787af7df0848b62a0db17af86705f111bfdaf4384a0b6`.
Its worktree HEAD alone does not certify its exact source because that worktree
has later edits. Disassembly and guest enforcement checks are retained; this
checkpoint does not claim a reproducible kernel build.

The saved auditor rejects 59 guest-log mutations, 32 host-log mutations, five
bad replay-media inventories, unsafe IPA members, malformed manifests and
changed, missing or extra resources. It compares extracted guest resources and
binaries against recorded inputs. Audit, seal and independent complete-bundle
verification pass. The first independent extraction ran out of disk space;
rerunning with RAM-disk scratch passed without changing the bundle. The complete expanded
bundle includes sources, IPA, resources, generated C, binaries, boot media,
firmware, attempts, logs and its saved auditor:

```text
/Users/alex/Library/Caches/vinix-ios/audio-category-20261027
VM state: probe-no-ads-kernel-upgrade
Manifest SHA-256:
5690ec96bf9beed7e741a122a08bda5ddb163eac92a76ec2780bed93a855aa85

Prior complete bundle:
/Users/alex/Library/Caches/vinix-ios/audio-activity-20261027
Prior manifest SHA-256:
57e4233a27ea5ede140e958ab92e0ed85c457d2c17b4baa3113460e813cfbc3c

IPA SHA-256:
47a17e723f8fae91595ac897d8f59cd3b453c43113a20bb1ff31ab656167332e
Executable SHA-256:
6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373
```

The original application and 95 resource files (1,831,863,828 bytes) are
unchanged. All 29 prior fixture binaries and generated C are reused unchanged;
the category fixture, runtime and supervisor are rebuilt. The overlay is not a
complete installation. The 708 selected input hashes do not seal complete
compiler, header and library closures. Historical expanded evidence is retained.
Independent validation logs are outside the sealed bundle at
`/Users/alex/Library/Caches/vinix-ios/audio-category-20261027-work`.

Build `tests/ios/audio-category.v` with the recorded frozen V compiler using
`-nocache -gc none -cc clang -cflags -O2` and a module path including `tests/ios`.
The retained auditor supports `check OUT`, `selftest OUT`, `summary OUT` and
`hash FILE` without rebuilding. `VINIX_IOS_AUDIT_TMPDIR` selects external
extraction scratch storage.
