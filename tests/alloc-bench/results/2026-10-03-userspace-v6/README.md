# Vinix and Catalina allocation measurements: v6 follow-up

The [complete v5 campaign](../2026-10-03-userspace-v5/README.md) failed the
hot-allocation target in cohort 2 and pooled samples. Its other five workloads
passed both cohorts and pooling. Every preceding measurement remains preserved.
V6 adds a general ordinary single-thread allocation path and reuses values
already computed while validating a free. Its complete fresh campaign **passes
the predeclared target**: all six Vinix medians are below Catalina in both
individual cohorts and in pooled raw samples. These are QEMU measurements;
they do not establish native hardware performance or a cause for variation
between captures.

All four complete captures and all 168 raw samples remain in the
[individual and pooled comparison](comparison.md) and
[machine-readable observations](comparison.json). Pooled medians use every
one of the 14 samples per workload and guest:

| Workload | Vinix ns/pair | Catalina ns/pair | Vinix/Catalina |
| --- | ---: | ---: | ---: |
| malloc_hot_64 | 228.8500 | 387.6525 | 0.590348 |
| malloc_mixed_batch_64 | 313.8025 | 777.9900 | 0.403350 |
| malloc_touch_262144 | 1537.3000 | 18458.8000 | 0.083283 |
| mmap_anon_4096 | 11432.8000 | 27426.5000 | 0.416852 |
| mmap_touch_262144 | 669947.7500 | 1924765.8500 | 0.348067 |
| pipe_create_close | 29889.3500 | 70205.8500 | 0.425739 |

## Fixed measurement protocol

The [original predeclaration](campaign-plan.json), declared at 22:01:48 UTC on
October 2, fixes four fresh captures in `vinix-1`, `catalina-1`, `catalina-2`,
`vinix-2` order after owned builds and correctness guests finish. The
[actual completion record](validation/campaign-complete/useralloc-v6-final-cohorts.json)
and [exit-zero coordinator record](validation/campaign-complete/useralloc-v6-final-cohorts.exit.json)
preserve all four captures from 22:57:36 through 23:09:12 UTC on October 2.
[Final readiness](validation/campaign-complete/useralloc-v6-final-readiness.json)
records all 16 completed gates at 22:56:39 UTC, before the first capture.
[Independent coordinator review](validation/campaign-complete/useralloc-v6-root-glue-review.json)
checks 34 input guards and 23 validation cases. The plan's complete bytes,
including the original pending status string, remain unchanged. The campaign
uses the unchanged six workloads, 200,000 base iterations, seven samples and
full warmup. Hot/mixed workloads use 200,000 allocation/free pairs per sample;
the other four use 10,000. All 168 raw samples, including outliers and complete
slower captures, must participate. Each individual cohort and all 14 pooled
samples per guest/workload must place every Vinix median at or below Catalina.

```sh
python3 tests/alloc-bench/results/2026-10-03-userspace-v6/recompute.py
python3 tests/alloc-bench/results/2026-10-03-userspace-v6/recompute.py --json
python3 tests/alloc-bench/results/2026-10-03-userspace-v6/check-recompute.py
```

[recompute.py](recompute.py) pins the original plan's complete byte hash and
requires precisely its four captures, actual exit-zero driver records,
explicit UTC declaration/start/finish times, ABBA order and nonoverlap.
The unchanged [strict validator](compare.py) requires complete metadata, all
six workloads, 42 distinct samples per capture, payload checksums, consistent
printed statistics and `ALLOC-DONE`. The unchanged [benchmark](bench.c) and
validator are pinned by [source fingerprints](source-snapshots.json).
The kernel remains the approved v5 x86 kernel `16140916…`; final v6 loader,
static archive and allocator patch are `ad78977e…`, `8d5c3dee…`, `ec459e48…`.
Saved [kernel](validation/kernel-x86_64.json) and
[libc](validation/libc-builds.json) provenance ties these exact inputs to
completed artifact validation. Actual QEMU arguments must match the plan;
platform/release/compiler metadata must stay identical between each guest's
captures. Catalina assembly, binary, commands, SDK and OS version must also
match between captures.

The [integrity suite](validation/recompute-review.json) passes all 170 retained
protocol checks. Its earlier v3 raw captures occur only in temporary fixtures
with synthetic v6 config/timestamps, and never become v6 timings. Malformed or
mismatched captures are rejected; complete slower data remains a failed target.
Pooled statistics use raw observations, not cohort medians or ratios. Observed
ranges are not confidence intervals, and sample numbers do not denote
simultaneous paired measurements.

