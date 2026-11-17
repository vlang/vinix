# DRM timeline WAIT

The 48-byte timeline wait snapshots object identities and points, validates all
initial fences, then registers unresolved future points under each object's
publication lock. Captured fences survive reset, replacement and namespace reuse.
Retired prefixes are available completions. Every exit detaches borrowed capture
nodes before freeing their request tables. Binary waits keep their existing path.

```sh
v run tests/drm-timeline-wait/run.v host /external/state/host-final
v run tests/drm-timeline-wait/run.v negative /external/state/negative-final
v run tests/drm-timeline-wait/run.v measure /external/state/measure
v run tests/drm-timeline-wait/native.v prepare /external/state
v run tests/drm-timeline-wait/native.v aarch64 /external/state
v run tests/drm-timeline-wait/native.v x86_64 /external/state
v run tests/drm-timeline-wait/native.v allocations /external/state
v run tests/drm-timeline-wait/native.v contracts /external/state
v run tests/drm-timeline-wait/run.v native /external/state
v run tests/drm-timeline-wait/evidence.v validate /external/state
v run tests/drm-timeline-wait/evidence.v seal /external/state
v run tests/drm-timeline-wait/evidence.v bind /external/state COMMIT
```

Create the common external parent first; each host/negative/measure directory
must be fresh. Native builds pin `d3ae11cef54ea7f2ea493ce02e4e86960817dbb6`
plus six kernel overlays, excluding unrelated concurrent event edits.

The sanitized full DRM fixture includes 1,824 counted WAIT checks: 1..4096
handles, ALL/ANY and availability, every request-owner OOM position, invalid
points, null points, errors, signal interruption, timeout, reset/name/user-record
replacement, and publication between initial snapshot and arm. Large future
lists detach on completion, timeout and interruption, before later publication.
Three compiled negatives must fail designated unlink-before-free, availability
and two-phase registration assertions.

The pinned Linux oracle compiles unchanged WAIT timeout/array/ioctl and chain
init/walk/find/signaled bodies. Its 21,952 zero-timeout outcomes cover seven
head states per object, four point triples and all sixteen flag combinations.
Allocation/refcount/RCU/usercopy, callback and scheduler infrastructure are
single-thread host stubs. Linux errno numbers are explicit because Darwin's
`ETIME` differs. The original complete preceding SIGNAL bundle is rechecked
before its oracle plumbing is reused; no historical checker is weakened.

The macOS probe disables sanitizers only for malloc-zone measurement. Nine
warmed 1,000-cycle batches at 1/65/4096 handles retain zero blocks/bytes after
future-point polling and cleanup. This measures request storage; published
metadata and native slabs remain unqualified. Ordinary host and negative tests
retain ASan/UBSan with stack-use-after-return detection.

Native waits poll/yield instead of Linux fence callbacks and scheduler hints.
Deadline flags are accepted without leaf scheduling support. Jiffy timeout
rounding, real multi-CPU behavior and native performance are unqualified. Inline
and combined handle storage differs from Linux's two allocations, including
combined-invalid OOM/fault precedence. Transfer, legacy interoperability,
published reclamation, Mesa and broader driver/hardware parity remain open.
The generic timeline capability remains disabled. No hardware or guest boots
are part of these runners.
