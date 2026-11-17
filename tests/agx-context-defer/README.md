# Deferred G13 context invalidation

`v run tests/agx-context-retire/run.v` now runs both the 3,672 retirement cases
and 1,008 additional four-context cases with ASan/UBSan, `-gc none -manualfree`.
Use `ASAN_OPTIONS=detect_stack_use_after_return=1`. All 24 release permutations,
two ABIs and three ring positions cover immediate acknowledgement, ambiguous
doorbell failure, timeout, device/fault transitions and full/corrupt channels.
The model expects release FIFO, deferral until borrow, one detached snapshot,
single requeue of unpublished failures and no replay of published failures.
It verifies every sent command's raw ID/pointer bytes and retains mapped owners.
An additional case extracts actual stopped queue cleanup, checks roots/links
before backing release and poisons the former node before another drain.

The existing retirement suite now requests retirement, drains at the modeled
borrow boundary, then retries cleanup. Its 11 compiled counterexamples retain
the ABI, acknowledgement, GC-snapshot and lifetime assertions; the baseline
also demonstrates the old inline-publication mismatch. A completion mutation
is scoped to the synchronous helper, independently of the new deferred gate.
Timer, doorbell, UAT and PMM services remain instrumented host services.

`check.v --native CURRENT_ARM_C BASELINE_ARM_C` checks exact native bodies for
the intrusive append, request and snapshot drain. Pointer identity, next-before-
mutation ordering and absence of allocations/file-lock paths are required.
Only the deferred gate, allocator-entry call, stopped link clearing and three
pointer defaults may change in the compared existing bodies/layouts. Thirty
ABI, heap, backing, ownership and acknowledgement bodies must match. `--selftest`
rejects eight FIFO, snapshot, replay, link, identity, gate and entry mutations.
Historical C/evidence checkers keep their original inputs and contracts.

`qualify.v STATE` creates a private worktree at the recorded baseline, links
the untracked kernel dependencies and overlays the three changed production
files. It verifies the unchanged native runner source against the preceding
complete bundle. Build `tests/agx-worker/native.v` externally and run it for
both architectures and allocation reporting. `evidence.v --seal STATE` checks
the preceding full bundle, retains complete current sources/results and checks
both the typed inventory and full archive restoration. After commit, `--bind
STATE COMMIT` checks exact paths/bytes; `--cleanup STATE` removes only the private
build worktree and verified restore.

Vinix retains the queue graph and VM until the later acknowledgement and UAT
cleanup. Asahi's deferred list holds only its context object. Idle retention,
backing timing, native rates and broader parity remain unqualified; see
[the report](../../docs/m1-agx-context-defer.md).
