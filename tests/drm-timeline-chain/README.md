# Modern Asahi cumulative timeline chains

The production syncobj implementation reserves fallible chain nodes before
modern output publication. Each root waits for its leaf and complete previous
prefix. Embedded parent-owned waiters propagate completion through a locked
queue without recursive callbacks or allocation. Published metadata retains
Vinix's existing lifetime; only unpublished reservations are freed.

```sh
v run tests/drm-timeline-chain/verify.v host /external/state/qualified-host
v run tests/drm-timeline-chain/verify.v negative /external/state/negative-final
v run tests/drm-timeline-chain/native.v prepare /external/state/qualified-host
v run tests/drm-timeline-chain/native.v aarch64 /external/state/qualified-host
v run tests/drm-timeline-chain/native.v x86_64 /external/state/qualified-host
v run tests/drm-timeline-chain/native.v allocations /external/state/qualified-host
v run tests/drm-timeline-chain/native.v contracts /external/state/qualified-host
v run tests/drm-timeline-chain/verify.v native /external/state/qualified-host
v run tests/drm-timeline-chain/evidence.v validate /external/state
v run tests/drm-timeline-chain/evidence.v seal /external/state
v run tests/drm-timeline-chain/evidence.v bind /external/state COMMIT
```

Use fresh external paths. Native builds start at
`85fa9142e09f7ede076fd645ec4bca8f6b2cea17` with nine owned kernel overlays,
excluding concurrent event-manager edits. Host checks use production functions
with deterministic allocator, lock and scheduler fixtures. The Linux oracle
compiles unchanged pinned chain init/walk/find functions with single-thread
refcount/RCU/lockdep stubs and compares 41,472 native outcomes. It does not
qualify Linux concurrency or reclamation. Reference and prior-evidence paths
are explicit in the runners.

`checks.v` covers prefix readiness, skipped retired leaves, duplicate/decreasing
and unsigned boundary points, binary predecessors, stable publication captures,
poll cancellation, exact-lock registration races and 10,000 reverse completions.
`modern_checks.v` tests every OOM position for 1/3/64/65/129 output records, real
two-queue submission callbacks, captured same-queue inputs, valid nil retired
dependencies and later packet rollback. The malloc-zone probe measures nine
warmed 1,000-cycle batches of unpublished reservations at 1/65/129 outputs.
Published metadata retention is explicitly excluded from that measurement.

`info_checks.v` tests actual sync-file reporting, including a retirement between
count and fill passes: actual count shrinks, but the original-sized zeroed tail
still gets copied. Three compiled negatives must fail designated assertions.
The native C guard detects hidden allocations, including boxing the by-value
sync array in cleanup. Existing first-completion, poll and info source guards
retain their negative controls after adapting to shared completion/unwrapping.

Legacy timeline maps, generic timeline ioctls, merge/array containers, metadata
reclamation, allocation-policy parity, lazy callback/timestamp timing, actual
multi-CPU races and hardware acceptance remain incomplete or unqualified.
