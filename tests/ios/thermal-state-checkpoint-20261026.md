# Process thermal-state checkpoint — 2026-10-26

Implementation and inventoried source:
`8f700726447c1f901faff30071069a621152b86f`. Advertising remains skipped.

`NSProcessInfo.thermalState` now returns nominal (0) when no Darwin
thermal-awareness provider is available, following Foundation's documented
fallback. It is a read-only instance property with the signed 64-bit
`NSInteger` ABI and encoding `q16@0:8`. This does not connect Vinix thermal
sensors or implement thermal-state notifications.

Fresh validation passes:

- Eight host build/execution steps, including normal and deterministic-hashing
  ASan/UBSan runs. Apple's native property checks cover the enum, reflection,
  method signature and direct IMP calls. Runtime checks cover inheritance,
  preserved registers and errno, concurrent readers and two drained lifetimes.
  Leak detection is disabled; sanitizer errors remain fatal.
- All 15 ARM64 guest builds and all 13 guest regression fixtures, including
  the new thermal-state cases. Every fixture has wait status zero.
- Evidence seal, independent check and mutation selftest. Checks reject
  missing validation cases or guest media, resource differences against the
  preserved guest archive, failed fixture/build statuses, changed startup
  boundaries, invented completion/accounting, unexpected faults or panics,
  altered logs and unmanifested files.

The unchanged Fortnite 42.30.1 executable has SHA-256
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
It passes the former thermal-state panic and reaches:

```text
iOS: UIKit apps must be launched by the Vinix desktop (VINIX_REQUEST_FD/VINIX_RESPONSE_FD)
```

This probe does not supply the desktop protocol pipes. After that message,
the guest remains incomplete until the VM harness's roughly 240-second
timeout; the host harness exits 1. There is no observed natural application
exit, completed probe or final application OOM accounting. The timeout does
not establish why the process remains alive. The next integration step is a
launch with a real desktop connection.

Progress remains **4/8 observable gates (50% of this checklist)**: image
load/binding, Objective-C `+load`, image initialization and application entry
are verified. A rendered frame, interactive menu, login and playable match
remain unverified. This fraction does not estimate remaining work or time.
`--probe-no-ads` binds SKAdNetwork to nil and changes application behavior;
this remains a diagnostic launch.

Three images load/bind, nine `+load` calls and three initializer groups return.
All 13 inline pthread-self reads are translated. The tagged 24 GiB virtual
reservation succeeds, and seven headroom queries stay positive within the
2 GiB cgroup limit. The sole signal fault belongs to the deliberate fixture,
which captures all 31 ARM64 registers and restores execution. No application
fault is observed before the timeout; final application OOM counters are
unavailable.

Complete evidence is preserved outside Git at
`/Users/alex/Library/Caches/vinix-ios/thermal-state-20261026`:
1205 source records, 698 selected build-input records and 1565 manifest
records. The selected VM state is `probe-no-ads-1659166`.
SHA-256 of `manifest.sha256`:

```text
d815747b8f635da1853425374b47f7f61015de03d941959c8bd6b03ea357d53e
```

The first staging attempt failed before boot because the host disk filled.
Its logs, status and cleanup record remain in the bundle. Only that incomplete
attempt's staging was removed. The new application copy uses an APFS clone;
all copied file hashes were verified against the prior bundle before replacing
this checkpoint's own ordinary copy. Historical evidence was preserved.

Preserve the complete prior bundle at
`/Users/alex/Library/Caches/vinix-ios/compiled-storyboard-20261026`, manifest
SHA-256 `3ae5be94ecc0c7664a0c41ecdef94fac56e660e7319596ae8824a028a8816619`.
Its independent checker passed again. Historical checkers are unchanged.
The prebuilt kernel is inventoried, not rebuilt; selected input hashes do not
seal complete compiler, header or host-library closures.

Reproduce with the frozen V compiler/environment from the
[window checkpoint](window-checkpoint-20261026.md), adding `tests/ios` to the
module path. Compile and run `thermal-state-prepare.v EXTERNAL_OUT
PRIOR_STORYBOARD_BUNDLE` against an existing, external, unsealed output
directory. It verifies the prior bundle and builds the five tools. Run
`notification-checks processinfo-host OUTPUT/host`, then `checkpoint-run build
OUTPUT`. Set `VINIX_IOS_STORYBOARD_BUNDLE=OUTPUT/application` for
`checkpoint-run probe OUTPUT`; this observed run returns 1 at the VM timeout.
Run `inventory-inputs ROOT OUTPUT SOURCE_REVISION`, then
`thermal-state-evidence seal|check|selftest OUTPUT` and hash the manifest.
Exact compiler/linker commands, statuses and generated artifacts are retained
in the bundle.
