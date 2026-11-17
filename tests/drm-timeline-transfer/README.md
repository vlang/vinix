# Timeline destination transfers and flat fence arrays

Positive `DRM_IOCTL_SYNCOBJ_TRANSFER` destinations now unwrap source containers,
drop completed leaves, sort/deduplicate pending contexts, and install a cumulative
destination chain. Zero pending leaves produce a private completed stub with the
latest observed timestamp; one leaf is borrowed; multiple contexts own a flat
array. Merge/table/chain failures unwind before destination publication. Published
fence metadata retains the existing native lifetime.

```sh
v run tests/drm-timeline-transfer/run.v host /external/state/host-qualified
v run tests/drm-timeline-transfer/run.v negative /external/state/negative-qualified
v run tests/drm-timeline-transfer/run.v measure /external/state/measure-qualified
v run tests/drm-timeline-transfer/native.v prepare /external/state
v run tests/drm-timeline-transfer/native.v aarch64 /external/state
v run tests/drm-timeline-transfer/native.v x86_64 /external/state
v run tests/drm-timeline-transfer/native.v allocations /external/state
v run tests/drm-timeline-transfer/native.v contracts /external/state
v run tests/drm-timeline-transfer/run.v native /external/state
v run tests/drm-timeline-transfer/reference.v PINNED_LINUX /external/state/host-qualified/drm-wait /external/state/reference-final
v run tests/drm-timeline-transfer/evidence.v validate /external/state
v run tests/drm-timeline-transfer/evidence.v seal /external/state
v run tests/drm-timeline-transfer/evidence.v bind /external/state COMMIT
```

Create the common parent first and use fresh host/negative/measure/reference
subdirectories. Native builds pin `480367cfb7415fa0e9d0001f25055c21b912843c`
plus eleven kernel overlays, excluding concurrent event changes. Qualification
keeps the host regressions and final reference comparison separately; earlier
failed oracle wrappers remain retained, including a null-contained assumption
and mismatched predecessor identity. Upstream function bodies stay unchanged.

The full sanitized DRM suite includes 51 counted transfer cases plus standalone
array protocols: private cleanup at every allocation, latest-context ordering,
timestamps, one/zero pending fast paths after inter-pass retirement, and
sync-file flattening. Arrays with 129/4096 members exercise sorting, callback
activation and one final wake. Two queues with the same owner must retain both
dependencies in either completion order. Lazy and enabled arrays check their
different error semantics; native chains activate callbacks eagerly.

The oracle compares 8,640 outcomes using pinned transfer/find/chain, array
allocation/init/lazy readiness, unwrap, sort/dedup and merge bodies. It covers
unsigned sequence/context boundaries, completed subsets, retired source points,
binary/timeline destinations and pending destination prefixes. Allocation,
refcount/RCU/time/callback plumbing is stubbed. Linux signed-comparison warnings
are disabled for unchanged upstream merge loops. The complete preceding binary
transfer bundle is rechecked before its infrastructure is reused.

Three compiled negatives must fail designated private-table cleanup, latest
sequence and first-error assertions. Nine warmed 1,000-cycle macOS malloc-zone
batches fail each merge/array/chain allocation and retain zero blocks/bytes.
Sanitizers are disabled only for that measurement. It measures unpublished
request storage; successful publication retains metadata and is not leak-flat.

Generated-C guards reject hidden allocations in merge/array/iterator/atomic
paths and require explicit table owners, i64 error loads/CAS, private-only
reservation handoff, and completion draining after publication unlock. G13 queue
fences use their unique queue identity as their public context, preventing
cross-queue deduplication. Source contracts include negative controls for these
review corrections. The generic timeline capability remains disabled pending
interoperability and native qualification. No GPU or guest boots occur here.
