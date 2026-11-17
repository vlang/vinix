# Shared firmware heap release policy

G13 shared and shared-read-only heaps now retire released allocation records
before `release()` returns. Private and GPU-read-only heaps retain deferred
collection. Existing callers of `new_heap()` keep that deferred default;
`new_heap_with_garbage()` selects a private flag during construction. Only the
two corresponding G13 manager classes select immediate release.

This matches the class policy in the packaged Asahi driver at Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`: its manager enables garbage pools for
private and GPU-read-only allocators, disables them for shared/shared-read-only
allocators, and its allocation drop retains nodes only when a pool exists.
The source contract checks both local policy and those pinned upstream paths.

Immediate release invokes the existing one-record collector under the heap
lock. Construction fixes the policy, so an immediate heap has no pending
garbage on entry; the newly released record is its only pending owner. Release
returns directly after collection without reading its invalidated table alias.
No new container or allocation is introduced. Independent lifetime review found
no source lifetime or locking blockers. Existing unmap, TLB completion, firmware
invalidation and rollback gates remain intact.

Offline validation passed:

- The previous shared-heap constructor reproduces retained metadata after
  release. Seven compiled negatives reject ignored/lost/reversed policy,
  zero collection, unconditional immediate release and a changed default at
  designated runtime assertions. Compile errors do not count as rejection.
- ASan/UBSan checks 4,320 policy/offset/release-permutation cases and 20,480
  mixed policy/reuse/partial-collection steps against an independent interval,
  pending-address FIFO and chronological-hole model. Counts, rounded bytes,
  ranks, duplicate/unknown releases, immediate lower-hole reuse, deferred
  ownership, live metadata addresses and actual metadata poisoning agree.
- Three 10,000-operation immediate-release samples retain zero records,
  malloc blocks and bytes without explicit GC. Existing ordinary, padding and
  capacity measurements remain flat. Interior GC still reclaims 8,192 blocks
  / 393,216 host malloc bytes below a live pin. Kernel slab rates are unmeasured.
- The full heap suite, 19,440 FIFO cases, 10,240 partial-collection/reuse steps,
  existing compiled ownership/bounds/padding/capacity/collection/reuse/history/
  FIFO negatives, 64 focused test files and broader offline regressions pass.
  Four hundred production heap/page-table cycles cover immediate/deferred
  policy and global/per-ASID mappings under `-gc none -manualfree`, ASan/UBSan
  and fake-stack detection. They verify invalidation before address reuse,
  preservation of live mappings and destruction of old metadata. Privileged
  instructions are replaced; firmware cache operations do not execute.
- Fresh isolated ARM/x86 builds pass. Generated C preserves nine heap bodies,
  eleven owning layouts apart from one scalar flag, fourteen GPU lifetime
  bodies and ten event methods. Constructor, release and manager differences
  reduce exactly to the deferred default, stack-only policy wrapper, locked
  one-record branch and two class selections. Ten host and four native C
  mutations are rejected. x86 ownership comparison also passes.

Allocation reports match the predecessor exactly: 379 ARM / 289 x86 sites
across 833 / 813 source files. Existing allowance-check failures remain
unchanged; no allowance was edited.

Compared repository heads are Omarchy
`3b36b9e19ea00a6c21492098308a7f44a8091564` and packages
`6aa71681da0fa53944f230e2d6b807bf852f2b0b`. The selected package definitions
are unchanged: Linux `bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

Whole-driver audit: **not_equivalent**. Matching these class policies does not
establish full allocator equivalence. Manager GC pacing, backing objects,
accounting and native performance remain open, as do modern UAPI/Mesa
integration, timestamp publication/units, remaining stage backing/event
destruction, manager/UAT replacement, firmware/cache teardown, reservation
fences, timelines, wire/default coverage, topology and power/reset. The earlier
Boehm/ASan fake-stack diagnostic remains unqualified; acceptance here uses the
production manual memory model.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-release-policy-20261117/`.
Native baseline is `53d4927abc706f68a91fc6fbbdb52769362a6203` with two retained
production overlays. Fifteen feature source paths are bound to the complete
bundle; dependent fixtures and native kernels are fresh. Independent unchanged
runners are reused after checksum verification. The historical inventory checker
verifies the predecessor, current bundle and full archive restoration without
changing its contract. `completion.txt` binds committed sources and reports to
the evidence. Generated results remain outside Git.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `43f382bcff6ccab58a109f183672fc39fed63fc4e845b1cd1f646bd094455718` |
| `bundle.tar.gz` | `b2a450badb84316f7ab9f9d3c8b6cab30e8318161a10af1b92fca1b5b067c13c` |
| `bundle/vinix-aarch64` | `97a244e649e75bd7be4c39c98d10a54bdcae537a1ec0a57142e370f6a822fdd0` |
| `bundle/vinix-x86_64` | `77bfde0a6291579c3d54d644705b087009f29603c6af0f35c51413fef4a82525` |
| `bundle/blob-aarch64.c` | `a735e0879bd9767756466192cd6d5bc10a6cf9e5b3443e5f7fa50b60833eb6b4` |

No GPU workload, firmware interaction, Vinix/QEMU boot, reboot, SSH or deployment occurred.
