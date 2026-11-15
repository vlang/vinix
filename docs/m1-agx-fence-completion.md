# First fence completion status

Offline increment, 2026-11-16. Full M1 parity remains **incomplete**; see
[the parity report](m1-agx-parity.md).

The packaged Linux DMA-fence implementation rejects repeated completion while
holding the fence lock. Vinix previously allowed a later error producer to
rewrite an already completed fence's result. Both native completion functions
now return under that lock when the fence is already signaled. The first error
is written before a release store publishes completion. Plain signaling keeps
an error prepared by the owner. Queued and late callbacks retain their existing
under-lock contract.

This adds no allocation, owning pointer, free or callback lifetime. Native fence
metadata retention is unchanged. It implements the selected first-completion
policy, rather than the full Linux timeline-chain or reservation-object model.

Validation passed:

- The complete production syncobj module, with injected locks, atomics,
  scheduling and time, passed ASan/UBSan checks for 800 success/error completion
  sequences and 4,000 main callbacks, including late waiters. Two additional
  deterministic exact-lock competing-producer cases, nil inputs and an
  owner-prepared error passed. Callbacks assert that the fence lock is held.
  Fixture-only metadata cleanup runs after all synchronous callers return.
- The production asynchronous ioctl/pending pipeline passed its sanitizer
  regressions. Completed success survives a late shutdown error; an original
  GPU fault survives late cancellation and plain signaling. Prior batching,
  backlog, initial snapshot, FIFO, dependency, admission and shutdown checks
  also passed.
- Three V unit suites (ten test files), the selected source/reference gates,
  and strict generated-C storage checks for 43 live ARM helpers passed.
  Negative checker selftests passed. The source audit checks and retains the
  packaged `drivers/dma-buf/dma-fence.c`; its overall result remains
  `not_equivalent` (expected exit 1).
- Isolated ARM and clean ordinary x86 kernels built from
  `c54d97723f894b8a3cbfc80336f4433fcda1cd7f` plus one retained
  `kernel/drm/syncobj/syncobj.v` overlay. All selected AGX, syncobj, GEM and ioctl
  V sources plus `drm.v` matched the audited checkout. The x86 kernel excludes
  AGX but includes the changed generic fence completion implementation.

Fresh checkouts matched remote Omarchy
`c054e662365235543cc28df2120bc9b6ceb2d197` and packages
`aa8376d2cff10995975b9fb76b6fadd9f35222e1`. They still select Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf` and Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`. The m1n1 reference is
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

Evidence is retained outside Git at
`/Users/alex/.local/state/vinix/omarchy-m1-fence-completion-20261115/`.
The canonical `bundle/` contains sources, references, test executables and logs,
both ELF kernels and generated C, provenance and the unchanged complete typed
inventory checker. Its sibling receipt and archive passed canonical and full
extracted inventory verification. `completion.txt` binds the feature commit's
12 non-report source paths and two reports to this evidence.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `f1c7e874badc50fc26227acc80bee6ef35a5ba6f89170068622d30e7ccebb6dc` |
| `bundle.tar.gz` | `f18e7363f418e67ba1d86479934398ab0066f7890e9a2413a05a2144ada44ff6` |
| `bundle/vinix-aarch64` | `add2bca574bd21a57643f307d78d47be5aab9d9a62203238094bc64cc98c7bc6` |
| `bundle/vinix-x86_64` | `7da136243e7d884a7a2424cd88b42145825eb88599725d451ea0ad488e71b187` |

No native GPU/firmware execution, Vinix boot, hardware test, reboot or deployment
was performed. These injected checks do not measure the kernel heap or exercise
actual multi-CPU kernel races. Modern ABI/Mesa integration, complete timeline
chains, reservation semantics, cache policy, accounting and other unverified
behavior still prevent a 100% equivalence claim.
