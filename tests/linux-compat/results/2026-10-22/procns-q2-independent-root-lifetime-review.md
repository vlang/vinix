# Independent queue lifetime review

Reviewer: `/root`, separate from implementer `/root/lifetime_review`.
Reviewed on 2026-10-22 against isolated commit
`bd9aa1bc1d04eac1ce31e02ce8914969294566ff` (Q2).

Inputs are the committed `kernel/fs/removed.v` in
`queue-fix/kernel-arm`, and the extracted complete `fs__reap_removed`
functions `queue-fix/generated-reaper-arm-track.c` and
`queue-fix/generated-reaper-x86-track.c`, relative to this evidence directory.
The sealed candidate input manifest pins the underlying generated C and kernels.

I reviewed the source and both tracking generated-C ownership paths. A full
drain transfers the complete array header under `removed_lock` and replaces the
shared queue with an empty header before unlocking. No detached array alias is
published. `retire` reapplies `.noslices` under that same lock before appending,
so concurrent retirement and callbacks use the replacement queue. Partial drains
retain the existing memcpy/delete-many transfer of owned item fields.

Callbacks and requeues run after unlock. The detached items buffer survives all
node/resource callbacks, owner checks and requeues, and is freed only after the
iteration; nodes and running scratch buffers are freed there too. Nested owned
resources retain their existing release paths. Q2 adds only the missing
`@[freed]` annotation on the already-freed partial-drain allocation.

No new lifetime blocker found. Repeated bursts may regrow the queue; partial
drains retain capacity until a full drain. The existing single-reaper contract,
five-second timed-reader assumption and permanent mount pins remain limits.
This review does not establish quiescence-based RCU or qualify unrelated shared
checkout edits. Runtime validation is separate and must retain strict slab and
big-page equality and the held-reference/racing-reader checks.
