# Preserved v3 validation

These completed checks used the preceding v3 kernel/libc artifacts. Any “final” label below refers to v3, not the v4 campaign. The complete v3 timing repeat failed five of the six performance targets; [its report](final-v3-versus-catalina2/README.md) preserves that result.

## Allocator and packaging verification

Vinix's default musl keeps a bounded working set of ordinary allocation groups
and free direct mappings. Its five direct-cache buckets total at most
3,968 KiB. The conservative additional backing envelope is below 16 MiB,
including nested ordinary groups; live allocations and musl's existing
fragmentation policy are outside that additional-retention bound. Full groups
still consolidate, `calloc` clears reused mappings, and `malloc_trim` returns
free storage while preserving live objects and `errno`. Mallocng assertions
use a defined compiler trap so GCC preserves unused-result redzone checks.
The final build logs confirm `-O3` for both static and shared mallocng objects.

The [x86 evidence](../validation/allocator-x86-v3/results.json) records four
actual guest variants: retained and retention-disabled libc, each dynamically
and statically linked. Each passed 1,910 checks with native guest GCC 14.2.0.
Double frees produced SIGSEGV and nominal-size overruns produced SIGILL.
Every variant returned to its warmed mapping baseline after trimming.

The [ARM evidence](../validation/allocator-arm-v3/summary.json) records the same
four correctness variants under QEMU HVF, separately from the x86 performance
comparison. Each passed 1,910 checks and trimming returned to baseline.
Double frees produced SIGSEGV; the compiler's ARM `BRK` trap produced SIGTRAP
for both redzone overwrites. The preserved probe proves those traps before
the verifier's ARM-only SIGTRAP acceptance was added. A normal child exit
still fails corruption verification. The x86 four-mode evidence retains its
exact earlier verifier source; the subsequent ARM-only amendment preserves
the x86 rejection rules.
Together, the eight allocator variants passed 15,280 checks.

[Production packaging evidence](../validation/production-packaging-v3) records
actual executions of both root userland builders using private output trees
and cached inputs. Both Alpine 3.21 base images select the pinned musl 1.2.5
recipe. The packaged loader, static archive, malloc header and libc links were
checked against their final manifests and initramfs contents. The separate
ARM runtime correctness image uses the compatible pinned 1.2.6 recipe.
Desktop hooks also restore the optimized loader after package overlays and
update the static desktop sysroots.

## Kernel regression and lifetime verification

The [complete x86 core run](../validation/core-x86_64-final/run.json) passed on
two vCPUs with 52 feature completion markers, including mapping and empty-pipe
reclamation, concurrent first writes, socket behavior and the unchanged
65,536-call recvmsg memory assertion. Its source, runner and raw transcript
are preserved alongside the manifest. The
[final ARM core run](../validation/core-aarch64-final/run.json) also passed on
two vCPUs, with 50 feature markers and a successful second boot verifying
persistent storage. It uses the identical test source and optimized static
musl 1.2.6. A separate preboot launch diagnostic preserves the initial copied
executable mode error before the successful run.

The [final desktop harness](../validation/desktop-perf-final/run.json) completed
one round of all six required scenarios: ops, churn, cache, idle, apps and
drag. All 43 result rows, the complete transcript, QEMU arguments and frozen
workload sources are preserved. The new static desktop links the verified
optimized libc; the private harness also overlays the final loader. Idle,
apps and drag complete their 20-second observations, with total CPU readings
of 0.26%, 0.75% and 4.94% respectively.

This harness completion verifies the scenario execution and preserves memory
diagnostics; its ops and churn measurements still show growth. Examples are
1,217 bytes per pipe operation and 6,728 bytes per `/proc` read in the
200-operation batches. The 300-run churn batches report 1,966 bytes per
`true`, 1,583 bytes per `sleep 0` or `awk`, and 21,408 bytes per `curl --version`.
The cache scenario records 16 MiB cached after writing 32 MiB. These
[unfiltered diagnostics](../validation/desktop-perf-final/results.json) remain
separate from the matched x86 allocation timing comparison. The one-round
capture does not establish leak-free kernel behavior or native desktop
performance.

