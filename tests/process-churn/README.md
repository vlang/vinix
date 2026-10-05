# Settled operation cohorts and slabinfo sampler regression

This diagnostic separates repeated-operation leaks from delayed process
retirement, slab spare pages, and the allocations made by the sampler itself.
Use a separately built `ALLOC_TRACK=1` kernel. The guest warms each workload,
starts allocation tracking, then measures three cohorts of 300 runs (200
mkdir/rmdir pairs in directory mode). It waits
at least six seconds by `CLOCK_MONOTONIC`, retries interrupted sleeps, and
performs another fork/reap to drain the process quarantine before each sample.
Reading all of `/proc/slabinfo` records every available size class, including
the ARM medium classes. The 32-class capacity is checked rather than silently
discarding classes.

`PROCESS CHURN: DONE failures=0` means the workload and measurements completed.
It does not mean the kernel has no leaks. `check-results.py` requires all
cohorts, real grace periods, and untruncated live-allocation summaries. Its
optional slabinfo check rejects the measured 48-byte descriptor slope and
requires the final slab/big-page deltas to settle; it does not assert that
unrelated physical-memory use or every live class is flat.

## Run

The generic VM drivers come from this checkout; `--runner-root` supplies the
main checkout's untracked VM assets and userland cache. The kernel argument
must identify the exact measured tracked build.

```sh
# Tiny standalone regression guest, both architectures.
python3 tests/process-churn/run.py --mode slabinfo \
  --runner-root /path/to/main-checkout --kernel /path/to/arm-kernel \
  > /tmp/slabinfo-arm.log 2>&1
python3 tests/process-churn/run.py --mode slabinfo --arch amd64 \
  --runner-root /path/to/main-checkout --kernel /path/to/amd64-kernel/bin/vinix \
  > /tmp/slabinfo-amd64.log 2>&1
python3 tests/process-churn/check-results.py /tmp/slabinfo-arm.log \
  --mode slabinfo --expect-flat-slabinfo
python3 tests/process-churn/check-results.py /tmp/slabinfo-amd64.log \
  --mode slabinfo --expect-flat-slabinfo

# ARM exec cohorts need the populated desktop image and its matching module ISO.
python3 tests/process-churn/run.py --runner-root /path/to/main-checkout \
  --kernel /path/to/arm-kernel --image /path/to/initramfs-desktop.tar \
  --module-iso /path/to/initramfs-desktop.iso > /tmp/exec-cohorts.log 2>&1
python3 tests/process-churn/check-results.py /tmp/exec-cohorts.log
python3 tests/kernel-allocs/sites.py /path/to/arm-kernel/bin/vinix \
  < /tmp/exec-cohorts.log

# Generated-C check on each actual tracked build.
python3 tests/process-churn/check-generated.py /path/to/blob.c

# Standalone controls and operations. Also run these with --arch amd64.
# Allow the complete 900-fork x86 TCG workload to finish under host load.
for mode in waits pipes sampling; do
  python3 tests/process-churn/run.py --mode "$mode" \
    --runner-root /path/to/main-checkout --kernel /path/to/arm-kernel \
    --timeout 1800 \
    > "/tmp/churn-$mode.log" 2>&1
  python3 tests/process-churn/check-results.py "/tmp/churn-$mode.log" --mode "$mode"
done

# Directory cohorts require the ARM runner's actual persistent ext2 volume.
python3 tests/process-churn/run.py --mode directories \
  --runner-root /path/to/main-checkout --kernel /path/to/arm-kernel \
  > /tmp/churn-directories.log 2>&1
python3 tests/process-churn/check-results.py /tmp/churn-directories.log --mode directories

# Measured select/fork regression fixes. Repeat the guests with --arch amd64.
python3 tests/process-churn/run.py --mode select \
  --runner-root /path/to/main-checkout --kernel /path/to/arm-kernel \
  > /tmp/select-fixed.log 2>&1
python3 tests/process-churn/check-results.py /tmp/select-fixed.log \
  --mode select --expect-flat-small
python3 tests/process-churn/check-results.py /tmp/churn-waits.log \
  --mode waits --expect-flat-small
python3 tests/process-churn/check-generated.py /path/to/blob.c --operations
```

