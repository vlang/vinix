# Vinix and Catalina allocation measurements: v5 follow-up

The [complete v4 campaign](../2026-10-02-userspace/README.md) failed the target:
hot allocation was slower in both repeats, and touched mmap in one. Every v4
measurement remains preserved. V5 targets general mallocng framing and
page-table teardown costs, but its complete fresh campaign **also fails the
target**. All six medians are faster in cohort 1; hot allocation is slower in
cohort 2 and pooled. Its cohort-2 median is 573.115 ns/pair versus Catalina's
436.040 ns/pair (1.314× slower). The other five workloads are faster in both
cohorts and pooled. These observations do not establish why timing varies
between captures.

All four complete captures and all 168 raw samples remain in the
[individual and pooled comparison](comparison.md) and
[machine-readable observations](comparison.json). Pooled medians use all 14
samples per workload and guest:

| Workload | Vinix ns/pair | Catalina ns/pair | Vinix/Catalina |
| --- | ---: | ---: | ---: |
| malloc_hot_64 | 550.070 | 473.913 | 1.160699 |
| malloc_mixed_batch_64 | 491.207 | 838.058 | 0.586126 |
| malloc_touch_262144 | 1954.100 | 15955.000 | 0.122476 |
| mmap_anon_4096 | 15099.650 | 25475.250 | 0.592718 |
| mmap_touch_262144 | 862624.450 | 1668026.400 | 0.517153 |
| pipe_create_close | 28820.900 | 49255.200 | 0.585134 |

## Measurement method

The [immutable predeclared campaign](campaign-plan.json) fixed four fresh
captures in `vinix-1`, `catalina-1`, `catalina-2`, `vinix-2` order after owned
builds and correctness guests finished. The
[completion record](validation/campaign-complete/completion.json) preserves
all four exit-zero captures from 21:41:59 through 21:54:04 UTC on October 2.
The plan's pending status string remains as originally declared. The campaign
used the unchanged six workloads,
200,000 base iterations, seven samples and full warmup. Hot/mixed workloads
have 200,000 allocation/free pairs per sample; the other four have 10,000.
Each capture must retain all 42 raw samples and its actual exit-zero driver
record. Both individual cohorts and pooling all 14 samples per guest/workload
must show every Vinix median at or below Catalina's median. No samples,
outliers or complete slower captures are filtered out.

```sh
python3 tests/alloc-bench/results/2026-10-03-userspace-v5/recompute.py
python3 tests/alloc-bench/results/2026-10-03-userspace-v5/recompute.py --json
python3 tests/alloc-bench/results/2026-10-03-userspace-v5/check-recompute.py
```

[recompute.py](recompute.py) requires exactly the four declared captures,
explicit UTC predeclaration/start/end times, ABBA order and nonoverlap. The
preserved [strict validator](compare.py) requires complete metadata, all six
workloads, 42 distinct samples, payload checksums, internally consistent
printed statistics and `ALLOC-DONE`. The unchanged [benchmark](bench.c) and
validator are pinned by [source fingerprints](source-snapshots.json).
The final kernel, loader, static archive and allocator patch are pinned to
`16140916…`, `6cf9e5ea…`, `eb50810a…` and `5ff7f0e2…` in the saved
[kernel](validation/kernel-x86_64.json) and
[libc](validation/libc-builds.json) manifests. Actual QEMU arguments must match
the declared settings, and each guest's platform/release/compiler metadata
must stay identical between its captures. Catalina's fresh assembly, binary,
commands, SDK and OS version must also match between captures.

The [integrity suite](validation/recompute-review.json) passes 170 cases.
It uses earlier v3 raw data solely in temporary fixtures with synthetic v5
configuration/timestamps, never publishing those fixtures as v5 timings.
Complete slower data remains a failed target; malformed or mismatched data is
rejected. Pooled medians use raw observations, rather than cohort medians or
ratios. Observed ranges are not confidence intervals, and sample numbers do
not denote simultaneous paired measurements.

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
assemble/link it for x86_64 macOS 10.15 with the MacOSX15.4 SDK because the
guest lacks Apple's toolchain. Fresh guest assembly is checked against the
linked assembly. Both C compilations use
`-std=c11 -O2 -Wall -Wextra -Werror -fno-builtin`. GCC minor versions differ;
firmware, disks and OS peripherals differ as recorded by actual arguments.
The unchanged [Catalina reproduction recipe](../2026-10-02-userspace/catalina-reproduction/README.md)
preserves setup and toolchain details. Other sessions continue using the shared
host. These timings describe QEMU TCG, not native hardware.

Malloc workloads measure user-space libc/allocator behavior; mmap includes
mapping, first-touch faults and teardown, and pipe creation includes kernel
object/syscall costs. These are not direct slab/XNU-zone microbenchmarks.

## General changes and implementation proof

[The allocator patch](validation/libc.patch) bypasses old offset selection
only when a slot has zero whole units of slack, where upstream clamping
always chooses offset zero. Positive-slack address cycling and slot rotation
remain. A shared size-stamping helper accepts the index already known by
malloc, avoiding a redundant header write/read; realloc's wrapper preserves
the existing low five index bits. All metadata, secret, bounds, live-mask,
redzone and old-header invalidation checks remain.

The existing retention policy remains bounded: one ordinary free group per
eligible class with at most 128 KiB backing, and five direct-map buckets whose
upper bounds total 3,968 KiB. The conservative additional retention envelope,
including nested groups, stays below 16 MiB; live allocations and upstream
fragmentation lie outside that bound. Dirty `calloc` reuse, trimming with live
objects and thread publication/teardown keep the established behavior. The
[v4 explanation and shared validation](../2026-10-02-userspace/README.md)
preserve the preceding allocator/kernel changes.

