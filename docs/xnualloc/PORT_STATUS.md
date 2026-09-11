# XNU allocator translation and Vinix zone backend

Updated 2026-09-11. Experimental continuation in draft PR #179. **This is an
adapted, partial translation, not a completed transplant of every XNU allocator
path or configuration. No V compilation, kernel boot, SMP stress or speedup is
claimed.**

## Provenance

Vinix base: `1dc68880818947654a69de85193d8800be0e4749` (PR #178), based on
`7c085707f535e498ff2ce9a6447d8a5b59844388`. The new branch is
`allocator/xnu-zone-port-2026-09-11`; master and PR #178 are unchanged.

XNU source: `apple-oss-distributions/xnu` at
`f6217f891ac0bb64f3d375211650a4c1ff8ca1ea` (`xnu-12377.1.9`), principally
`osfmk/kern/zalloc.c`, blob `0d79c2dd58f8eed4e8f80834fa1e3b9b43675eff`.
Source: https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/kern/zalloc.c

Apple and Carnegie Mellon notices are retained. The translated files retain
APSL 2.0, not GPL. The exact upstream APPLE_LICENSE (blob
`fe81a60cae982c042a69f97623b427666c455093`) accompanies source, tests and these
documents. See NOTICES. This draft does not establish compatibility of a combined
distribution or provide a license exception.

## Translation coverage

| XNU logic | Supplied V code | Status / adaptation |
|---|---|---|
| Packed zone page metadata; inline/reference bitmaps; rotating scans; initialization/merge/free; packed bitmap references | `xnualloc/bitmap.v` | Translated primitives. Explicit storage/length arguments and an exhaustion sentinel. |
| Relative-index bitmap buddy free lists, split state, splitting/coalescing, two banks, extra tracking storage | `xnualloc/buddy.v` | Translated library for 4 KiB/16 KiB prebacked arenas. NOT the PMM and NOT live kernel bitmap backing. |
| Full-prefix/empty-suffix depot lists, FIFO/LIFO moves, magazine swap/replacement, explicit SMR polling | `xnualloc/magazine.v` | Translated primitives used by the new ordinary-zone path. Fixed 32-element magazines. |
| `zone_meta_queue_push`, remove/requeue, ordinary fully backed `zcram` | `xnualloc/zone.v` | Adapted to pointer-linked full/partial/empty chunk queues; no packed VA queue indices or partial VM population. |
| `zalloc_import`, ordinary allocation dispatch and bitmap reservation | `Zone.zalloc_import`, `Zone.zalloc_ext` | Batch reservation and queue/counter transitions; caller supplies backing. Unavailable batches do not mutate state. |
| `zfree_drop`, allocation/free validation and accounting | `Zone.zfree_drop`, `zone_mark_valid/invalid`, `zfree_ext` | Adds a distinct client-live bitmap. Cached objects remain bitmap-reserved until drained. |
| Non-SMR cache prime, import, overflow, depot recirculation | `zalloc_cached_*`, `zfree_cached_*` | Adapted control flow with six fixed magazine containers per initialized CPU cache. No recursive magazine allocation. |
| Element/cache draining and ordinary empty-chunk reclamation | `zone_reclaim_elements`, `zone_drain_cache`, `zone_drain_recirc`, `zone_reclaim_chunk` | Detach/account under one external lock; release backing outside the lock. No VA sequestering. |
| Vinix small heap entry points and early/SMP registration | `memory/xnu_zone_heap*.v`, routing in `physical.v`/`slab.v`, both SMP initializers | Source-connected behind `-d xnu_zone`, but not compiled/boot-validated. |

These are not byte-for-byte representations of XNU's full state. In particular,
**recirculation objects stay reserved in this port** until an explicit drain;
XNU's more elaborate bitmap/cache accounting is not reproduced wholesale.
The non-SMR core exposes no success stubs for unsupported VM, grace periods,
read-only mappings or security facilities.

## Kernel behavior and synchronization contract

`-d xnu_bitmap` selects only the earlier translated bitmap routines in the
independent slab backend. `-d xnu_zone` instead routes small `malloc`, `free`,
`realloc` and `heap_trim` through the new zone/cache state machine. Fourteen
16-byte-aligned classes from 16 through 2048 bytes and one 4 KiB backing page per
chunk are retained. Larger requests use Vinix's existing contiguous PMM-backed
large allocation and page-aligned payload interface.

**One interrupt-disabling class lock protects the zone, every CPU cache and both
depot layers.** The per-CPU cache objects are real, but there is no lock-free or
per-CPU-only fast path. This is a correctness-first adaptation, not XNU's scalable
locking design. It can be slower than the original allocator. No performance
improvement is asserted.

CPU cache readiness is published with release ordering after SMP has installed
all GS/TPIDR CPU numbers. Cache lookup uses an acquire load and never reads that
CPU register before readiness. Logical CPU IDs 0 through 63 can use caches;
others use the uncached path. ARM64 boot without SMP also remains uncached.
This is not a CPU-hotplug/offline protocol. NMI/reentrant allocation while a
class lock is held is not supported.

Cache metadata is allocated lazily through the fallible PMM, never recursively
through malloc. A new cache is attempted only when a payload slot is already
available, preventing the last payload page from being spent on empty cache
metadata. Failure to obtain metadata falls back to uncached allocation. The
metadata is retained for the lifetime of the kernel, because magazine containers
can migrate between depots. No cache-container teardown is implemented.

The free path marks the client object invalid, poisons its payload, then
publishes it to a magazine or zone bitmap, all under the class lock. A second
client free is rejected while metadata is valid. `zfree_ext` itself is a trusted
publication primitive: its caller must have just invalidated that object under
the same lock, exactly once. It is not a general independently safe public free.
Allocation reserves a live slot before unlocking and zeroing its payload.

Cached objects pin their pages. Allocation drains all caches of a depleted
class before requesting another page. `heap_trim()` drains every cache and the
central depot, detaches empty pages into a private list, unlocks, and returns
those pages to PMM. Valid client-live objects continue to pin their backing.
Normal free retains one truly empty spare per class, but that limit does NOT
bound cached payload, partially occupied pages or permanently retained cache
metadata. Drain loops hold interrupts disabled for potentially long intervals;
latency and pressure behavior need measurement. There is no automatic pressure
callback, adaptive working-set/depot policy or cross-class OOM reclaim loop.

Headers and bitmaps are still in writable payload backing. No guard mapping,
protected metadata or type separation is supplied. Invalid/unmapped pointers
may fault while their header is inspected; stale pointers after slot reuse are
not reliably detected. The extra live bitmap is not a memory-safety guarantee.

Without either feature flag the independent allocation algorithm is selected.
The module imports and added source are still visible to the V compiler, so
flag-off builds ALSO require validation; opt-in behavior is not a build-isolation
guarantee.

## Missing portions of the requested full port

The complete `kalloc.c` dispatch, typed/variable heaps, type signatures and
assignment policy remain untranslated. So do full zone creation/startup and
configuration policy, permanent/per-CPU/read-only zones, SMR deferred frees,
custom object-cache callbacks, guarded allocations, memory tagging/PAC,
sanitisers, diagnostics and the working-set/adaptive-cache policy.

Mach VM map/submap population, partially backed chunks, asynchronous expansion,
waiter wakeup/NOFAIL/WAITOK semantics, VM pressure/jetsam, VA sequestering and
large noncontiguous VM-backed allocations are NOT ported. The bridge uses
Vinix PMM instead. It does not pretend to emulate those contracts.

The full XNU split-lock/preemption protocol is also missing: introducing it
requires a separate concurrency proof and tests. The existing single-lock
core must not be called with only a CPU-local lock.

## Validation and reproducibility

Actually executed locally after these changes:

- `python3 tests/memory/heap_model_test.py`: 10 tests passed, including 100,000
  operations in the independent slab model and source checks.
- `python3 tests/xnualloc/reference_test.py`: 4 tests passed. Builds extracted
  C reference code with UndefinedBehaviorSanitizer and compares against models;
  includes 12,000 bitmap cases and 40,000 mixed-order buddy operations.
- `python3 tests/xnualloc/zone_model_test.py`: 6 tests passed, including 80,000
  mixed operations at depot limits 0/1/2/4 with four logical CPU caches, ownership
  and reclamation invariants, live survivors, duplicate frees and source hooks.
- `git diff --check`: passed for the local continuation.

**None of those tests executes V.** The protocol model is sequential under the
one-lock assumption; it is not a hardware or weak-memory-order concurrency test.
Eighteen actual V host test functions are supplied across `port_test.v`,
`zone_test.v` and `smoke_test.v`, but have not run locally: no V compiler or QEMU
was available. V/kernel GitHub Actions were queued at the last check during
publication, not successful.

CI pins the V 0.5.2 Linux archive by SHA-256, runs model/reference checks and
runs the actual V tests in debug/production. Its recipe is not evidence of a
successful result. Before merge, require flag-off, bitmap-only and zone-backend
builds on both architectures; actual host tests; boot self-tests; concurrent
cross-CPU allocation/free/drain with interrupt load; OOM/fault injection; and
latency/throughput/retained-page measurements against the pinned base.

The boot self-test now uses public malloc/free so it exercises the selected
backend. It runs before SMP and does NOT test real CPU-cache registration.

See `tests/xnualloc/README.md` for exact commands. Keep PR #179 in draft.