The slabinfo control uses three cohorts of 300 complete reads without execing
any external sampling programs. On x86, PID 1 redirects output to `/dev/com1`.
Exec mode uses the ARM desktop image's `true`, `sleep 0`, `curl --version`, and
BusyBox `awk BEGIN{}`. Preserve the kernel ELF beside each log so that allocation
return addresses can be named against the right build. `/proc/allocsites`
lists only call-chain groups with at least 50 objects; its live summary and
the complete slab-class deltas also matter.

## Measured sampler leak and ownership fix

On 2026-10-02, the saved combined kernel from `eff8f8a9` retained **602 additional
48-byte objects per 300 full slabinfo reads** on both ARM and x86. Named live
groups grew 604, 1206, 1808 objects at `fs__slabinfo_text`. Each complete read
formats the proc file twice, including the EOF read; the extra two descriptors
come from the end-of-cohort sample.

The generated C promoted the local `lib.Text` descriptor through `memdup`.
`Text.str()` already clones the returned bytes and frees its formatting buffer,
but the promoted descriptor had no owner. The fix gives that descriptor a
caller-stack slot, using the established `vinix_stack_alloc` pattern. The
returned owned string, the class snapshot array's free, and proc-file string
ownership are preserved. No process/VFS retirement rule or additional free
was introduced. The descriptor's synchronous use and returned-string lifetime
were independently reviewed before committing.

Tracked production builds from `164a7ae1` plus this fix pass the generated-C
check on both architectures. The check requires one caller-stack slot, no
`memdup` in `fs__slabinfo_text`, and the existing array/string ownership calls.
Both repeated-read guests have **zero size-48 object growth in all three
cohorts**, and no live call-chain group reaches 50 objects. Final slab and
big-page deltas are zero. ARM live counts remain 17; x86 counts are 13, 14,
15, including one residual size-16 object per timed cohort. That separate
small residual is not treated as proof of a per-read leak.

The result checker accepts both fixed logs and rejects the baseline's first
602-object increase. Corrupted logs with a short grace, missing DONE, or
duplicate measurement are also rejected.

## Exec findings and limits

The initial isolated exec run on the saved baseline had these used-memory
deltas in KiB for successive 300-run cohorts after actual 6.1-second grace:

| Program | Baseline cohorts | Fixed cohorts |
| --- | --- | --- |
| `true` | 80, 16, 0 | 64, 48, -16 |
| `sleep 0` | 16, 0, -16 | 0, 0, 0 |
| `curl --version` | 0, 16, 0 | 16, 0, 0 |
| `awk BEGIN{}` | 16, -16, 16 | 0, 0, 0 |

The fixed run reads every available class. `sleep`, `curl`, and `awk` finish
with unchanged live class counts in their final cohort and eight tracked live
allocations each. `true` finishes with 18, including small changes in several
classes rather than 300 retained objects at an exec call site. The baseline
also had only small live groups and included the sampler's two 48-byte
descriptors per cohort. These observations support bounded retirement/cache
effects in this workload; they do not establish that every process lifetime
is leak-free. No exec/process lifetime was changed from these totals alone.

The unchanged allocation allowance audit still fails 157 pre-existing
file/kind groups. The `fs/procfs.v` escaping-local count improves from five to
four; no failing category or allowance was added. The compiler reports 352
ARM and 245 x86 allocation sites for this candidate.

The ARM desktop run also completes `ops,churn,cache,idle,apps,drag` with all
43 required measurements, one DONE marker, no panic/error, and no reported
write after free. Idle/apps/drag desktop CPU samples are 0.27/0.67/9.86% of one
CPU; these single samples are validation evidence, not a performance claim.
The existing harness still reports pipe 169 B/op and mkdir 208 B/op on both
tmpfs and ext2. Its churn totals are 160/48/32/48 KiB, showing why totals from
one mixed-workload batch need the isolated, repeated, settled measurements
above before assigning a leak to exec. Those remaining operation lifetimes
are outside this formatter fix.

