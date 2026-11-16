# Submit queue lookup before staging

Native G13 submission now checks its queue after header validation and before
allocating command storage or copying command/sync data. An absent queue
returns `ENOENT` even when staging would otherwise fail with `ENOMEM`,
`EFAULT` or a descriptor error. Packaged
[Asahi submission](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs)
also resolves the queue before command/sync staging.

The probe holds the file namespace lock only while reading queue IDs and
returns a boolean. User copies run after unlocking; no queue, VM or resource
pointer escapes the probe. The existing locked backend lookup remains. Queue
removal during copying therefore returns `ENOENT` and releases staging storage
before backend preparation or publication. Header errors retain `EINVAL`.

Validation passed:

- ASan/UBSan with stack-use-after-return detection: 12,600 new checks cover
  zero/large/missing queue IDs against command OOM, copy faults, malformed
  descriptors/payloads and invalid/missing syncs. Missing queues cause zero
  allocation attempts and zero user reads. Nine malformed-header cases retain
  precedence. Known queues still report staging OOM/copy errors.
- A synchronous copy callback acquires the file lock, removes the logical
  queue, and verifies later revalidation. All staged storage is returned;
  result bytes, output fence identity and published work remain unchanged.
  The callback link clears before invocation and all borrowed fixture storage
  outlives its consumers. These are deterministic host interleavings.
- Existing async scenarios pass, with the repeated missing-queue/OOM case
  corrected to `ENOENT`. All 167,395 wait/syncobj cases, 9,400 lifecycle checks
  and close/mapping/priority/PRIME/wire/node/fence regressions pass.
- Exact prior GpuFile source with current fixtures fails the first new
  assertion: `ENOMEM` where `ENOENT` is required. Its raw Git bytes, precise
  single-source runner adapter, executable and rejection are retained.
- 27 V test files and selected reference/source gates pass. New guard tests
  reject a missing/late early probe, lost backend revalidation, missing probe
  unlock and changed reference errno. The expanded strict ARM C checker now
  covers 95 live helpers including the probe; negative selftests pass.
- Isolated ARM and clean x86 builds from
  `68c368ba8912a69b491db18711c9244534749031` plus one overlay,
  `kernel/gpu/agx/file/file.v`. ELF/C pairs and exact inputs were retained
  before switching architecture. x86 excludes AGX. Selected audited/support
  sources match the private worktree inputs.

Bounded generated ARM C review confirms direct `ENOENT` return before staging,
allocation-free boolean probe returns with unlocks, and the later lookup.
Existing submit allocation/free token counts match prior C. No native
allocation or lifetime was added. The unchanged global allocation allowance
audit **still fails** for baseline and feature, with identical per-file/kind
counts: 383 ARM/289 x86 sites and 827/813 sources. No allowance changed.

Local copies of prior Omarchy/package clones were refreshed against their
GitHub remote heads, still `4bf10ed28342b597009dcf573ffc0d70b94b31e3` and
`d727707b620c4e6c1c8de0f45c4a843475fa020e`. Pins remain Linux
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. Selected gates pass; the full
audit remains `not_equivalent` (exit 1).

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-submit-lookup-order-20261116/`.
Canonical `bundle/` and a fully restored archive pass the unchanged complete
typed inventory checker. Sources/references, kernels/C, executable tests,
negative baseline, raw logs and bounded C review are retained. `completion.txt`
binds eleven source paths and two reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `c6343f25796a201b249f17d1153d9f492452b62a7fb6ba596fb34d48aa279461` |
| `bundle.tar.gz` | `f485881b5de782402508077c2693d58c165528732d69cf9c4d783aefa7a7d9e5` |
| `bundle/vinix-aarch64` | `aae518e0bd4455f521a4feb861565ac6033b0a62fb890128d1a5a257991672b7` |
| `bundle/vinix-x86_64` | `2d1693df47ab3a2e8cc848b924e2ce9a920649b7747fed163691c3c208c429c3` |

This qualifies absent-queue precedence after native header validation. Linux
retains an owned queue across staging; Vinix revalidates and safely rejects
removal. Equivalent concurrent-destroy behavior remains open. The extra brief
lock and linear lookup were not benchmarked. Modern ABI/Mesa integration,
complete validation/error ordering, GEM-bind missing-VM semantics, cumulative
timelines, fence containers, reclamation and hardware qualification remain
open. No native heap or multi-CPU qualification, Vinix/QEMU boot, GPU execution,
hardware test, reboot, SSH or deployment occurred.