Both guests use QEMU 11.1.1 with these identical common settings:

```text
-machine q35,vmport=off
-accel tcg,thread=single,tb-size=1024
-cpu Penryn,kvm=on,vendor=GenuineIntel,+ssse3,+sse4.2,+popcnt
-smp 2,sockets=1,cores=2,threads=1
-m 4096
```

Vinix compiles the unchanged benchmark with native guest GNU GCC 14.2.0.
Catalina 10.15.7 uses guest GNU GCC 14.3.0 to produce assembly; host Apple tools
assemble/link it for x86_64 macOS 10.15 using the MacOSX15.4 SDK because the guest
lacks Apple's toolchain. Both C compilations use
`-std=c11 -O2 -Wall -Wextra -Werror -fno-builtin`. The unchanged
[Catalina reproduction recipe](../2026-10-02-userspace/catalina-reproduction/README.md)
retains setup/toolchain details. GCC minor versions, firmware, disks and OS
peripherals differ. Other sessions continue running on the shared host. These
measurements describe QEMU TCG, not native hardware. Malloc measures user-space
allocator behavior; mmap includes mapping, first touch and teardown, and pipe
creation includes kernel object/syscall costs. These are not direct slab or
XNU-zone microbenchmarks.

## Allocator implementation and independent review

The [final allocator patch](validation/libc.patch) consumes an available
ordinary slot when the request is below `MMAP_THRESHOLD`, `need_locks` is zero,
the actual volatile malloc lock is zero and the requested class is active.
With the sole group it can also refill from already active freed slots, using
the same activation, assertion and bounce decay as the existing path. Page
activation, group traversal, mapping, multithread state and negative lock
transitions use the original allocator body, preserved byte for byte as the
`noinline` `malloc_slow`. Slot selection and the shared `enframe` retain address
cycling and header/nominal-size stamping. No workload-specific request test or
special size branch was introduced.

Freeing receives the validated index, actual stride and ordinary class stride
from an inlined metadata helper. The original alignment, offset encoding,
group back-reference, live-slot, secret, class bounds, mapped bounds, nominal
size, terminator and overflow checks remain before header invalidation and
freed-mask publication. `int` class/units temporaries preserve original
integer promotions. Direct class-63 mappings additionally require one slot
and a nonzero mapping length before any stride use, avoiding an out-of-bounds
class-table access for invalid metadata. The retention policy, public wrappers,
realloc/aligned/calloc paths and allocator fork glue retain v5 behavior.

[Independent final review](validation/independent-review/review.json) passes
with no blocker. It checks actual final source hashes, all 24 malloc/free/realloc
static/PIC objects and all 12 corresponding actual mallocng archive members,
including duplicate wrapper basenames. Cached free details remain scalar;
all eight free objects and warm malloc wrappers have no added canary. Warm
malloc wrappers have no call and tail-branch to the original slow function;
x86 saves two registers without allocating a stack frame, and ARM needs no
stack frame. Defined assertion traps remain in the generated code. Source and
object shape alone do not establish a performance improvement.

The [v5 kernel/source reconstruction proof](../2026-10-03-userspace-v5/README.md)
remains the kernel implementation reference: no new kernel optimization is
part of v6. Approved x86/ARM kernels stay `16140916…`/`3d721f31…`, with frozen V
`80c39942…`, both architecture builds and all 248 standard modules unchanged
before/after those builds. The same-checker allocation audit remains historical:
440 sites in both v4/v5 and unchanged literal allowlist failure, exit 1. It is
not reported as passing or as proof of a leak-free kernel.

## Correctness and production evidence

[The eight-mode correctness summary](validation/v6-verification-summary.json)
and actual [x86](validation/allocator-x86_64/results.json)/
[ARM](validation/allocator-aarch64/results.json) serial logs cover both
retained/disabled policies with dynamic/static linkage on each architecture.
Each mode completes 1,910 original and 30,942 supplemental checks, totaling
262,816 checks. All 32 corruption children terminate by a signal and all eight
post-trim mapping deltas are exactly zero. Mapping-byte checks do not measure
physical RAM. The suites exercise all 48 ordinary class boundaries, 72-live
bursts, dirty reuse, trimming with live allocations, 24 thread-transition
cycles, 18 refill request sizes for 129 rounds each with a live allocation,
and allocation/reallocation/trim in all three public atfork callbacks across
eight forks with a worker and after its exit. These finite workloads do not
prove exhaustive thread interleavings or instrument every internal branch.
Clock, absolute sleep, timerfd and futex checks also complete. Embedded actual
input archives and final manifests were independently rehashed.

