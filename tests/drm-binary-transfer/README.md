# Binary-destination syncobj transfers

The 32-byte `DRM_IOCTL_SYNCOBJ_TRANSFER` request supports destination point zero.
It retains the destination identity, resolves the source point and replaces the
destination fence without waiting for GPU completion. Source point zero captures
the current head; retired positive prefixes use the permanent completed stub.
FOR_SUBMIT waits up to five seconds for publication and detaches its explicit
stack capture on every return. Positive destination points return EOPNOTSUPP;
timeline merge/array fences and the generic timeline capability remain pending.

```sh
v run tests/drm-binary-transfer/run.v host /external/state/host-stack
v run tests/drm-binary-transfer/run.v negative /external/state/negative-stack
v run tests/drm-binary-transfer/run.v measure /external/state/measure-stack
v run tests/drm-binary-transfer/native.v prepare /external/state
v run tests/drm-binary-transfer/native.v aarch64 /external/state
v run tests/drm-binary-transfer/native.v x86_64 /external/state
v run tests/drm-binary-transfer/native.v allocations /external/state
v run tests/drm-binary-transfer/native.v contracts /external/state
v run tests/drm-binary-transfer/run.v native /external/state
v run tests/drm-binary-transfer/evidence.v validate /external/state
v run tests/drm-binary-transfer/evidence.v seal /external/state
v run tests/drm-binary-transfer/evidence.v bind /external/state COMMIT
```

Create the common external parent first. Host/negative/measure subdirectories
must be fresh. Native builds pin `1625440897e2116677c4b09adb7f51761d498e0b`
plus four kernel overlays, excluding concurrent event edits. Host tests include
1,221 counted transfer checks and the full sanitized DRM suite, using kernel GC
mode and stack-use-after-return detection. They cover lookup/pad/flag precedence,
pending fences, chains, source/destination name reuse, self-transfer, future-point
publication, timeout/signal ordering and cancellation before later publication.
The fixture clock can advance five seconds without millions of polling steps.

The compiled oracle reuses infrastructure only after rechecking the unchanged
complete preceding WAIT bundle. It compiles unchanged pinned dispatch, binary
transfer, find-fence, add-wait and chain functions, comparing 10,752 outcomes.
Refcount/RCU/usercopy/publication and one-step timeout scheduling are host stubs;
actual future publication/interruption races are separate fixture checks. The
oracle never selects timeline destinations. Three compiled negatives must fail
designated borrow-cleanup, exact-payload and source-point assertions.

The macOS probe disables sanitizers only for heap measurement. Nine warmed
1,000-cycle success/timeout/interruption batches retain zero blocks/bytes.
An initial local capture and a fixed-array variant both generated hidden heap
copies with this compiler; explicit `__builtin_alloca` removes that allocation.
Generated-C guards require explicit initialized stack storage, no heap boxing
and detachment on prepared returns. Ordinary host/negative tests keep sanitizers.

Polling/yielding differs from Linux callback scheduling and jiffy rounding.
Real multi-CPU behavior, native slab retention/performance, legacy timeline-map
interoperability and published metadata reclamation remain unqualified. Timeline
destination merge/container semantics, Mesa, firmware/cache and hardware parity
remain incomplete. No guest boots, GPU access or reboots are part of these tests.