## Isolated waits, pipes, sampling, and directories

The added standalone modes use the saved sampler-fixed tracked kernels above,
without rebuilding or changing kernel lifetimes. `waits` measures a zero-operation
control, raw `nanosleep` and monotonic relative `clock_nanosleep` requests of one
millisecond, and fork/exit/reap without exec. Each workload has three cohorts of
300 operations. Sleep cohorts also report elapsed workload time; the checker
requires at least 300 ms for 300 successful one-millisecond sleeps. Fork cohorts
print progress every 25 reaps, since x86 TCG can take much longer than ARM HVF.

`pipes` creates an anonymous pipe, writes and checks one byte, and closes both
ends 300 times per cohort. `sampling` reads complete meminfo and slabinfo snapshots
300 times per cohort. These controls separate sampler/grace-period effects from
allocations that grow once per measured operation.

The ARM waits guest passes every cohort with intact allocation tracking.
`nanosleep` has zero live-class or slab growth in every cohort. Both
`clock_nanosleep` and fork/reap keep 11 tracked live objects in all three cohorts;
their first slab-page changes settle in later cohorts. The zero-operation control
keeps 17 live objects, despite used-memory deltas of 144, 0, 112 KiB. This shows
why a physical-memory total alone is insufficient to assign an operation leak.

Both pipe guests and both complete-snapshot controls also pass. ARM pipe live
counts stay 17, 17, 17, with slab deltas 64, 32, 0 KiB and no final big-page
change. ARM sampling live counts also stay 17. The x86 controls and both sleep
workloads retain one extra size-16 object per cohort, including the zero-operation
control; 300 operations do not produce 300 extra objects in that class. Pipe and
sampling live counts are 13, 14, 15 on x86. The later fork probe identifies this
cohort-level residual as the extra fork/reap used to drain quarantine, as detailed
below. No pipe, sleep, sampler, or retirement free was added from these totals.

`directories` measures three cohorts of 200 mkdir/rmdir pairs on each verified
filesystem: tmpfs magic `0x01021994` at `/tmp`, and ext2 magic `0xef53` at `/root`.
After each six-second grace it creates and unlinks one regular file to actively
drain due removed nodes; the same drain is present before the initial snapshot.
Both filesystems still retain **200, 400, 600 size-192 directory nodes and
200, 400, 600 size-16 names**, identified respectively at `fs.create_node` and
`string.clone` in the mkdir call chains. This is a confirmed **208 bytes per
removed directory**, matching the desktop harness, rather than a temporary
regular-file retirement backlog.

`kernel/fs/removed.v` deliberately excludes directories. Open file nodes still
borrow their parent directory; cwd/root and mount references also require careful
ownership. The measured directory slope needs a directory-reference and retirement
design with independent lifetime review before those nodes or names can be freed.
This diagnostic preserves the current rule and exposes the retained allocation.

The standalone evidence is saved as
`/tmp/vinix-process-churn-{waits,pipes,sampling}-{arm,amd64}.log` and
`/tmp/vinix-process-churn-directories-arm{,-sites}.log`. Incomplete x86 fork attempts
remain separate from successful cohort results; the checker rejects missing DONE
or missing measured cohorts.

## Measured select scratch and x86 fork ownership fixes

`select` keeps one byte ready in an anonymous pipe, alternates timed and untimed
calls, and measures libc `select` and raw `pselect6` separately for three cohorts
of 300 calls each. The saved baseline retains **300, 600, 900 size-16 objects**
at `file.do_select` for each selector on both architectures. Libc select uses
pselect6 on ARM; x86 exercises its native select entry as well.

Generated C shows the local timeout copy promoted through `memdup`, despite the
source's `unsafe { &remaining }`. Giving the 16-byte copy a once-per-invocation
caller-stack slot removes that allocation. `ppoll` consumes the pointer
synchronously and copies the duration into an owned timer when it blocks; no
pointer to this slot escapes the call. The existing poll/index array ownership
stays intact. An independent review confirmed the lifetime before committing.

