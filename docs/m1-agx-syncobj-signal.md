# Binary syncobj SIGNAL

Offline increment, 2026-11-16. Full M1 equivalence remains **incomplete**; see
[the parity report](m1-agx-parity.md).

Vinix now implements `DRM_IOCTL_SYNCOBJ_SIGNAL`, using the 16-byte array
request and read/write encoding `0xc01064c5`. Nonzero padding and zero count
return `EINVAL`. Handles are copied once and all exact object identities are
resolved before effects. Copy, lookup and allocation failures return `EFAULT`,
`ENOENT` and `ENOMEM`.

The handler installs a fresh completed fence for each entry, including duplicate
handles. Each private completion has zero context, sequence, error and native
queue provenance, plus a monotonic timestamp sampled before its allocation.
Per-entry allocation failure stops processing and preserves the already
published prefix. SIGNAL replaces each binary head; it does not signal an old
GPU fence held by another waiter, submission or sync file. Binary replacement
also clears timeline lookup membership and publishes pending empty captures.
This follows the packaged
[Linux SIGNAL implementation](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_syncobj.c)
and [private completion allocator](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/dma-buf/dma-fence.c).

Ordinary successful/error fence completion now records its first monotonic
timestamp under the fence lock before publishing readiness. Later completion
attempts preserve both the first timestamp and the first status.

Temporary handle/object storage is inline through 64 entries and checked,
fallible owned storage above that. Every allocated request owner is freed on
copy/lookup failure, per-fence OOM and success. Published and superseded private
fences follow Vinix's existing metadata retention policy: **each successful
entry retains `sizeof(DmaFence)` bytes**, including duplicate entries.
Linux-style reference reclamation and memory accounting are still missing.
Fixture-only fence retirement after all consumers are gone must not be read
as native kernel reclamation. Signaled CREATE's existing allocation path is
unchanged; its fallibility remains separate work.

Validation passed:

- ASan/UBSan with stack-use-after-return detection: 3,413 SIGNAL cases over
  200 cycles plus 1..4096-handle requests; 16,000 existing wait/reset checks;
  4,103 geometry probes and 200 capture primitive cycles. Cases cover full
  validation before effects, inline/owned failure cleanup, OOM at each prefix,
  distinct duplicate timestamps, old GPU/timeline snapshots, first-publication
  captures across reset, user-handle mutation and exact-lock destroy/reuse.
  The allocator counts retained fence bytes separately from request owners.
- Asynchronous submission and DRM wire/node sanitizer regressions, three V
  unit suites (fifteen files), selected source/reference gates, strict generated-C
  checks for 56 live ARM helpers and negative selftests. The new allowed
  allocation site is exactly one fallible private-fence allocation.
- Isolated ARM and clean x86 builds from
  `c77c0d57e0cf4149919a74f764568195a8488d3d` plus four retained overlays:
  `kernel/drm/drm.v`, `kernel/drm/ioctl/ioctl.v`,
  `kernel/drm/syncobj/syncobj.v` and `kernel/drm/syncobj/stub.v`.
  Both include generic SIGNAL; x86 excludes AGX. Selected AGX/DRM,
  process/scheduler/exit and reviewed clock/lock sources match the build tree.
  Each architecture's ELF, generated C and inputs were retained before switching.
- Independent source and retained ARM C lifetime review found no defect.
  It checked initialization, empty arrays without allocation, pointer option
  transfer, cleanup, prefix failure and first timestamp publication. Timestamp
  sampling adds a fence-lock to clock-lock dependency; review found no reverse
  acquisition in the inspected clock sampling/mutation paths. Actual concurrent
  execution was not tested.

The unchanged global allocation allowance audit **still fails**, identically
on this feature and unchanged baseline: 385 ARM and 291 x86 V-reported sites,
with matching per-file/per-kind counts. One source file was added. This neither
qualifies retained fence memory nor certifies native leak freedom. Original
failures, comparison and unchanged allowances/auditor remain in the evidence.

Fresh Omarchy `29fbc4e2de4e57525acc6195351e86a31773e158` and packages
`bbb89d545a355ac111730879cecb46b907ef066f` matched checked remote heads.
Pins remain Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf` and Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`; m1n1 is
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. The source audit records a later
shared-checkout HEAD; selected hashes bind its inputs to the isolated baseline
and overlays. Its selected gates pass; verdict remains `not_equivalent` (exit 1).

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-syncobj-signal-20261116/`.
Canonical `bundle/` retains sources/references, binaries, logs, both kernels/C,
clock/lock sources, review and the complete typed inventory checker. Canonical
and fully restored archive inventories passed. Earlier 3,410-case runs remain
diagnostics. `completion.txt` binds sixteen non-report paths and two reports to
the feature commit and sealed inputs.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `25ef6c09fb4cf4664ab39fc1708ffc66af45ba1bc0c1377503b23f3bdb2a12cb` |
| `bundle.tar.gz` | `2844056dcb25fca33acf80e3826d4e39a238f59b0e04f686be7f933326408143` |
| `bundle/vinix-aarch64` | `4115faf89494b7404c297f3a96a26d9d15eed90d0fbc1e0abed1aad64f661c3c` |
| `bundle/vinix-x86_64` | `f8e4b1822ec9cb835338eea94ade7a66b06bae253213a0875654726c5b146601` |

Modern ABI/Mesa integration, full Linux timeline/reservation semantics,
remaining generic operations, namespace capacity, sleeping callbacks, cache
policy and accounting remain open. No native GPU/firmware execution, Vinix
boot, native heap measurement, hardware test, reboot or deployment occurred.