X86 page-table teardown first checks a live successor, then scans all 512
entries if needed. Any nonzero software-only entry also keeps its table alive.
A surviving child makes all ancestors nonempty. Empty children are detached
from parents before completed TLB invalidation and physical reclamation. The
four-level root survives; five-level PML4 reclamation requires a full empty
scan and clearing its PML5 parent edge first.

[Independent source/object review](validation/independent-review/review.json)
finds no blockers. It reproduces all 24 malloc/free/realloc static/PIC
disassemblies and checks all 12 actual mallocng static archive members.
All eight free instruction sequences are identical to v4, retaining its
hardening. Actual generated unmap/helper C and relocation-bearing x86 object
code preserve detachment, fencing/shootdown and free ordering without hidden
V allocations. Intel's [SDM section 4.10.4.1](https://www.intel.com/content/dam/www/public/us/en/documents/manuals/64-ia-32-architectures-software-developer-vol-3a-part-1-manual.pdf)
documents that INVLPG also invalidates paging-structure caches for the current
PCID, supporting invalidation after empty ancestors are detached.

The [complete patch](validation/independent-review/combined-kernel.patch)
reconstructs all 18 changed kernel files from
`e29bcc4dc62e8861dcef5a52901b5214bac7f073`.
[Independent reconstruction](validation/independent-review/source-reconstruction-review.json)
checks every reconstructed source against both final manifests. The actual
[x86](validation/kernel-x86_64/build.json) and
[ARM](validation/kernel-aarch64/build.json) builds pass, with kernels
`16140916…` and `3d721f31…`, frozen V `80c39942…` and all 248 standard modules
unchanged before/after each build. Other sessions' shared source edits are
excluded from these isolated inputs.

## Correctness and production validation

[X86 allocator](validation/allocator-x86_64/results.json) and
[ARM allocator](validation/allocator-aarch64/results.json) transcripts cover
both retained/disabled policies, each dynamically/statically linked: eight
actual modes. Each runs 1,910 original plus 22,776 supplemental checks, or
197,488 checks total. All 32 corruption children exit abnormally and all eight
trim deltas return to zero. These mapping-byte checks do not measure physical
RAM. The sources exercise all 48 ordinary class boundaries, 72-live-object
batches, dirty reuse, live-object trimming and 24 pthread transition cycles;
clock, absolute sleep, timerfd and futex checks also pass. These allocator
runs use final v5 libc on the recorded v4 kernels `f944412c…`/`c617cb9d…`;
final v5 kernel integration is checked separately by core regressions.

Both actual root userland builders pass
[production packaging validation](validation/production-packaging/root-review.json)
on Alpine 3.21/pinned musl 1.2.5. The packaged x86 archive/loader match the
timing inputs. Packaged ARM musl 1.2.5 is separately fingerprinted; ARM runtime
checks and the static desktop use compatible musl 1.2.6. The
[production desktop build](validation/static-desktop/build.json) passes and
links v5 libc; final binary `30b42201…` includes `malloc_trim`.
Actual link commands, symbols, an allocator link-map excerpt and full-map
fingerprint are retained.

[Final core gates](validation/kernel-final-gates.json) record three completed
exit-zero suites on two vCPUs. [X86 with LA57](validation/core-x86_64/run.json)
exercises the 256 TiB boundary; [x86 without LA57](validation/core-x86_64-four-level/run.json)
explicitly skips only that boundary and passes the lower three. The four-level
run uses the same kernel/ISO/core binary, changing only the CPU's LA57 feature.
[ARM](validation/core-aarch64/run.json) passes the 16 KiB page-table boundaries
and persistence reboot. All use the final `f71d45c7…` boundary supplement,
including sparse earlier entries, sibling survival, holes, absent-page faults,
fork COW and zeroed reuse, alongside the full existing core suite. Earlier
passing test variants remain in `earlier-validation/`.

The [complete desktop harness](validation/desktop-perf/validation.json) passes
all 43 required rows across ops, churn, cache, idle, apps and drag, using the
final ARM kernel/loader/static desktop, before timing. Its
[raw diagnostics](validation/desktop-perf/results.json) retain existing
ops/churn growth and do not show a universally flat kernel heap. The single
20-second idle/apps/drag observations report 0.19%, 0.56% and 2.58% total CPU;
these are not attributed as causal improvements over earlier noisy runs.
The [same-checker allocation audit](validation/allocation-audit/comparison.json)
reports 440 sites in both frozen v4 and v5, with no path/kind count regression.
Both extracted architecture compilations succeed, but the unchanged literal
allowlist still fails, exit 1. This audit is not reported as passing.

The initial [missing-uACPI link failure](excluded/kernel-missing-uacpi/build.json)
was corrected by supplying the untracked dependency and was never booted.
An initial [supplement waitpid failure](excluded/core-wait-eintr/run.json)
exposed the test helper's missing EINTR retry. A separate
[four-level optional probe](excluded/core-four-level-limit-errno/run.json)
expected EINVAL but received the existing address-limit ENOMEM; its
replacement explicitly checks x86 CPUID.LA57 and only skips when unsupported.
These test-harness failures remain separate from completed timing data.
The [historical v4 diagnostics](../2026-10-02-userspace/README.md)
retain broader ops/churn growth and four-vCPU waiter stalls; successful
two-vCPU suites do not establish a leak-free kernel or universal SMP stability.

The implementation changes are committed as `37884975` (allocator framing)
and `9d6f3e1a` (x86 page-table teardown and boundary regression). All final
source/object/runtime proofs are retained here; shared historical validation
is linked to the committed v4 report rather than duplicated.