Actual [x86](validation/production-packaging/amd64/root-review.json) and
[ARM](validation/production-packaging/aarch64/root-review.json) production
userland archives pass separate completed packaging checks on Alpine 3.21's
pinned musl 1.2.5. Packaged x86 loader/archive match the timing inputs.
Packaged ARM musl 1.2.5 loader/archive `0bdb92db…`/`b58d975a…` differ from ARM
runtime/static-desktop musl 1.2.6 `8289c205…`/`2a83589e…`; their evidence stays
separate. The actual [production-hook static desktop build](validation/static-desktop/build.json)
passes, links final v6 libc and retains `malloc_trim`, producing `f921ddf5…`.
Actual link commands, linked symbols and full link-map fingerprint are saved.
The [final core gates](validation/core/final-gates.json) and
[independent evidence audit](validation/core/evidence-audit.json) record three
fresh exit-zero static-libc modes on two vCPUs. [X86 with LA57](validation/core-x86_64/run.json)
passes all 53 core markers and the 256 TiB boundary; [x86 four-level](validation/core-x86_64-four-level/run.json)
passes the same full core suite and explicitly skips only the unsupported
LA57 boundary. It uses the same kernel/ISO/test binary, changing only the CPU's
LA57 feature. [ARM](validation/core-aarch64/run.json) passes all 51 core markers,
16 KiB page-table boundary checks and its second persistent boot. Each mode
contains exactly one `PAGETABLE CHECK: PASS`. Exact original compile flags
produce byte-identical executed test binaries. Actual QEMU arguments, static
archive/CRT linkage, source/binary hashes and boot ISO/disk embedded-input
checks are retained. These use final v6 static libc with unchanged approved
v5 kernels and the existing `f71d45c7…` boundary supplement.

The [complete desktop harness](validation/desktop-perf/validation.json) passes
all 43 required rows across ops, churn, cache, idle, apps and drag, with the
final ARM kernel, musl 1.2.6 loader and static desktop, before timing. Its
[actual runner exit](validation/desktop-perf/preparation/driver.exit.json) is zero;
[raw diagnostics](validation/desktop-perf/results.json) and serial text preserve
existing ops/churn growth. These observations do not establish flat kernel
memory or causal improvements over preceding captures.

The resident controller's [preserved traceback](excluded/desktop-perf-controller/pipeline.log)
comes from unpacking two values returned by a three-value validation helper.
The actual guest already completed successfully. The
[corrected validator](excluded/desktop-perf-controller/validate-completed.py)
checks exact equality of all 43 raw/result rows and recorded final artifacts;
[recovery](excluded/desktop-perf-controller/recovery.json) records its exit zero
and that the guest was not repeated. This is a controller glue error, not a
guest scenario failure. Earlier kernel/test-harness failures remain linked
in the [v5 report](../2026-10-03-userspace-v5/README.md).

## Preserved v5 hot-path diagnostic

[The independent diagnostic summary](validation/v5-hot-diagnostic/summary.json)
preserves two boots, 12 fresh dynamic/static executions, two measured phases
per execution and all 168 raw hot samples. Outside-loop probes found the same
sole nested class-4 group, eight slots, 80-byte stride, disjoint masks, slot
rotation and zero thread/malloc-lock state; all 1,536 allocation probes met the
existing single-thread free conditions. Those observations do not support a
class/retention/group/free-eligibility/lock-state change as the explanation for
v5 timing variation. Guest CPU time closely follows wall time, but both clocks
can advance during a host pause, so this does not establish host noise or a
specific TCG mechanism. The cross-compiled private sampler's code layout and
extra probes differ from the canonical guest-compiled benchmark; its samples
never replace or revise canonical v5 or v6 captures. A preflight symbol-resolution
failure and earlier compilation errors remain preserved in
[excluded diagnostic setup evidence](excluded/v5-diagnostic-preflight/).

The allocator change is committed as `ba930704` (`musl: streamline ordinary
single-thread allocation`). [The frozen source/object manifests](validation/source-freeze/source-object-manifest-sha256.json)
and [implementation checkpoint](validation/source-freeze/evidence/v6-checkpoint.json)
retain exact final inputs. All completed canonical captures remain selected
by the original fixed protocol. No temporary fixture or diagnostic becomes
campaign data. The preceding [v4 results and diagnostics](../2026-10-02-userspace/README.md)
remain preserved, including ops/churn growth and four-vCPU waiter stalls;
successful two-vCPU suites do not establish universal SMP stability.
