# First-submission capture and wait interruption

Offline increment, 2026-11-16. Full M1 parity remains **incomplete**; see
[the parity report](m1-agx-parity.md).

This closes the empty-object polling window documented in the preceding
[binary wait snapshot report](m1-agx-binary-wait.md). An empty binary wait now
registers a borrowed capture node under the same syncobj lock as replacement.
The first non-null fence published after registration is captured and the
node detached before that lock is released. Immediate clearing or replacement
before the waiting task runs again cannot redirect the wait. Registration also
takes the initial snapshot under that lock; existing fences stay stable.

Every post-registration exit detaches all borrowed nodes before the synchronous
ioctl's stack storage disappears. Pending binary waits now return the kernel's
internal restart error for unmasked private/shared signals or thread exit.
Masked signals do not abort a wait. Readiness and absolute timeout checks keep
their precedence over interruption, matching the packaged Linux wait loop.

This adds a borrowed stack-node lifetime, with no new owning allocation/free or
fence callback. Native syncobj/fence metadata retention remains unchanged.
The object lock serializes publication, capture reads and removal. Nil fence
replacement leaves empty registrations pending; a captured node is detached
and never updated by later replacement.

An independent lifetime review covered the source, scheduler/exit handling and
isolated ARM generated C. It found no lifetime or lock-order defect. The emitted
wait uses fixed `handles[64]`, `objects[64]` and `captures[64]` stack arrays,
passes nodes directly by address and releases all entries before every
post-registration return. Reviewed production hashes and scope are retained in
the bundle's `review.txt`. Actual kernel concurrency and signal delivery were
outside that review.

Validation passed:

- ASan/UBSan production create/wait/syncobj/request code and the real pending
  signal reader passed 5,800 recorded ioctl checks across 200 cycles, plus
  direct pointer/count/copy/namespace checks. The final run explicitly enabled
  ASan stack-use-after-return detection. Scripted cases cover first publication
  followed by immediate clearing/completed replacement, duplicate handles,
  signals, masks, thread exit and readiness/timeout/interruption precedence.
  Checks assert detachment on return and exercise later publication.
- Another 200 capture primitive cycles cover multiple registrations,
  middle/head/tail removal, nil publication, duplicate registration rejection,
  idempotent cleanup and exact-lock publication/cancellation interleavings.
  Fixture-only frees follow all synchronous callers and scripted actions.
- Production asynchronous submission and DRM node/request-copy sanitizer
  regressions passed. Three V unit suites (twelve test files), selected source
  contracts and strict generated-C storage checks for 48 live ARM helpers
  passed, including negative checker selftests. The overall source audit still
  reports `not_equivalent` (expected exit 1).
- Isolated ARM and clean x86 cross-builds passed from
  `f6c2c0e6f3b09d089f3ebdc172d1597ed0caae58` plus three overlays:
  `kernel/drm/drm.v`, `kernel/drm/syncobj/syncobj.v` and
  `kernel/drm/syncobj/capture.v`. Selected AGX, syncobj, GEM, ioctl and reviewed
  process/scheduler/exit sources matched the checkout. Both generated C outputs
  contain the changed generic wait/capture implementation; x86 excludes AGX.

Fresh checkouts matched checked remote heads Omarchy
`9f68da882545cf4aae8a6c15cce06fada0f116dd` and packages
`9c8d516a58d1a36585a2dbb2f6244d851506b767`. They still select Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf` and Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`; m1n1 remains
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

Evidence is retained outside Git at
`/Users/alex/.local/state/vinix/omarchy-m1-wait-capture-20261116/`.
The canonical `bundle/` contains source/reference snapshots, logs, native
sanitizer executables, both ELF kernels and generated C, independent review,
provenance and the unchanged complete typed inventory checker. Canonical and
full extracted archive inventories passed. `completion.txt` binds the feature
commit's 14 non-report source paths and two reports to that evidence.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `33d27fa60d516b2d6bb9d8ab66b3bbd9d367c16161ce2fc8550cbd07f7191dd9` |
| `bundle.tar.gz` | `bb87627bc226802389660d0b93971dedcb8325b4f20b307cdbc7747ff7a58ddd` |
| `bundle/vinix-aarch64` | `ba38420b32bd6ab110de0d2ab8eec15071ccf20a790eb61e4818fe600e4d9ec7` |
| `bundle/vinix-x86_64` | `97f735ce2006983b80379332ae834585692d7c50b5e77d94223042797ad3ea4a` |

The 64-handle cap, scheduler polling instead of sleeping fence callbacks,
deadline scheduling hints, full timeline/reservation semantics and modern
ABI/Mesa integration remain open, alongside cache policy and accounting.
No actual multi-CPU kernel race, kernel heap measurement, userspace signal
delivery/restart, GPU/firmware execution, Vinix boot, hardware test, reboot or
deployment was performed.
