# Fallible syncobj creation before handle publication

Offline increment, 2026-11-16. Full M1 equivalence remains **incomplete**;
see [the parity report](m1-agx-parity.md).

CREATE previously published its object before installing the optional signaled
fence and used an infallible object allocation. It now allocates the object
fallibly, initializes its optional timestamped private completion, then chooses
and publishes a handle under the namespace lock. A guessed handle cannot
expose a partially initialized signaled object. The legacy empty constructor
uses the same path with no initial fence.

Allocation failure and native namespace exhaustion return `ENOMEM` without
changing the caller's output handle. Invalid flags fail before allocation.
Guarded cleanup frees only the private object and its exclusively owned stub;
namespace exhaustion unlocks before cleanup. Successful publication transfers
both allocations into the existing retention policy. There is no numeric-handle
rollback that could erase a concurrently reused object.

This follows the creation-before-handle sequence in the packaged
[Linux DRM syncobj implementation](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_syncobj.c).
Published object/fence reclamation and Vinix's existing global 1,024-slot and
per-file 1,023-handle limits remain separate parity gaps.

Validation passed:

- ASan/UBSan with stack-use-after-return detection: 3,004 CREATE cases over
  200 failure/publication cycles, actual global-table exhaustion and actual
  per-file handle exhaustion with a global slot still free. Cases cover both
  allocation failures, nested creation during failure and before publication,
  initial completed-fence visibility, distinct initial fence identities,
  unchanged error outputs, flags, owner isolation and the empty legacy API.
- All 19,413 previous wait/reset/SIGNAL cases, 4,103 geometry probes and
  200 capture primitive cycles. Object metadata, fence metadata and temporary
  storage are tracked separately. Metadata-free hooks reject freeing anything
  reachable from a published handle/head and require the namespace lock to be
  released. Fixture-only retirement after all consumers finish is not native
  kernel reclamation or a kernel heap measurement.
- Asynchronous submission and DRM wire/node sanitizer regressions, three V
  suites (sixteen test files), selected reference/source contracts and strict
  generated-C checks for 58 live ARM helpers with negative selftests. The
  legacy wrapper is absent from native generated C after dead-code removal;
  source guards and host execution cover it. An initial 59-helper check's
  missing-body rejection is retained as a diagnostic.
- Isolated ARM and clean x86 builds from
  `d6f2d54697c03984021c8fd61bc1113e783bba33` plus two retained overlays:
  `kernel/drm/drm.v` and `kernel/drm/syncobj/syncobj.v`. Both include generic
  CREATE; x86 excludes AGX. Each ELF, generated C and input set was retained
  before changing architecture. Selected AGX/DRM and reviewed process,
  scheduler, clock/lock, FS and file sources match the private build.
- Independent source and retained ARM C lifetime review found no defect.
  It checked every ownership exit, empty arrays without allocation, option
  transfer and publication. The existing ioctl FD/Handle reference protects
  the namespace owner until the handler returns; final DRM close removes the
  namespace afterward. Supporting FS/file source identities are retained.

The unchanged global allocation allowance audit **still fails**. Its reported
sites change from 385 to 384 on ARM and 291 to 290 on x86: precisely one
infallible `SyncObj` struct allocation is replaced by explicit fallible
preparation. All other per-file/per-kind counts and source counts match the
unchanged baseline. This does not establish native leak freedom. Original
failures, comparison and unchanged allowances/auditor are retained.

The async fixture records retained syncobj metadata separately from job fault
positions and live-node counts; its existing job assertions still pass.
CREATE allocation failures and cleanup use the actual constructor in the DRM
fixture. Published metadata retention remains unchanged in production.

Fresh Omarchy `29fbc4e2de4e57525acc6195351e86a31773e158` and packages
`bbb89d545a355ac111730879cecb46b907ef066f` match checked remote heads.
Pins remain Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf` and Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`; m1n1 is
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. Selected source-audit gates pass;
the verdict remains `not_equivalent` (exit 1).

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-syncobj-create-20261116/`.
Canonical `bundle/` retains sources/references, binaries/logs, both kernels/C,
review and the complete typed inventory checker. Canonical and full restored
inventories passed. Earlier checks remain diagnostics. An initial unsealed
bundle omitted two supporting source copies; its rejection and partial copy
remain in `failed-source-copy/`, and the final bundle includes both pinned
files. `completion.txt` binds seventeen non-report paths and two reports to the
feature commit and sealed inputs.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `c24ba1d7f41453465ecf4c138600559534f7d4cd1224c34cb0296345eb6baa33` |
| `bundle.tar.gz` | `fae0b9cc27d549ea4e80ec4e4315bf87c8c3a09479de5e53d0fa7499ddecd339` |
| `bundle/vinix-aarch64` | `d4cb6e6662d8778e48fe25fa878f493f69ade942af34b3542cfb3ea2248687e9` |
| `bundle/vinix-x86_64` | `d945d889503ec7d6f5b8ddb5f89c452871183b118d6a0ef928303ad9e547a480` |

Full timeline/reservation semantics, modern ABI/Mesa integration, other generic
operations, namespace capacity, reclamation, callback waits, cache policy and
accounting remain open. No GPU/firmware execution, native concurrency or heap
measurement, Vinix boot, hardware test, reboot or deployment occurred.
