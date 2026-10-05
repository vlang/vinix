# Vinix and Catalina allocation measurements: complete v4 campaign

The complete v4 campaign does **not** meet the target. Vinix's pooled hot 64-byte
allocation median is 537.758 ns/pair versus Catalina's 487.970 ns/pair, or
1.102× slower. Hot allocation is slower in both cohorts (1.036× and 1.240×);
touched 256 KiB mmap is also slower in cohort 1 (1.153×). The other five pooled
medians are faster. All four complete captures and all 168 raw samples remain
included in the [complete individual and pooled tables](comparison.md) and
[machine-readable observations](comparison.json). No v4 parity claim is made.

The earlier v3 candidate failed on five of six workloads against its faster
Catalina repeat. Its [complete comparison](earlier-candidate/final-v3-versus-catalina2/comparison.md),
both Catalina references and [v3 validation](earlier-candidate/v3-validation.md)
remain preserved. The v4 general optimizations passed the completed correctness
checks below, subject to the explicitly recorded audit and broader limitations.

The [predeclared campaign](campaign-plan.json) fixed four fresh captures in
`vinix-1`, `catalina-1`, `catalina-2`, `vinix-2` order after owned builds and
correctness guests finished. Its status string remains as originally declared;
the [completion record](validation/campaign-v4-complete/completion.json) records
all four actual exit-zero captures from 19:48:58 through 20:11:00 UTC on
October 2. Every capture has seven samples after full warmup in each of six
workloads. Earlier valid timings stay under `earlier-candidate/`.
Compilation failures, incorrect code generation, preboot failures, interrupted
runs and superseded diagnostics remain under `excluded/` or explicitly
historical validation directories. They do not participate in recomputation.
The two rejected v4 kernel candidates were never booted.

```sh
python3 tests/alloc-bench/results/2026-10-02-userspace/recompute.py
python3 tests/alloc-bench/results/2026-10-02-userspace/recompute.py --json
python3 tests/alloc-bench/results/2026-10-02-userspace/check-recompute.py
```

[recompute.py](recompute.py) requires exactly the four declared captures,
actual driver exit zero, explicit UTC start/end timestamps, predeclaration,
ABBA order and nonoverlap. Each capture needs complete metadata, all six
workloads, all 42 distinct raw samples, matching payload checksums, consistent
printed statistics and a completion record. The preserved
[strict validator](compare.py) and [benchmark source](../source-archive.json) are pinned to the
hashes in [source-snapshots.json](source-snapshots.json).
The original C bytes are recovered through the [source archive](../SOURCE-ARCHIVE.md),
with zero translation credit.

The script checks identical common QEMU settings/compiler flags, actual
QEMU argument lists matching those settings, 200,000 base iterations, seven
samples and full warmup. It pins the final Vinix kernel to `f944412c…`, loader
to `21258229…`, static libc to `0f6227b8…` and allocator patch to `ff14e55c…`,
using exact hashes in the [kernel](validation/kernel-x86_64.json) and
[libc provenance](validation/libc-builds.json). Catalina's freshly generated
assembly, executable, compiler/assembler commands and SDK must match between
its final captures. Platform and release metadata must remain identical within
each guest's two captures, as must Catalina's recorded OS version. A complete
slower capture produces a failing parity result.

Hot/mixed workloads use 200,000 allocation/free pairs per sample; the other
four use 10,000. Each cohort includes medians and full observed ranges. Pooled
statistics include all 14 raw samples per workload and guest, including
outliers. The ratio is Vinix median divided by Catalina median. The target
requires all six medians to be no slower in both individual cohorts and the
pooled result. Pooling uses all raw samples rather than cohort medians or ratios.

[Report integrity checks](validation/recompute-review.json) pass 170 cases,
including retention of every sample, complete slower data remaining a failed
target, and rejection of malformed, inconsistent or mismatched records and
provenance. [check-recompute.py](check-recompute.py) uses actual v3 raw records
only inside temporary fixtures with synthetic v4 config and timestamps. These
fixtures are never saved or published as v4 measurements.

## Guest and compiler setup

Both guests use QEMU 11.1.1 with the same common configuration:

```text
-machine q35,vmport=off
-accel tcg,thread=single,tb-size=1024
-cpu Penryn,kvm=on,vendor=GenuineIntel,+ssse3,+sse4.2,+popcnt
-smp 2,sockets=1,cores=2,threads=1
-m 4096
```

