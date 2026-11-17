# DRM timeline SIGNAL

The 24-byte timeline-array request snapshots every object and point, reserves
every chain node, then publishes completed payloads while retaining cumulative
predecessors. Null points mean zeroes. Published metadata remains retained;
failure cleanup releases only unpublished reservations and request buffers.
Binary SIGNAL continues to create fresh private completions. Timeline SIGNAL
uses one permanent global stub initialized at DRM startup, with a getter fallback.

```sh
v run tests/drm-timeline-signal/run.v host /external/state/host-first
v run tests/drm-timeline-signal/run.v negative /external/state/negative
v run tests/drm-timeline-signal/run.v measure /external/state/measure
v run tests/drm-timeline-signal/native.v prepare /external/state
v run tests/drm-timeline-signal/native.v aarch64 /external/state
v run tests/drm-timeline-signal/native.v x86_64 /external/state
v run tests/drm-timeline-signal/native.v allocations /external/state
v run tests/drm-timeline-signal/native.v contracts /external/state
v run tests/drm-timeline-signal/run.v native /external/state
v run tests/drm-timeline-signal/evidence.v validate /external/state
v run tests/drm-timeline-signal/evidence.v seal /external/state
v run tests/drm-timeline-signal/evidence.v bind /external/state COMMIT
```

Use fresh external subdirectories and create their common parent first if
running modes concurrently. Native builds pin
`8f0622c7515265ef5762b8d8ced20d8ed510c0b8` plus four owned kernel overlays,
excluding concurrent event edits. Host binaries, C, logs and pinned primary
sources are retained. The 302 counted failure/copy/lookup cases cover every
allocation failure through 129 entries; successful arrays reach 4096 nodes.
Other cases cover first captures, overwritten names/records at the publication
lock, null/zero/duplicate/decreasing points and pending GPU predecessors.

The oracle compiles pinned Linux SIGNAL/QUERY and chain functions with explicit
single-thread allocation/refcount/RCU/usercopy/add-point plumbing. It compares
15,552 readiness/progress results, and requires the unchanged complete preceding
QUERY bundle. Three compiled negatives must fail designated assertions.

The macOS probe disables sanitizers only for malloc-zone measurement. Nine
warmed 1,000-cycle batches fail the final chain reservation at counts 1/65/129,
retaining zero blocks/bytes. This isolates unpublished storage and does not
measure published metadata or native slab retention. Ordinary host and negative
tests retain ASan/UBSan and stack-use-after-return checks.

Native handles use inline/combined storage rather than Linux's two allocations;
the permanent stub initializes at first DRM registration rather than Linux's
subsystem init. Those allocation/error-order and timestamp-phase differences,
published reclamation, actual multi-CPU behavior, wait/transfer, Mesa and hardware
parity remain incomplete or unqualified. The timeline capability stays disabled.
