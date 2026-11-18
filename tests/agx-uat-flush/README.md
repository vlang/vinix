Compile `run.v` externally, then run with
`ASAN_OPTIONS=detect_stack_use_after_return=1`. The runner uses
`-gc none -manualfree` and ASan/UBSan. It extracts the production GPU flush,
the real handoff layouts and the actual begin/complete/abort methods, and copies
the production channel and firmware message implementation. Only hardware time,
privileged barriers, transport delivery and kernel locks use host services.

The 312 cases cover delayed/immediate consumption, the extra kernel slot,
modulo wrap, send failure, timeout, error/stopped transitions, incomplete handoff,
busy slots, full/corrupt rings, uninitialized handoff, unsupported hardware and
both caller lock states. They check unlock on every return, unchanged unrelated
slots, unpublished rollback and published-failure retention. A retained failure
must reject another request before fixture reset. A delayed request after that
reset checks the return/unlock path again. Another 24 invalid requests must
leave the ring, handoff, device state and caller lock untouched.
Five page-count cases cover single- and multi-page flushes, the largest
16-bit count, and the first two wrapped counts. Each retains the full byte
range in the handoff.

Twelve kernel teardown cases combine the production FwCtl handshake with
real page-table edits and a TLB recorder on both roots. They cover uncached
unmap, delayed acknowledgement, ring-full retry, missing handoff
acknowledgement, failed send, and partial reprotect. The recorder checks
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
`check.v --host C`, `--selftest C`,
`--native CURRENT BASELINE` and `--allocations CURRENT BASELINE` check the poll,
five checker mutations, the exact native wait-primitive transformation and
unchanged allocation reports. Native comparison resolves interned strings by
value before comparing bodies; it does not discard control-flow differences.

Native builds use the existing `tests/agx-heap-gc/qualify.v` worktree runner.
Historical heap-GC checkers keep their original contracts and complete bundles.
The UAT poll fix has no new allocation, ownership field or handoff state.