The same frozen V compiler made the measured baseline retain 43,155,456 bytes
after 65,536 empty recvmsg calls, adding one 128-byte and one 512-byte live
object per call. The [baseline probe](../validation/socket-arm-baseline/run.json)
preserves its failure and complete slab snapshots. Explicit caller-stack
scratch storage removes those hidden allocations; the final
[ARM probe](../validation/socket-arm-final/validation.json) completed the same
65,536 calls with zero retained bytes. The host collector encountered a
process cleanup error after guest completion. That error, the raw transcripts
and independent footer/memory validation are recorded separately from the
guest's successful result.

The [independent lifetime review](../validation/socket-lifetime-final/review.json)
checks all 15 caller-stack buffers/headers and both queued FD ownership
transfers. Socket families finish copying before the caller's frame ends,
including blocking calls. The queue owns one metadata allocation until
delivery, truncation, ordinary read or close. The saved generated C confirms
that the six transfer functions contain no scratch-buffer `memdup`, and both
queue insertions transfer their array metadata without a deep clone.
The [committed source fingerprints](../validation/socket-operations-final/commit-provenance.json)
confirm that commit `c9c8ce01` contains the exact two reviewed socket files.

The [extended ARM comparison](../validation/socket-operations-final/comparison.json)
runs the identical probe source against the frozen baseline and final kernel.
All 11 batches numbered 0–10 retain zero bytes after 8,192 calls each,
including small and large messages, stream/datagram/seqpacket descriptor
delivery, and control truncation. The 48-byte queued descriptor metadata
class stays flat across every tested delivery and cleanup path. Both kernels
reject the probe's final `MSG_PEEK` case with `EOPNOTSUPP` (errno 95), preserving
an existing unsupported operation.

Broader plain-read and repeated socket creation/close paths still retain
memory. The [settlement comparison](../validation/socket-operations-final/settlement-comparison.json)
checks five batches after an additional one-second wait; both kernels finish
all five functional checks. The baseline retains at least as much memory in
each case. The remaining growth is preserved as a limitation of these
broader existing paths, so these results do not establish that every kernel
allocation class stays flat.

| After 8,192 calls and one second | Baseline retained bytes | Final retained bytes |
| --- | ---: | ---: |
| Stream read discarding rights | 11,173,888 | 4,325,376 |
| Datagram read discarding rights | 11,190,272 | 4,341,760 |
| Stream close with queued rights | 41,680,896 | 34,816,000 |
| Datagram close with queued rights | 41,664,512 | 34,799,616 |
| Send to a closed stream | 39,174,144 | 33,243,136 |

Every baseline and final snapshot keeps the written-after-free counter at 1.
The [heap self-test](../validation/socket-operations-final/heap_selftest.v)
deliberately increments that counter once while verifying freed-slot poison
detection. None of these socket batches increases it.

The [final allocation audit](../validation/allocation-audit-final/comparison.json)
reduces reported sites from 443 to 432, removing the 11 socket locals whose
addresses escaped, and adds no reported sites. The literal repository
allowlist still fails in both baseline and final audits. Both raw logs also
retain the same incomplete x86 audit caused by the audit's extracted source
list: the [full diagnostic](../validation/allocation-audit-final/x86-diagnostic.json)
records missing `drm.simple` imports and mapping resource interface errors.
The actual full x86 kernel builds and core suite pass. The ARM audit
invocations finish successfully, with 385 baseline and 374 final reported
sites. These audits are preserved as a comparison
with existing limitations, rather than reported as passing repository checks.

Four-vCPU validation has an existing 80-waiter thread-creation limitation:
the [exact baseline](../validation/waiters-baseline-4cpu/run.json) stopped while
creating worker 70, and the
[earlier VM/pipe candidate](../validation/waiters-candidate-4cpu/run.json) stopped
at worker 69 with the identical test source. Both diagnostic transcripts and
their failure records are preserved. The complete final x86 suite passed on
two vCPUs; broader SMP stability remains unverified by these runs.
