# Returning AGX worker scheduling

`v run tests/agx-worker/run.v` extracts the production G13 and G17 event
workers and fake dependency wait into a host fixture. ASan/UBSan runs with
`-gc none -manualfree`. A fatal `yield` stub models the verified non-returning
scheduler API; `reschedule` delivers later work with manager locks released.

The suite covers 40 multi-cycle worker cases and 96 delayed, ready, null and
mixed dependency cases. It checks later message consumption, failure shutdown,
final maintenance and the first dependency error. This exercises production
control flow with stubbed transport and fences, not native scheduler execution.
`AGX_WORKER_C` and `AGX_WORKER_BINARY` retain generated artifacts externally.
Temporary fixtures are removed before returning either success or failure.

For counterexamples, supply a baseline directory containing `gpu.v`, `g17.v`
and `fake.v` plus a fresh external output directory:

```sh
v -o /external/worker-run tests/agx-worker/run.v
v run tests/agx-worker/counterexamples.v /external/worker-run /external/baseline /external/negative
v run tests/agx-worker/check.v --host /external/test.c
v run tests/agx-worker/check.v --selftest /external/test.c
v run tests/agx-worker/check.v --native /external/blob-aarch64.c /external/baseline/blob-aarch64.c
```

Eight compiled negatives reject all three old calls, each omitted handoff,
missing shutdown and a swallowed dependency error. Nine C mutations cover the
three loops' handoffs and allocation guards. Native C comparison permits only
the three substitutions, resolving interned strings by value and normalizing
the numeric path hash in discard-variable names. Nine scheduler, fence,
termination, service and cleanup bodies must match the baseline. Source guards
also check both architectures' returning APIs and terminal worker teardown.

`prepare.v` verifies and reuses the previous complete bundle's native qualifier,
then overlays all three changed sources into its private worktree. `native.v`
limits builds to two jobs and retains binaries, C and source inventories.
The historical strict x86 comparison and required allocation checker retain
their original contracts. `reclaim-cache.v` only removes recognized compiler
cache entries excluded from a completed task's verified complete bundle; its
commit, archive and inventory hashes must match the original report and receipt.
Unknown entries and all canonical evidence remain untouched.

`evidence.v --seal STATE` checks results, preserves complete sources and
artifacts, verifies a typed inventory, archives everything and checks a full
restoration. After the report records its hashes and the feature is committed,
`--bind STATE COMMIT` verifies the exact committed paths and bytes. `--cleanup
STATE` then removes only the private worktree and verified restoration.

The qualification and remaining limits are in
[the worker report](../../docs/m1-agx-worker-reschedule.md). No hardware,
firmware interaction, boot or reboot is performed by these tests.
