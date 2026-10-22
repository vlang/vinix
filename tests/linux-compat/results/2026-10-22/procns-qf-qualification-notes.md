# Q2 queue-drain qualification notes

Exact isolated source: bd9aa1bc1d04eac1ce31e02ce8914969294566ff. The ARM measurements use its allocation-tracking kernel. Both production and tracking profiles build on both architectures. Their complete kernel and generated-C hashes are recorded in queue-candidate-inputs.json. All four final kernel binaries and generated-C files are byte-identical to Q1; Q2 adds only the verified-freed annotation to the existing partial-drain allocation.

The full-drain fix moves the detached queue buffer under the queue lock, resets the global header, and frees that buffer after callbacks. Independent root review and generated-C checks cover the ownership transfer. Existing timed-reader and permanent mount-pin limits remain; this is not a quiescence-based RCU proof.

The first Q1 allocation comparison rejected a newly unattributed partial-drain array assignment. Its raw inventory failures and complete historical build records remain under queue-fix/q1-ec5631d664a8 and are pinned by archive.sha256. The final Q2 inventories both exit1 for the unchanged 178 inherited excess groups; their comparison exits0 with identical per-file/kind counts and no new allocation group. The initial readiness helper also failed on a private status filename mismatch; q2-ready-initial.log/status preserve that host-only failure.

The ARM performance driver, both frozen module copies, existing measure source, selected cached desktop, 710437376-byte raw initramfs, firmware, exact kernel, V compiler and host launch dependencies are pinned before the guests run in qf2-perf-inputs.sha256 and verified again afterwards. The original qf-perf-inputs.sha256 is the earlier Q1 preparation manifest and remains historical. The cached image setup uses the existing private od/install compatibility substitutions. Automatic shared-checkout pruning is disabled. Each group runs in a separate process and distinct workfolder/QMP socket; the short desktop groups overlap the intentional grace waits in the ops guest.

The strict raw-result auditor requires 36 unique 200-cycle operation cohorts, every bytes_per_op=0 with no class deltas; four expected 300-execution churn cohorts with zero retained bytes and no PERF-SLAB rows; exactly one bounded 32MiB cache result; and exact five-second idle/apps/drag raw/JSON equality, expected native app processes, one START/DONE pair, and no PERF-ERROR or panic. It also requires the native ARM ext2 /root mount marker, so the persistent filesystem operations cannot silently run on tmpfs. Two negative controls must reject disabled assertions and a substituted desktop log.

The cache bounds were declared before completion: used_mb 0..64, cached_kb 0..65536 and at most1MiB skew between separate slab probes. Cache retention is reported separately from zero-leak operation and churn results.

Observed final raw rows:

