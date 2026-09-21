# Reclaimable Vinix heap: implementation and comparison

## Status and provenance

Prepared 2026-09-11 against Vinix commit
`7c085707f535e498ff2ce9a6447d8a5b59844388` and subsequently integrated onto
`master`. The original `physical.v` and
`klock_amd64.v` blobs were reconstructed from the GitHub connector and checked
against Git blob hashes `f8b11f618825eefa39a32bc33e5b2e8af43a3e99` and
`9dfd1a9c85549b011a9fe286b13ef0c2b4a7855e` respectively.

This is an independent V implementation of familiar slab techniques, NOT a
C-to-V translation of Apple's allocator. No XNU implementation is copied.
XNU's inspected `zalloc.c` carries APSL 2.0 terms; Vinix carries GPL v2.
Source translation must not be treated as permission to discard the original
license. A literal import needs licensing review and suitable permissions.

Validation now includes the ten Python model/source checks, the 18-function V
host suite in debug and production, six debug kernel build variants across
x86_64/AArch64, and x86_64 QEMU boot self-tests. The Python model is still not an
SMP, weak-memory-ordering, or interrupt-safety test. The in-kernel performance
comparison is recorded in `docs/xnualloc/BENCHMARK.md`.

## Comparison with XNU

Reference: Apple's public XNU commit
`f6217f891ac0bb64f3d375211650a4c1ff8ca1ea` (import named `xnu-12377.1.9`). This
pins the inspected source; it is not a claim that every Apple shipping kernel
uses exactly that revision or configuration.

Vinix currently allocates physical pages with a globally locked bitmap scan.
Its heap uses nine classes, 8 through 2048 bytes in powers of two. Each class
has one lock and an intrusive free-object chain. Slab pages never return to the
PMM. Larger heap objects use contiguous physical pages plus a whole metadata
page. Page allocations, kernel virtual mappings, and heap objects are distinct
layers; replacing the small-object heap does not replace the other two.

XNU's zone layer tracks allocation state and page/chunk occupancy, can reclaim
empty backing, and offers per-CPU magazines, depots, and batched circulation.
Its cache design explicitly depends on preemption control. General allocations
also involve kalloc heaps and, on the relevant paths, type-based segregation.
VM-backed allocations use Mach VM facilities rather than Vinix's direct PMM
path. The zone source imports scheduling, locks, VM, pmap, diagnostics and
security infrastructure: it is not a self-contained malloc.c to translate.

These are substantial architectural advantages in reclaimability, scalability
and hardening, not evidence of a measured speedup on Vinix. A small, uncontended
intrusive allocator can have a shorter fast path. XNU itself cites Bonwick and
Adams' magazine design and FreeBSD UMA in its cache description.

Primary references:

- Vinix heap and PMM: https://github.com/vlang/vinix/blob/7c085707f535e498ff2ce9a6447d8a5b59844388/kernel/modules/memory/physical.v
- XNU zone implementation, including cache design near lines 250-370: https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/kern/zalloc.c
- Apple's allocator architecture and type-isolation explanation: https://security.apple.com/blog/towards-the-next-generation-of-xnu-memory-safety/
- Existing ARM64 interrupt-state snapshot: https://github.com/vlang/vinix/blob/7c085707f535e498ff2ce9a6447d8a5b59844388/kernel/modules/klock/klock_arm64.v

## Implemented scope

`slab.v` replaces the original Slab implementation, and `physical.v` wires it
into the existing malloc/free/realloc/calloc entry points. Initialization is
lazy, without heap allocation. The 14 classes are 16, 32, 48, 64, 96, 128, 192,
256, 384, 512, 768, 1024, 1536 and 2048 bytes.

Each page has an 80-byte header on the intended 64-bit layouts, including four
64-bit allocation words. Payload begins at a 16-byte-aligned offset. Tail bits
are permanently occupied. A partial-page list supports constant-time list
changes; full pages need no list. Allocation checks at most four bitmap words
and uses bounded bit search. Partial pages are preferred over an empty spare.

When the last object is freed, at most one empty page is retained per class.
Further empty pages are detached under the class lock and returned to the PMM
after releasing it. `memory.heap_trim()` releases all currently observed spare
pages, returning bytes released. It is not yet wired into an OOM callback.
Idle spare retention is at most 14 * 4096 = 56 KiB when quiescent; temporary
in-flight detached pages and partially occupied pages are outside that bound.

Malloc zeroing and free poisoning remain. Allocation zeroing is outside the
class lock, after the slot is marked live. Header and slot checks catch some
invalid frees and double frees while the page is still owned by that slab.
They do NOT establish arbitrary-pointer validation or reliable detection after
address reuse. Headers share writable pages with objects, so this is not
XNU-style protected/external metadata, type isolation, or VA sequestering.

Additional fixes reject calloc multiplication and large-allocation rounding
/metadata-page overflow; failed growing realloc keeps its original allocation.
The x86 lock now snapshots interrupt state before publishing unlock, matching
the ordering already used by Vinix's ARM64 lock.

The physical allocator and virtual-memory implementation are otherwise
unchanged. Infallible PMM exhaustion still panics. Large heap allocations still
need contiguous physical backing and the extra metadata page. Realloc-zero
behavior is retained rather than imposing a new API contract.

## Tradeoffs and work not included

Intermediate size classes reduce rounding for some requests (for example,
65 bytes uses a 96-byte class rather than 128). This is geometry, not a measured
workload result. The larger header reduces object density in existing classes;
small allocations now consume at least 16 bytes instead of 8. More classes can
increase partially occupied-page fragmentation. One cached spare avoids PMM
churn in single-object reuse but does not eliminate burst-induced churn.

There are no per-CPU magazines, cross-CPU return queues, allocator reserves,
NOWAIT semantics, type-aware heaps, separate metadata mappings, guard pages,
or a noncontiguous VM-backed large-object allocator in this patch. Adding
magazines requires retaining page liveness for every cached object and draining
caches before reclamation; otherwise a speed optimization can introduce UAF.

## Validation

From a complete patched Vinix checkout:

```sh
python3 tests/memory/heap_model_test.py
```

The model checks all size classes across several pages, full/partial/empty
transitions including one-slot pages, partial-before-spare selection, payload
zeroing/poisoning, resident-page invalid/double frees, tail bits, arithmetic
bounds, x86 snapshot source order, and mixed-size churn. It deliberately models
an abstract PMM rather than claiming to execute the kernel PMM.

Build the actual kernel in debug and production with the repository's toolchain
and dependencies. Enable the boot tests by adding `VFLAGS='-d heap_selftest'`
to the kernel make invocation. For example, using the native Linux CI flags:

```sh
# V must name an already built V compiler by absolute path.
cd kernel
./get-deps
make PROD=false V="$V" VFLAGS='-d heap_selftest' \
  CFLAGS='-Ulinux -U__linux -U__linux__ -U__gnu_linux__ -D__vinix__ -O2 -g -pipe'
```

This recipe has been exercised with V 0.5.2. Boot the resulting image through
the repository's normal image workflow. The expected successful
serial marker is `heap: self-test passed`. The self-test runs from pmm_init
before SMP startup; its free-page comparisons require no concurrent clients.
It exercises the actual V allocator and allocation API, not the Python model.

Before default enablement, also boot-test ARM64, run SMP allocation/free on
different CPUs, interrupt-heavy workloads, concurrent trimming, and
OOM/fragmentation stress. Native throughput, p50/p99 latency, lock contention,
peak pages, and pages retained after churn remain necessary; QEMU TCG results
alone do not justify production deployment.
