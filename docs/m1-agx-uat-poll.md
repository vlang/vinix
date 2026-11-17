# Returning G13 UAT completion polling

G13 firmware-control UAT invalidation now waits with `katomic.sync()` instead
of `sched.yield(false)`. On ARM, the latter enters the explicitly non-returning
`idle_after_dying_thread()` path. A delayed firmware response could therefore
abandon the live transaction while it still owned `fwctl_lock`, preventing its
deferred unlock and handoff completion. Barrier polling keeps the caller active
until acknowledgement, device failure or the existing one-second timeout.

The production change is one wait primitive and its explanatory comment.
Validation, publication, token comparison, timeout, error state, handoff
completion and deferred unlock remain unchanged. Unpublished enqueue failures
alone roll back the reserved slot; published failures retain it. Caller-held
manager locks remain held on return. No allocation, owning field or handoff
state is added. Independent lifetime review found no blocker; hardware counter
time continues with interrupts disabled.

Offline validation passed:

- The actual pre-fix manager fails a delayed-acknowledgement host case at a
  fatal scheduler stub. The stub reflects the verified ARM scheduler contract;
  it does not execute the native scheduler or claim a hardware reproduction.
- ASan/UBSan with `-gc none -manualfree` and fake-stack detection passes 312
  production channel/handoff cases plus 24 invalid requests. The fixture uses
  the real begin/complete/abort methods and firmware messages. It covers delayed
  responses, ring wrap, user/kernel slots, caller lock states, timeout, failed
  sends, device transitions, incomplete handoff, full/corrupt rings and busy
  slots. Published failures reject reuse before explicit fixture reset; a
  delayed request after reset verifies the unlock/return path again.
- Eight compiled negatives reject the old scheduler call, missing token wait,
  ignored handoff, missing unpublished rollback, unsafe published rollback,
  missing unlock, zero timeout and inverted token comparison. Five C-checker
  mutations are rejected. All 66 focused test files pass; the audit unit test
  also passes after adding the scheduler source to its snapshots.
- Both isolated native builds pass. ARM C reduces exactly to the baseline
  after restoring the scheduler call. Eleven existing handoff, ring, backing
  and cache-GC bodies match after resolving interned strings by value. The
  original strict checker compares x86 C against a fresh control generated
  with the current compiler. The UAT body contains no allocation or scheduler call.
- Allocation sites and source counts match the predecessor: 379 sites / 834
  files on ARM, 289 / 813 on x86. Per-file/per-kind counts and existing
  allowance-check failures remain unchanged. No allowance was edited.

Whole-driver audit: **not_equivalent**. This fixes the UAT wait's return path;
it does not establish native timing, scheduler fairness or full firmware
lifecycle correctness. Other AGX worker paths still use `sched.yield(false)`
and require separate review. Legacy eager GC, allocator backing/accounting,
modern UAPI/Mesa integration, remaining stage backing/event destruction,
firmware/cache teardown, timestamps, fences/timelines, wire defaults, topology
and power/reset remain incomplete or unqualified.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-uat-poll-20261117/`.
Baseline revision is `04063daed04d9f524daabeec600d9d460c51f09b`; only the GPU
manager source differs in the isolated kernel worktree. The complete bundle
retains test sources, binaries, generated C, native input inventories, source
audit, negative cases and review. The historical inventory checker verifies the
bundle and full archive restoration. `completion.txt` binds committed feature
sources and reports to that evidence. Results remain outside Git.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `73e8dbdb3600aac50b6c51f3aeb04992cf2db84331e90cc145d9edf0f7f35a66` |
| `bundle.tar.gz` | `724ddd80c04ce63203a3df57ee81bfa3b613337addb68c0b569d0f2f94aae420` |
| `bundle/vinix-aarch64` | `d79f2f4ba12387a8b2de149caffb25a5c7e3fdd83016126c3c79b7adfa344019` |
| `bundle/vinix-x86_64` | `e708931382eb101e3e74e7fd95ae916626dcfdc94e0b4613bcfc9ababa02c996` |
| `bundle/blob-aarch64.c` | `9455a437065ba52c2693a1ff2a9075076c4fb717ccafba9e37ba725dc6136b4a` |

No GPU workload, firmware interaction, Vinix/QEMU boot, reboot, SSH or deployment occurred.
