# DRM timeline QUERY

QUERY has a 24-byte read/write header and writes one u64 point per handle. It
resolves the complete handle array before outputs, then samples each retained
object's current head separately. Empty/binary objects return zero. Timeline
queries select completed progress in the head context or LAST_SUBMITTED.

```sh
v run tests/drm-syncobj-query/run.v host /external/state/host-final
v run tests/drm-syncobj-query/run.v negative /external/state/negative
v run tests/drm-syncobj-query/native.v prepare /external/state
v run tests/drm-syncobj-query/native.v aarch64 /external/state
v run tests/drm-syncobj-query/native.v x86_64 /external/state
v run tests/drm-syncobj-query/native.v allocations /external/state
v run tests/drm-syncobj-query/native.v contracts /external/state
v run tests/drm-syncobj-query/run.v native /external/state
v run tests/drm-syncobj-query/evidence.v validate /external/state
v run tests/drm-syncobj-query/evidence.v seal /external/state
v run tests/drm-syncobj-query/evidence.v bind /external/state COMMIT
```

Use fresh external paths. Host tests preserve the executable, generated C and logs;
the kernel build runner pins `0b9e112f8982754269b845809f1a6a73b486ff81` plus four
owned kernel overlays. It excludes concurrent event-manager changes. The test
fixtures measure every temporary-buffer owner and exercise 1/64/65/129/4096
handles, errors before output, partial copy faults and handle reuse/publication
between outputs. Three negative variants must compile and fail designated tests.

The oracle compares 10,368 production results with unchanged pinned Linux
QUERY and chain init/walk/signaled bodies. It requires the preceding complete
chain bundle and runs its unchanged archive checker before reusing its plumbing.
Allocator/refcount/RCU/usercopy/feature checks are host stubs. This comparison
does not qualify kernel concurrency or hardware behavior.

Vinix uses inline storage through 64 records and a combined allocation beyond
it; Linux uses two allocations. OOM/fault precedence is therefore not equivalent.
The generic timeline capability remains disabled pending wait/signal/transfer.
Legacy maps, published metadata reclamation, Mesa migration and hardware parity
remain outside this increment. No Vinix/QEMU boot or reboot is needed.