Vinix compiles the unchanged C benchmark with native GNU GCC 14.2.0. Catalina
10.15.7 uses GNU GCC 14.3.0 inside its guest to compile C to assembly. Its guest
lacks Apple's assembler/linker, so host Apple tools assemble/link that assembly
for x86_64 macOS 10.15 using MacOSX15.4 SDK. The executable runs in Catalina.
Manifests preserve actual commands and hashes; fresh guest code generation is
checked against retained linked assembly. The
[private serial reproduction recipe](catalina-reproduction/README.md)
preserves serial configuration, input fingerprints and build steps.

Both C compilations use `-std=c11 -O2 -Wall -Wextra -Werror -fno-builtin`.
GCC's minor versions differ and may affect code generation and ratios.
Firmware, boot disks and OS-specific peripherals differ as recorded in full
argument lists. The benchmark is single threaded with volatile payload checks.
Owned timing runs are sequential; other sessions still use this shared host.
These measurements describe QEMU TCG, not native hardware. Observed ranges
are not confidence intervals; equal sample indices do not indicate simultaneous
or statistically paired observations.

The [coordinator pause](validation/campaign-coordinator-guard-stop/reason.json)
followed completed `vinix-1`: its guard checked a shared source file changed
by another session. The measured frozen kernel, isolated source and libc stayed
unchanged. The corrected guard validates those frozen paths, then resumes
the same Catalina, Catalina, Vinix order. The complete first capture remains.
Separately, [closed correctness-image cleanup](validation/campaign-cleanup-overlap.json)
overlapped that first capture around 19:49:59–19:50:03 UTC. This is a conservative
estimated window; exact cleanup start was not recorded. The command duration
was 2.523 seconds. All first-capture samples remain included without adjustment.

Malloc workloads exercise each guest's user-space allocator/libc; mmap includes
mapping, faults and teardown; pipe creation includes syscall/object-lifetime
costs. They do not directly time Vinix slab allocation or XNU zones. Vinix's
corrected clock reads a free-running hardware counter. Interrupt-counted old
timings are excluded. The ARM allocator transcript also records precise/coarse
clock, absolute sleep, timerfd and futex regressions.

## Changes and source provenance

Default musl retains bounded free groups/direct mappings and provides
`malloc_trim`. V4 avoids mask atomics only when musl's published thread state
is exactly zero, preserves actual lock release across the negative-to-zero
transition, uses guarded nonzero native bit scans and removes redundant coarse
class fallback with retention enabled. Freeing a sole retained ordinary group
can publish the freed slot after all original metadata/header/redzone validation
and header invalidation. Conditions use general thread state, class/queue
membership and bounded footprints.

Five free direct-map buckets total at most 3,968 KiB. The conservative extra
backing envelope, including nested ordinary groups, remains below 16 MiB.
Live allocations/upstream fragmentation are outside that additional-retention
bound. `calloc` clears cached mappings; trimming preserves live objects and
`errno`. Unconditional assertion traps, metadata secrets, slot cycling,
ownership and redzone checks remain. The
[allocator code-generation proof](validation/allocator-codegen-v4/v4-codegen-proof.json)
records static/shared `-O3` and all final retained/disabled x86/ARM artifacts.

X86 atomic reads use naturally aligned width-exact loads with the prior locked
operation for misaligned operands. Generic sequentially consistent stores and
read-modify-write operations remain locked; explicit fences remain. Lock
release uses a byte release store before restoring interrupts. Memory copies/
fills use naturally aligned words within requested bounds, with byte prefix/
tails and copy fallback for incompatible alignment. Unsupported resources skip
advisory-lock cleanup they cannot require.

The combined kernel also includes the clock correction, lazy x86 anonymous
page faults, pipe backing allocated on first nonzero write and caller-stack
socket scratch storage. `MAP_POPULATE` stays eager; small ARM mappings keep their
eager policy. [Independent review](validation/independent-review-v4/review.json)
checks lifetimes, SC ordering, pointer-valued loads, interrupt sequencing,
object bounds and absence of hidden V allocations/recursive memory calls.

The [complete kernel patch](validation/kernel-v4/combined-kernel.patch)
reconstructs all 17 changed files from
`e29bcc4dc62e8861dcef5a52901b5214bac7f073`.
[Reconstruction validation](validation/source-reconstruction-review.json)
applies that patch to the recorded base and hashes every file against both
final manifests. Both actual full architecture builds pass with frozen V
`80c39942…`, unchanged 248 standard modules and Apple Clang 21. Final kernels
are `f944412c…` (x86) and `c617cb9d…` (ARM).

## Completed v4 checks and remaining validation

