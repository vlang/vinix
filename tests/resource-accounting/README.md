# Resource accounting regressions

The guest exercises Linux LP64 `getrusage`, `wait4` and `/proc/self/stat`
against a disposable, physically backed EXT2 root. Its assertions compare
observable behavior across operations rather than assuming exact scheduler
or filesystem metadata counts.

The checks cover:

- Touching 32 MiB of anonymous pages raises current RSS and minor faults.
  The allocator reserves at least 64 MiB to enter Vinix's demand-paging path,
  then unmaps its untouched tail; smaller mappings are eagerly filled.
  The guest warms its allocation and `/proc` parsing helpers first so lazy
  faults in the EXT2 executable are outside that measurement.
  `PROT_NONE` preserves resident pages and restoring permissions preserves
  their data. Unmapping reduces current RSS while retaining the peak.
- A fork child counts inherited resident pages, starts with fresh event
  counters, and does not inherit its parent's historical RSS peak after
  those pages have been unmapped.
- Writing and synchronizing EXT2 data produces completed disk-write blocks.
  A cold positional read produces disk-read blocks; 100 repeated cache hits
  produce no more. A cold private mapping produces major faults and disk
  reads; refaulting warm mapped data produces minor faults without disk I/O.
- Four workers report their own anonymous faults and sleeping switches.
  Repeated 20 ms sleeps must cause switches, without assuming every sleep
  call switches away before its deadline expires.
  Process totals include their work after they exit. Two busy tasks pinned
  to one CPU require timer preemption and involuntary switches.
- `wait4` reports faults, I/O, switches and peak RSS. Reaped child and
  grandchild event totals accumulate, while RSS uses the largest peak.
  Child I/O uses fresh files that have never been mapped; cache discard is
  a best-effort hint and recently unmapped pages can remain pinned.
  `/proc` child-fault fields agree with `RUSAGE_CHILDREN`.
- Executing a replacement program retains process RSS history and both
  process and calling-thread event/CPU histories.
- Invalid selectors and output pointers fail. A failed `wait4` output copy
  preserves the wait event for a subsequent successful call.
- A warmed loop of 3,000 accounting syscalls and 1,000 proc reads checks
  retained slab memory, with 16 KiB allowed for bounded cache variation.

Build the isolated kernel for the selected architecture, then run:

```sh
VINIX_VM_RUNNER_ROOT=/path/to/main \
VINIX_KERNEL_DIR=/path/to/worktree/kernel \
VINIX_AARCH64_SYSROOT=/path/to/main/build-aarch64-userland/sysroot \
VINIX_QEMU_RT_NO_BUILD=1 VINIX_QEMU_AUDIO=off \
  python3 tests/resource-accounting/run.py --arch=aarch64

VINIX_VM_RUNNER_ROOT=/path/to/main \
VINIX_AMD64_KERNEL=/path/to/worktree/build-amd64-kernel/bin/vinix \
  python3 tests/resource-accounting/run.py --arch=amd64
```

The runner cross-compiles the test with warnings treated as errors and
threads enabled. It boots a temporary EXT2 image, requires the final pass
marker and checks the stopped image with `e2fsck -f -n`. The x86 guest
redirects its output to `/dev/com1` using `O_NOCTTY`.

`--retention-only` compiles the same warmed query loop while skipping new
field semantics, pointer-policy checks and file creation. It can compare
an older kernel's retained memory with the candidate using identical work.

Accounting stores scalar totals in existing task/address-space objects;
there is no allocation per recorded event. Fork creates fresh counters,
shared address spaces count each mapped leaf once, private COW replacement
does not increase RSS, and shadow/kernel page maps are excluded. Each
successful instrumented VirtIO, AHCI or NVMe leaf transfer contributes
completed payload bytes,
with `ru_inblock`/`ru_oublock` expressed in 512-byte blocks. Cache hits and
partition forwarding do not charge those bytes again.

Background writeback belongs to the kernel thread issuing its device I/O.
This does not implement Linux's attribution of delayed writes to the task
that originally dirtied a page. Fault counts represent successful
resolution/COW transactions; a concurrently resolved fault can finish
without installing another physical page. Swap and the Linux-unused
`rusage` fields remain zero. Apple ANS and native C filesystem I/O paths
remain uninstrumented. The NVMe hook compiles on both architectures but
has no hardware I/O guest coverage; the exercised device paths are VirtIO
and AHCI.

ABI behavior follows the Linux kernel's
[resource snapshot implementation](https://github.com/torvalds/linux/blob/master/kernel/sys.c),
[I/O block conversion](https://github.com/torvalds/linux/blob/master/include/linux/task_io_accounting_ops.h)
and [scheduler switch classification](https://github.com/torvalds/linux/blob/master/kernel/sched/core.c).

## Measured validation

On 2026-10-02, the final allocation-tracked kernels passed the complete
physical EXT2 guest and the subsequent image consistency check:

| Measurement | AArch64, VirtIO | AMD64, AHCI |
| --- | ---: | ---: |
| Native page size | 16 KiB | 4 KiB |
| Minor faults from touching 32 MiB | 2,048 | 8,192 |
| Additional major faults during that anonymous touch | 0 | 0 |
| Observed process RSS peak | 41,136 KiB | 41,024 KiB |
| Cold file-mapping major faults | 32 | 128 |
| Warm file-mapping minor faults | 128 | 512 |
| Worker minor faults, summed | 2,048 | 8,192 |
| Worker voluntary switches, summed | 48 | 48 |
| Observed busy-task involuntary switches | 25 | 56 |
| Read/write blocks in each fresh child's measured I/O | 32 / 40 | 32 / 40 |
| Slab before/after the 4,000-query loop | 4,512 / 4,512 KiB | 1,220 / 1,220 KiB |

Fork residency, `PROT_NONE`, unmapping and retained RSS peaks, fresh child
counters, exact descendant totals, maximum child RSS, process/thread
histories across exec, invalid arguments and failed-copy wait retries all
passed. Scheduler numbers are observations, not fixed required counts.

An older tracked AArch64 `kernel-stacks` kernel also passed the identical
retention-only loop with Slab at 1,200 / 1,200 KiB. The explicit ABI stack
record preserves measured bounded scratch behavior; these measurements do
not establish a pre-existing query leak. Generated C for both candidates
showed no heap calls in the accounting helpers, `getrusage` or the child
rusage-copy helper; the two ABI-copy paths each use one stack record.

The saved local logs are `/tmp/vinix-resource-accounting-arm64-guest.log`,
`/tmp/vinix-resource-accounting-amd64-guest.log` and
`/tmp/vinix-resource-accounting-arm-baseline-guest.log`.
