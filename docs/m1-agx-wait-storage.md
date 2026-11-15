# Binary waits beyond 64 handles

Offline increment, 2026-11-16. Full M1 parity remains **incomplete**; see
[the parity report](m1-agx-parity.md).

The packaged Linux DRM core allocates wait storage for the requested count.
Vinix previously rejected every binary wait above 64 handles. The handler now
keeps inline stack storage for up to 64 handles and uses one fallible packed
allocation for larger requests. Checked 64-bit arithmetic sizes and aligns the
handle, object and capture regions. Allocation failure returns `ENOMEM`.

Snapshots, first-publication capture and signal/timeout behavior remain intact.
Every allocated exit frees its owner; post-registration exits first detach all
borrowed captures under the object locks. Reverse detachment avoids repeated
tail scans for duplicate-handle registrations. Cleanup never frees inline
storage. Native syncobj/fence metadata retention is unchanged.

An independent source and generated-ARM-C review found no ownership, bounds or
alignment defect. It confirmed the by-value owner transfer, absence of hidden
boxing, and capture detachment before owner free on every post-registration
return. The reviewer also checked the final retained ARM C and its identities;
the bundle's `review.txt` records hashes and scope.

Validation passed:

- ASan/UBSan with stack-use-after-return detection: 5,800 existing wait checks,
  5,600 large-wait checks over 200 cycles, 4,103 geometry probes and 200 capture
  primitive cycles. Cases include the 1/64 inline boundary, 65..4096 handles,
  ready index 4095, duplicate captures, immediate replacement, allocation/copy/
  lookup/prepare failures, timeout, interruption and idempotent owner cleanup.
- The injected allocator starts memory with nonzero bytes and checks every
  retiring allocation against actual object capture lists. Requests return
  all owned buffers/bytes before later publication. Huge requests use a
  fixture-only allocation ceiling. These are owner-lifetime measurements, not
  measurements of the native kernel heap.
- Asynchronous submission and DRM node/request-copy sanitizer regressions,
  three V unit suites (thirteen test files), selected source contracts and
  strict generated-C checks for 51 live ARM helpers passed. The checker permits
  only the existing owned backlog allocation and the new checked wait-owner
  allocation; its negative selftests passed.
- Isolated ARM and clean x86 builds passed from
  `41f5eaaf53e27eb7fd1b16f04c90be4251e0ffb6` plus two overlays:
  `kernel/drm/drm.v` and `kernel/drm/wait_storage.v`. Both contain the generic
  wait implementation; x86 excludes AGX. Selected sources match the audited
  checkout and retained architecture inputs.

The unchanged global kernel allocation allowance audit **still fails**, on
both this change and the unchanged baseline. Complete reports have identical
per-file/per-kind counts: 385 ARM and 291 x86 V-reported allocation sites. The
new helper adds one source file and no new reported site. Both original
failures, the unchanged auditor/allowances and the separate comparison remain
retained. This comparison does not turn the allowance audit into a pass or
certify leak-free native execution.

Fresh Omarchy `9f68da882545cf4aae8a6c15cce06fada0f116dd` and packages
`9725b0b09b245cc405abfe5730cfec2adac98be6` matched checked remote heads. They
still select Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf` and Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`; m1n1 remains
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. The final M1 source audit passes
its selected gates but remains `not_equivalent` (expected exit 1).

Evidence is retained outside Git at
`/Users/alex/.local/state/vinix/omarchy-m1-wait-storage-20261116/`.
The canonical `bundle/` includes sources, references, test binaries/logs,
both ELF kernels and generated C, independent review, original allocation
reports and the unchanged complete typed inventory checker. Canonical and full
extracted archive inventories passed. Failed attempts remain diagnostic; ARM
was rebuilt and retained after an initial retention omission. The unsealed
failed source copy is preserved separately as `failed-source-copy/`.
`completion.txt` binds fourteen non-report source paths and two reports to the
feature commit and retained evidence.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `e804e721ec81a753af5e2292f0294cc7bcf42041ab1ee50a7f7e4130a95bdca8` |
| `bundle.tar.gz` | `f537c3748feb21550c2d9a60d385c5a1beeab5239b5607c89be5177afdf3535c` |
| `bundle/vinix-aarch64` | `3c4b6e0938b65fa51692e3b53ecfe1398c90b5b861e04dc8ab59e64d2081e47e` |
| `bundle/vinix-x86_64` | `aa1496baea9118f8cd7ee06d48a8f39d319005c9b54653ad4c460b951e450d74` |

Scheduler polling versus sleeping fence callbacks, deadline hints, full
timeline/reservation semantics, global syncobj table limits, modern ABI/Mesa,
cache policy and accounting remain open. No native heap measurement, actual
multi-CPU race, userspace signal delivery/restart, GPU/firmware execution,
Vinix boot, hardware test, reboot or deployment was performed.