The [ARM allocator](validation/allocator-arm-v4/results.json) passes retained/
disabled libc, each dynamically/statically linked, compiled with GNU GCC14.2.0
and run under QEMU HVF on its recorded earlier corrected-clock kernel
`f43f7081…`. Each mode passes 1,910 original plus 22,776 supplemental
checks: 98,744 checks total. The supplement covers all 48 ordinary class
boundaries, 72-live-object batches, trimming with live objects, dirty reuse and
24 pthread publication/teardown cycles. All four modes return mapped-byte totals
to the warmed baseline after trimming. These virtual mapping totals are not RAM.

Retained ARM corruption children report `5,11,5,5` signals per mode; disabled
modes report `11,11,5,5`. ARM assertion traps are SIGTRAP. Normal child exit still
fails verification. The separate original/supplement sources run in every mode.
The [x86 allocator](validation/allocator-x86-v4/results.json) likewise passes
98,744 checks on the recorded corrected-clock kernel `0d02357a…`, before the
additional v4 kernel speed changes. Retained dynamic corruption signals are
`11,11,4,4`; retained static signals are `4,11,4,4`; both disabled modes report
`11,11,4,4`. X86 assertions trap with SIGILL. Every trim delta is zero, including
the disabled static mode's temporary 4 KiB mapping increase. The
[consolidation review](validation/v4-consolidation-review.json) independently
checks both actual raw transcripts: 197,488 checks and 32 rejected corruption
children. Final v4 kernel/libc integration is covered by both completed core
suites; the completed timing campaign is preserved above. Closed verification images were subsequently
removed to recover disk space; the native and ARM directories preserve exact
image hashes and removal disclosures alongside actual source/raw/provenance
records. Final timing inputs and captures are separate and remain preserved.

[Production packaging](validation/production-packaging-v4) records both actual
root userland builders using Alpine 3.21/pinned musl1.2.5. Both report PASS and
check final loader/static archive/header/links against packaged initramfs.
ARM runtime correctness/static desktop separately use compatible musl1.2.6.
Packaged libc remains in private storage with fingerprints here. After
verification, disk exhaustion required removing closed staging/devtools and
reproducible tar archives. Each directory preserves the removal disclosure and
archive hashes; those tar files are not claimed to remain available.

[X86 core](validation/core-x86_64-v4/run.json) and
[ARM core](validation/core-aarch64-v4/run.json) both complete exit zero on two
vCPUs with final ff14 static libc and their final v4 kernels. Both cover
supported locks surviving unrelated pipe/socket closes, POSIX lock release
on dup close and flock lifetime through final handle close, alongside existing
mapping/pipe/concurrent-write/socket checks. ARM's persistence reboot passes;
its initial preboot Limine failure is preserved in `excluded/`.

[Memory runtime verification](validation/independent-review-v4/memory-runtime)
passes 361,573 host ASan/UBSan cases against the exact new implementation,
including guard-page boundaries, alignments, read-only sources and fill
conversions. Actual x86/ARM objects contain no SIMD or recursive runtime calls.
All 10 heap model tests pass with geometry corrected to the current 16-word
slab layout; the [raw log](validation/kernel-v4/heap-model.log) is retained.

The [allocation audit](validation/allocation-audit-v4/comparison.json) reports
432 sites versus the frozen baseline's 443, removing 11 socket escape warnings
and adding no kinds/counts. The literal unchanged allowlist and extracted x86
source audit still exit1. Existing audit limitations remain recorded separately
from actual full build/core PASS; the repository audit is not reported as passing.

The [static desktop build](validation/static-desktop-v4/build.json) passes
with frozen sources/final ff14 libc; its binary is `342951b1…`. The
[actual v4 desktop harness](validation/desktop-perf-v4/validation.json) completes
all 43 required rows across ops, churn, cache, idle, apps and drag using the
final ARM kernel, loader and desktop. Idle/apps/drag total CPU readings are
0.26%, 0.57% and 3.40%. One round completes all three 20-second observations.

The [complete unfiltered diagnostics](validation/desktop-perf-v4/results.json)
still show ops/churn memory growth, including 1,217 bytes per pipe operation
and 6,728 bytes per `/proc` read in 200-call batches. Successful scenario
execution does not establish that every kernel class stays flat. Historical
socket settlement measurements retain broader read/create/close growth, and
the previous four-vCPU 80-waiter baseline and candidate both stalled during
thread creation. Those records remain linked in
[v3 validation](earlier-candidate/v3-validation.md). These two-vCPU checks do
not establish universal SMP stability or leak-free kernel behavior.