Both fixed select guests complete all six measured cohorts, including invalid
fd-set, timeout, outer-mask and inner-mask pointers returning EFAULT; incorrect
mask size returning EINVAL; successful mask restoration; a real ten-millisecond
timeout; a queued SIGUSR1 interrupt returning EINTR and restoring the old mask;
and delayed pipe readiness after another process writes. ARM select live counts
stay 17 and pselect counts stay 11; both x86 selectors stay 11, 11, 11. The first
ARM select cohort includes two startup size-16 objects seen in the idle control;
all later ARM cohorts and every x86 cohort have zero size-16 object growth.

The x86 fork probe separately names its retained size-16 group at
`string.clone <- sched.new_process <- userland.clone_new_process <- syscall_fork`.
Its three complete 300-run cohorts retain 301, 602, 903 strings: the 300 measured
forks and one extra drain fork per cohort. This explains the controls' original
one-object growth even when their measured workload performs no fork.
`sched.new_process` establishes one owned inherited executable path, but the
x86 clone caller cloned and overwrote it again. Removing that second clone
preserves the existing owner, which exec or process cleanup later releases; no
new free was introduced.

The new waits guest checks that a forked child inherits the parent's
`/proc/self/exe` path. The fixed ARM run passes this assertion and all twelve
workload cohorts; fork/reap remains at 11 tracked live allocations in each of
its three 300-run cohorts, with zero size-16 growth and no final slab/big-page
change. The fixed x86 run also completes all twelve cohorts, including all 900
measured forks, and passes the inheritance check. Its fork live counts stay
11, 11, 11 with every object class flat. The slab deltas are +4, -4, +4 KiB:
one spare size-384 slab page remains, with zero object growth and no big-page
change. Both sleep workloads and the zero-operation control also have zero
size-16 growth on the fixed x86 kernel. These measurements remove the original
301-objects-per-cohort fork slope without treating spare pages or unrelated
physical-memory fluctuations as leaked operation objects.

`--expect-flat-small` checks the reproduced size-16 operation class and requires
the lifetime/ABI semantic marker. It allows the idle control's two startup
objects in the first cohort and requires zero positive growth afterwards; it
does not assert that every physical-memory total or unrelated allocation is
flat. `check-generated.py --operations` requires one stack slot and no memdup
in the actual `do_select` C, preserves poll/index frees, and checks exactly one
inherited executable-path clone with no clone-caller overwrite on either
architecture.

Both tracked production builds pass. The unchanged allocation audit reports
351 ARM and 245 x86 sites (compiler exit 0/1), with 156 pre-existing failing
file/kind categories versus 157 before these fixes. Only the pselect escaping
local category disappears; no allowance, failing category, or failing count
was added. The audit's known x86 scratch-copy compilation failure remains
distinct from the successful x86 production build.

Logs are `/tmp/vinix-process-churn-select-{arm,amd64}-{baseline,fixed}.log`,
`/tmp/vinix-process-churn-select-{arm,amd64}-build.log`,
`/tmp/vinix-process-churn-waits-{arm,amd64}-fixed.log`,
`/tmp/vinix-process-churn-waits-amd64-fixed-sites.log`,
`/tmp/vinix-process-churn-waits-amd64-final.log`, and
`/tmp/vinix-process-churn-operation-alloc-audit.log`. Both fixed ELFs and generated
C, the exact two-file kernel patch, and hashes are saved under
`/tmp/vinix-process-churn-artifacts/operation-fixes/`. The root integration run
validates the final combined kernel's core and desktop workloads separately.

The validation logs are `/tmp/vinix-process-churn-{arm,amd64}-build.log`,
`/tmp/vinix-process-churn-slabinfo-{arm,amd64}-{baseline,fixed}.log`,
`/tmp/vinix-process-churn-arm-{baseline,fixed}.log`,
`/tmp/vinix-process-churn-alloc-audit.log`, and
`/tmp/vinix-process-churn-desktop.{log,json}`. The matching fixed ELFs and
generated C are saved under `/tmp/vinix-process-churn-artifacts/`.
