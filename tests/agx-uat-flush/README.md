Compile `run.v` externally, then run with
`ASAN_OPTIONS=detect_stack_use_after_return=1`. The runner uses
`-gc none -manualfree` and ASan/UBSan. It extracts the production GPU flush,
the real handoff layouts and the actual begin/complete/abort methods, and copies
the production channel and firmware message implementation. Only hardware time,
privileged barriers, transport delivery and kernel locks use host services.

The 432 cases cover delayed and immediate consumption, the extra kernel slot,
modulo wrap, send failure, timeout, error/stopped transitions, incomplete handoff,
busy slots, full/corrupt rings, uninitialized handoff, unsupported hardware and
both caller lock states. Completion cases check corrupt pointers, an unexpected
in-range write pointer, a latched channel fault and a stopped manager concurrent
with acknowledgement. The fixture checks lock release, unpublished rollback,
unrelated slots and retention of published failures. A retained failure must
reject another request before fixture reset. A delayed request after that reset
checks lock release again. Another 24 invalid requests check that the ring,
handoff, device state and caller lock are preserved.
Five page-count cases cover single- and multi-page flushes, the largest
16-bit count, and the first two wrapped counts. Each retains the full byte
range in the handoff.

Fourteen kernel teardown cases combine the production FwCtl handshake with
real page-table edits and a TLB recorder on both roots. They cover uncached
unmap, delayed acknowledgement, ring-full retry, missing handoff
acknowledgement, failed send, corrupt completion and partial reprotect. A corrupt
completion keeps the leaf valid and uncached, retains its physical backing and
skips the final invalidation. The recorder checks
the lower root's ASID-0 range and the upper root's global invalidations.
Retries preserve cache obligations and avoid sending after unmap.

The scheduler stub fails if called: a no-op stub would hide the original bug.
The original production source fails the delayed-acknowledgement case at this
stub. Fake time supplies the firmware acknowledgement from inside the polling
loop. No fixture executes the native scheduler or firmware.

`AGX_UAT_FLUSH_C` and `AGX_UAT_FLUSH_BINARY` retain evidence externally.
`--manager-source PATH` selects an original or mutated manager source.
`counterexamples.v RUNNER BASELINE_MANAGER FRESH_DIRECTORY` retains nine
compiled runtime negatives, including the old fixed page count.
The historical scheduler-fix bundle uses `check.v --host C`, `--selftest C`,
`--native CURRENT BASELINE` and `--allocations CURRENT BASELINE` to check the
original poll, five checker mutations, the exact native wait-primitive change
and allocation reports. Its native comparison resolves interned strings by
value before comparing bodies. The current completion checks and evidence are
recorded in [the UAT polling report](../../docs/m1-agx-uat-poll.md).

Native builds use the existing `tests/agx-heap-gc/qualify.v` worktree runner.
Historical heap-GC checkers keep their original contracts and complete bundles.
The UAT poll fix has no new allocation, ownership field or handoff state.
