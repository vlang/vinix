# UIApplication badge clearing checkpoint — 2026-10-26

Implementation and inventoried source revision: `50085404120e44fa113e72bc5f572f39f0a55dd4`.
Advertising remains skipped.

`UIApplication.applicationIconBadgeNumber` now reports zero and
`setApplicationIconBadgeNumber:0` clears the absent badge. Both expose the
native signed 64-bit Objective-C signatures. Nonzero counts fail explicitly
because there is no launcher badge backend.

The shared Catalyst/runtime fixture checks defaults, repeated clears,
reflection, signatures, direct IMP calls, subclass behavior and independence
from the idle timer. Two runtime lifetimes drain completely. Isolated child
processes verify rejection of positive, negative and full-width counts.
Normal and deterministic-hashing ASan/UBSan host runs pass; leak detection is
disabled. The isolated native inspection confirms the method signatures and
default/clear behavior. It does not establish badge authorization or display
semantics for a running native application.

All 14 ARM64 guest builds and all 12 guest regression fixtures pass.
The build wrapper runs up to four independent jobs and retains each command,
log and exit status. Complete window, storyboard and alert host artifacts
are inherited without rerunning from source revision
`6d2639b7a0486823456cecd33ef74519a70d8787`, bundle
`/Users/alex/Library/Caches/vinix-ios/window-20261026`, manifest SHA-256
`55a48d4d9db015cf83e393022e88585270559db8e84e3ac092df685cbac95d9f`.

The unchanged Fortnite 42.30.1 executable has SHA-256
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
The badge selector stop is gone. Three images load/bind, nine `+load` calls
and three initializer groups return, and application entry is reached.
The next observed stop is:

```text
V panic: iOS: application icon badge count -1 requires a badge backend
```

Application exit is 1 (wait status 256); the diagnostic harness exits zero.
Progress remains **4/8 observable gates (50% of this checklist)**. A rendered
frame, interactive menu, login and playable match remain unverified. This
fraction does not estimate remaining work or time. `--probe-no-ads` binds
SKAdNetwork to nil and changes application behavior; this is a diagnostic run.

All 13 inline pthread-self reads are translated. The tagged 24 GiB virtual
reservation succeeds without committing that much physical memory. Seven
headroom queries return positive values within the 2 GiB cgroup limit; final
application OOM counters are zero. The sole signal fault is the deliberate
regression fixture, which captures all 31 ARM64 registers and restores execution.

Complete evidence is outside Git at
`/Users/alex/Library/Caches/vinix-ios/application-badge-20261026`.
It contains 1194 source records, 696 selected
build-input records and 1965 manifest records. The selected
guest state is `probe-no-ads-503541`. SHA-256 of `manifest.sha256`:

```text
c03b2a1725ee064cbf84f516723f1fa209915038bca24cc23e88acac13fdbca5
```

`application-badge-evidence` seal, independent check and mutation selftest
pass. The checker retains the previous startup, VM reservation, memory,
fault, exit and complete-bundle requirements, and rejects missing badge guest
or host validation, failed fixture waits and missing native/provenance evidence.
Historical checkers remain unchanged. The prebuilt kernel is inventoried,
not rebuilt from concurrent edits. Selected hashes do not seal complete
compiler, header or host-library closures.

Reproduce with the frozen V compiler and flags documented in the
[window checkpoint](window-checkpoint-20261026.md), building
`notification-checks.v`, `notification-vm.v`, `application-badge-run.v`,
`image-initializers-input-inventory.v` and `application-badge-evidence.v`.
In a fresh external bundle, retain the complete inherited artifacts and their
provenance, run `application-badge-host`, `application-badge-inspector-build`
and `application-badge-inspect` through `notification-checks`, then wrapper
`build` and `probe`. Capture inventories at the source revision, then run
evidence `seal`, `check`, `selftest` and `hash`.
