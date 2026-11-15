# Warming the performance observer across CPUs

The V slab sampler now warms its reader on every CPU admitted by its saved
affinity mask before each baseline snapshot. This addresses the cold-reader
page changes reproduced in [the placement diagnostic](linux-performance-reader-placement.md).
It does not relax the existing requirement for zero object, backing-page and
large-page deltas in the fixed workload.

The shared `perfreader` module performs 64 reads per CPU, alternating the two
caller-owned snapshot buffers. Each CPU selection is checked against actual
execution with a bounded migration wait. Before restoring the original mask,
it returns to the entry CPU. If the caller has just narrowed its mask and is
still migrating, it chooses an admitted CPU instead. Failed reads also attempt
to restore placement and the saved mask. Successful restoration is reread and
verified; failures stop the sampler rather than skipping warmup.

Warmup occurs after the existing workload warm cohort and before its original
grace wait. Workload probe bodies, 200-operation/300-program counts, grace waits,
scenarios, measured duration, RAM and CPU count are unchanged. The measured
workload uses its original affinity mask. Warmup prints nothing between the
measured snapshots. A completed pair emits its `PERF-READER` proof afterward,
including the saved/restored mask and the actual configured reads per CPU.

`reader-warm-check` requires exactly 40 ordered proofs, each immediately after
its complete measured pair. `check` also invokes the unchanged strict complete
heap policy. `observe` preserves nonzero counters with `qualification=false`.
The original checker remains independently usable and still rejects the
preceding four-delta capture. Public tests exercise 94 default-profile and 93
ARM-profile proof refusals in normal and production builds, including missing,
duplicate, moved, malformed, wrong-mask and wrong-count proofs.

The native `heap-reader` probe exercises restricted affinity, three invalid CPU
selections, an empty-mask refusal and restoration after a failed procfs read.
It then warms both CPUs and forces 200 measured reads from CPU 0 to a final
snapshot on CPU 1. The existing native checker retains its strict class/page,
large-page and corruption checks, with an additional exact control proof.
Its reader mode adds eight proof-refusal controls to the existing 52 ARM / 44
x86 controls. The bounded launcher retains its original placement mode and
accepts an explicit `reader` mode for this probe.

Development attempts remain visible. The first warmup restored the mask while
leaving the caller on the last CPU visited; an interrupted ARM run recorded a
class-384 page increase in `socketpair`. This did not establish its cause.
The next native probe refused a just-narrowed mask while migration was pending;
its associated incomplete run was also stopped. Both supervised attempts retain
their captures, unchanged input maps and `ECHILD` cleanup receipts. Neither is
qualified as a complete performance run.

The kernels remain the previously qualified production `ALLOC_TRACK=1`,
`LIMINE_MP=1`, seed-42 builds from isolated source
`cab44e91988c37aae1bab7af0fe7183dcd5ddd8a` plus the procfs builder fix. No kernel
allocation or lifetime code changes here. Both target payloads keep strict
format/pointer links with the verified sampler compiler
`53debcfe66952ba952d64b2b94dbb2408bed6992453d1ac6bad5889e4bd1ec7e`.
The complete host frontend remains `cbfc1be`, with tracked tree
`7a51d7a21849d86d09280dbc168f8fffe7c1dbca`. Generated C retains stack masks and
snapshot storage. Sampler/test sources are based on `b5be5f32c` plus the
captured warmup change. The host launcher's initial production compile refuses
inherited deprecated aliases; its normal build is used without changing those
unrelated modules or suppressing warnings.

The final validated payload's supervised attempt completed 15 of 40 cohorts.
It recorded a class-1536 backing-page increase of one in `socketpair`, with zero
object delta. The supervisor then refused an incomplete `du` observation after
a compiler scratch directory disappeared while an auxiliary tool was being
built inside a charged root. This was a test-execution mistake; `ECHILD`
cleanup and stable input maps are retained. All complete-workload checkers
correctly reject the incomplete capture. The 386 captured budget samples have
a maximum apparent charge of 2,793,868 KiB, minimum free space of 1,369,260 KiB
and maximum sample-start gap of 1.955 seconds. They do not qualify the failed
observation or complete workload.

Disk space briefly fell below admission, then recovered. Three fresh read-only
admission attempts still timed out. After the host suite finished, a direct
allocated-size scan took 4.392 seconds, exceeding the unchanged three-second
command bound; together with the other probes it also exceeds the five-second
observation window. The fixed six-scenario retry remains blocked by observer
timing. Tool builds for that retry were moved outside its charged roots. No
timeout, disk floor, working-state limit or flatness allowance is weakened.

The public suite passed again after the original `/tmp` heap state disappeared;
its complete replacement is preserved in the external control directory.
Both native architectures pass strict links and forced cross-CPU flatness,
restricted-mask and refusal/restoration checks. Focused native and warm-proof
consumers pass in normal and production builds. Broader section 15 acceptance,
the original four workload deltas and the inherited allocation-policy refusal
remain open. No full performance qualification is claimed.

The complete evidence root is `/Users/alex/.cache/vx-rw-1115-evidence`, archived
as `/Users/alex/.cache/vx-rw-1115-evidence.tar.gz` with SHA-256
`c6af982fb6f7b54195ea926eed5d6c7170515d8465c2e29e2ff36312d0f9bbb1`.
The unchanged archive-checker source, compiled in production mode and checked
with its corruption/sparse-hole selftests, passes the full named-root comparison
of logical bytes, paths, types, modes and link targets. All original roots remain
retained. The bundle contains strict build inputs/commands/generated C, native
ELFs and captures, frozen source closures, working-state samples, successful
host/focused controls, every refused attempt and the complete replacement public
heap state. `dependencies.json` pins and rechecks the preceding compiler,
instrumented-kernel and placement archives.

The final native serial hashes are
`cb8219e4db520d2fe4fe54340b7cf1d6e59de14bd76ac0bf9ce2643557a1b0f7`
(ARM) and `eb133a8ca39950fa2d0b911d73bc4d4fa2f6a1735a3c32f86c742dde0c99a78e`
(x86). Archive integrity does not turn the incomplete workload into a pass.
