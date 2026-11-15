# Syncobj namespaces beyond the fixed table

Offline increment, 2026-11-16. Full M1 equivalence remains **incomplete**;
see [the parity report](m1-agx-parity.md).

Vinix no longer rejects creation after 1,024 objects globally or 1,023 handles
in one DRM file. It allocates the lowest free nonzero 32-bit handle in each
file namespace, with a checked successor that cannot wrap to zero. Lookup,
individual destruction and file close operate without the former fixed table.
The selected handle policy follows `XA_FLAGS_ALLOC1` and `xa_limit_32b` in the
packaged [Linux syncobj implementation](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_syncobj.c).

The native index uses one link in each retained object, sorted by unsigned
owner/handle keys under the existing global namespace lock. Creation prepares
private object/fence storage before choosing and publishing its handle.
Destruction unlinks objects and clears their links, preserving already captured
object/fence identities through reuse and file close. Namespace operations add
no separate allocation. Published keys are immutable; any future key change
must unlink and reinsert under the namespace lock.

This index still traverses linearly under one global lock, unlike Linux's
per-file xarray. Indexing performance and locking equivalence are not established.
Published metadata reclamation remains missing. The additional pointer can
affect native slab sizing; native heap cost was not measured.

Validation passed:

- ASan/UBSan with stack-use-after-return detection: 13,238 namespace cases,
  including 4,096 objects across four files and 4,096 in one file, high-handle
  reuse with old identities, capture survival across owner close, explicit
  first/middle/last reuse, neighboring owner blocks, unsigned 64-bit owner
  boundaries and 5,000 operations against an independent bitmap model.
  Successor probes cover `UINT32_MAX`; a complete 32-bit namespace was not
  materialized.
- All 22,413 remaining prior wait/reset/SIGNAL/CREATE checks, 4,103 geometry
  probes and 200 capture primitive cycles. Four obsolete fixed-cap CREATE
  rejection cases were replaced by positive namespace-capacity cases; their
  original evidence remains in the immutable CREATE bundle. Fixture cleanup
  retires every allocation after consumers finish; native retention is unchanged.
- Async submission and DRM wire/node sanitizer regressions, three V suites
  (seventeen test files), selected reference/source gates, strict generated-C
  checks for 62 live ARM helpers and negative selftests. Object/fence ownership
  in host fixtures is tagged at checked exact allocation call sites because
  their sizes can coincide. Native source and generated kernel C use the real
  allocator without fixture instrumentation or production padding.
- Isolated ARM and clean x86 builds from
  `c43e6b0cb755b7abe0ab4b1eb08849895bc829a2` plus one retained overlay:
  `kernel/drm/syncobj/syncobj.v`. Both contain generic namespaces; x86 excludes
  AGX. Selected sources match the private build. Each ELF, generated C and
  overlay was retained before switching architecture. The source audit records
  a later shared HEAD; selected source hashes bind its input to these builds.
- Independent source and retained ARM C lifetime review found no defect in
  insertion, lookup, unlinking or owner cleanup. It confirmed unsigned ordering,
  non-wrapping handle exhaustion, unlocked private failure cleanup, ownership
  transfer, absence of boxing and preservation of published snapshots.

The unchanged global allocation allowance audit **still fails**, with identical
baseline/feature source counts and per-file/per-kind counts: 384 ARM and 290 x86
V-reported sites. Original failures and comparison are retained. No allowances
or auditor were relaxed; this is not a native heap or leak qualification.

Fresh Omarchy `29fbc4e2de4e57525acc6195351e86a31773e158` and packages
`ea02147686053d0ae6aef9800760fdda4c4e1489` match checked remote heads.
Pins remain Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf` and Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`; m1n1 is
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. Selected audit gates pass;
verdict remains `not_equivalent` (exit 1).

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-syncobj-namespace-20261116/`.
Canonical `bundle/` retains sources/references, binaries/logs, both kernels/C,
review and the complete typed inventory checker. Canonical and fully restored
archive inventories passed. The initial fixture compile rejection and earlier
13,198-case run remain diagnostics. `completion.txt` binds sixteen non-report
paths and two reports to the feature commit and sealed inputs.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `f9b4668c85de504891f8a49817f065ff08c096ea3feb372867765b899fdb1613` |
| `bundle.tar.gz` | `e2cb7a3bb68fd6d3c5bb86122c6cc6558937a4d583db1560dbef43c14b4797e3` |
| `bundle/vinix-aarch64` | `bbd599517d1f002961e605fcbfc7d6370543eaf80cce5dd25d6722246e80001d` |
| `bundle/vinix-x86_64` | `b946760d7fd6a12d4b6b1da530750226c8e05214d7380c278b167b6fe89cf3b8` |

Timeline/reservation semantics, modern ABI/Mesa integration, other generic
operations, index/locking performance, reclamation, callback waits, cache policy
and accounting remain open. No native concurrency/heap measurement, Vinix boot,
GPU/firmware execution, hardware test, reboot or deployment occurred.
