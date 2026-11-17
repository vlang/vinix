# Logical queue record lifetime

`ASAN_OPTIONS=detect_stack_use_after_return=1 v run tests/agx-workqueue-records/run.v`
executes the production logical queue module and extracted fake driver owner
methods with instrumented locks, fences, VMs and GEM objects. It covers slot
cancellation, successful completion, borrowed items/fences, unlock before free,
143 pending/idle close and destroy cases, and first/middle/last row deletion.
`v run tests/agx-file-close/run.v` adds 51 heap-record owner cases and an aggregate
pin case to the existing native file fixture. Old stack/pool fixtures record
one-shot disposal tokens; new heap fixtures use the production disposer and
check ASan poisoning. These are host instrumentation, not firmware execution.

`MallocNanoZone=0 v run tests/agx-workqueue-records/run.v --measure` runs three
10,000-close batches with one warmed file and the real WorkQueue allocation.
`--fake-source FILE` selects baseline/mutated owner code for either mode.
The pinned baseline retains 10,000 records / 12,800,000 malloc-accounted bytes
on its first batch; the fixed code retains zero on all three. The fixture's
WorkQueue is 1,056 bytes; allocator rounding and its instrumented lock differ
from native kernel slab sizes and rates.

`AGX_WORKQUEUE_C` / `AGX_WORKQUEUE_BINARY` preserve fixture artifacts externally.
`counterexamples.v WORKQUEUE_RUNNER CLOSE_RUNNER FRESH_EXTERNAL_DIR` requires
seven compiled variants to fail named disposal, shifted-alias or inflight-gate
assertions. Compiler failure does not count. Runners clean their scratch roots
before returning either status.

`check.v --native CURRENT_C BASELINE_C` compares ARM generated C. It
requires only the exact owner changes, stable pointer copies before deletion,
one metadata free, the constructor's scalar local and unchanged object layouts.
Cancellation, completion, fake worker/submission and native capture/backing
bodies remain unchanged. `--selftest` rejects six compiled-C text mutations.
The original `tests/agx-g13-failure/check-completion-order.v BASELINE CURRENT
--x86` requires x86 C equality after its existing discard-path normalization;
the x86 kernel excludes this logical queue module. `check-allocations.v CURRENT
BASELINE` permits only the verified logical queue allocation to leave ARM's
report; x86 counts stay unchanged. Existing allowance failures stay.

`qualify.v STATE` prepares an isolated worktree at the pinned baseline with
three production overlays. `--refresh STATE` preserves the first ARM build and
copies the verified annotation for final native builds. `evidence.v` seals the
complete bundle, verifies archive restoration and binds committed paths/bytes.
See [the report](../../docs/m1-agx-workqueue-records.md).