```text
qf-perf-compat-ops
PERF-CHURN variant=new scenario=churn round=1 program="/bin/true" runs=300 retained_kb=0 per_run_bytes=0
PERF-CHURN variant=new scenario=churn round=1 program="/bin/sleep 0" runs=300 retained_kb=0 per_run_bytes=0
PERF-CHURN variant=new scenario=churn round=1 program="/usr/bin/curl --version" runs=300 retained_kb=0 per_run_bytes=0
PERF-CHURN variant=new scenario=churn round=1 program="/bin/busybox awk BEGIN{}" runs=300 retained_kb=0 per_run_bytes=0
PERF-CACHE variant=new scenario=cache round=1 written_mb=32 used_mb=20 cached_kb=16384 slab_kb=36672
PERF-MEMINFO variant=new scenario=cache round=1 MemTotal:       11756352 kB
PERF-MEMINFO variant=new scenario=cache round=1 MemFree:        11585056 kB
PERF-MEMINFO variant=new scenario=cache round=1 MemAvailable:   11585056 kB
PERF-MEMINFO variant=new scenario=cache round=1 Buffers:               0 kB
PERF-MEMINFO variant=new scenario=cache round=1 Cached:         16384 kB
PERF-MEMINFO variant=new scenario=cache round=1 SwapTotal:      0 kB
PERF-MEMINFO variant=new scenario=cache round=1 SwapFree:       0 kB
PERF-MEMINFO variant=new scenario=cache round=1 Zswap:          0 kB
PERF-MEMINFO variant=new scenario=cache round=1 Zswapped:       0 kB
PERF-MEMINFO variant=new scenario=cache round=1 VinixPageouts:  0
PERF-MEMINFO variant=new scenario=cache round=1 VinixRefaults:  0
PERF-MEMINFO variant=new scenario=cache round=1 VinixSwapErrors: 0
PERF-MEMINFO variant=new scenario=cache round=1 Slab:           36704 kB
PERF-MEMINFO variant=new scenario=cache round=1 VinixMemoryPressure: 0
PERF-MEMINFO variant=new scenario=cache round=1 # class      size    objects   pages
PERF-MEMINFO variant=new scenario=cache round=1 size-16 16 14201 19
PERF-MEMINFO variant=new scenario=cache round=1 size-32 32 3465 12
PERF-MEMINFO variant=new scenario=cache round=1 size-48 48 230 6
PERF-MEMINFO variant=new scenario=cache round=1 size-64 64 1206 10
PERF-MEMINFO variant=new scenario=cache round=1 size-96 96 4144 32
PERF-MEMINFO variant=new scenario=cache round=1 size-128 128 77 4
PERF-MEMINFO variant=new scenario=cache round=1 size-192 192 3425 47
PERF-MEMINFO variant=new scenario=cache round=1 size-256 256 9378 155
PERF-MEMINFO variant=new scenario=cache round=1 size-384 384 7114 176
PERF-MEMINFO variant=new scenario=cache round=1 size-512 512 6901 229
PERF-MEMINFO variant=new scenario=cache round=1 size-768 768 74 10
PERF-MEMINFO variant=new scenario=cache round=1 size-1024 1024 16 5
PERF-MEMINFO variant=new scenario=cache round=1 size-1536 1536 37 9
PERF-MEMINFO variant=new scenario=cache round=1 size-2048 2048 7 5
PERF-MEMINFO variant=new scenario=cache round=1 size-2688 2688 0 0
PERF-MEMINFO variant=new scenario=cache round=1 size-4048 4048 0 0
PERF-MEMINFO variant=new scenario=cache round=1 size-5392 5392 4096 1369
PERF-MEMINFO variant=new scenario=cache round=1 size-8096 8096 0 0
PERF-MEMINFO variant=new scenario=cache round=1 large - - 206
PERF-MEMINFO variant=new scenario=cache round=1 # written after free 0
qf-perf-compat-desktop
PERF-RESULT variant=new scenario=idle round=1 seconds=5.0 processes=4 desktop_cpu=0.14 apps_cpu=0.19 total_cpu=0.33 desktop_mb=40.1 apps_mb=40.6 total_mb=80.8 system_used_mb=293.9 physical_mb=127.1
PERF-RESULT variant=new scenario=apps round=1 seconds=5.0 processes=9 desktop_cpu=0.47 apps_cpu=0.37 total_cpu=0.84 desktop_mb=43.8 apps_mb=134.0 total_mb=177.8 system_used_mb=437.9 physical_mb=245.4
PERF-RESULT variant=new scenario=drag round=1 seconds=5.0 processes=9 desktop_cpu=1.58 apps_cpu=0.46 total_cpu=2.04 desktop_mb=43.9 apps_mb=134.0 total_mb=177.9 system_used_mb=428.6 physical_mb=235.7
qf-perf-drag-desktop
PERF-RESULT variant=new scenario=drag round=1 seconds=5.0 processes=4 desktop_cpu=2.53 apps_cpu=0.23 total_cpu=2.76 desktop_mb=40.2 apps_mb=40.6 total_mb=80.8 system_used_mb=293.8 physical_mb=127.0
```

An additional fresh drag-only guest has its own strict raw/JSON/marker/full-PPM audit and complete before/after screenshots. Visual review confirms the System window moving from the upper center to the lower left, with Frames6→245. These are one-round functional and bounded-retention checks using cached desktop images and five-second desktop measurements. They do not establish release performance or a long-term soak. The x86 results and native retention cohorts have separate authoritative summaries, audits, receipts and input pins, linked from qf-validation-summary.json.
