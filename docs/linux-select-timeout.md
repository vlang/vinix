# Native select remaining timeout

Raw pselect6 and x86-64 select now return the remaining timeout after
readiness, expiry, handled-signal interruption and core count/bitmap/descriptor
errors. The deadline starts when the valid timeout is imported. Seconds and
nanoseconds stay separate, with saturated addition, and raw select truncates
the remainder to microseconds. Invalid timeout/mask arguments return before
writeback; absent and zero timeouts skip it. A read-only timeout preserves the
completed call's result and errno. Libc pselect preserves its const input.
These rules follow [Linux v6.12 fs/select.c](https://github.com/torvalds/linux/blob/v6.12/fs/select.c)
and its [safe timespec addition](https://github.com/torvalds/linux/blob/v6.12/kernel/time/time.c#L790).

## Qualification

Original and fixed isolated production kernels use source revision
`4c41d45abd3de4e81b7778ec9c8335adbb79ddbb` and the retained pselect.v patch,
V 0.5.2 `7d74206`, `PROD=true LIMINE_MP=1 ALLOC_TRACK=0` and link seed 42.
Their input maps differ only in pselect.v. The identical static musl probe
ELF for each architecture runs on its original kernel, fixed kernel and
Linux 6.12.51 reference.

| Architecture | Checks | Original failures | Fixed failures | Linux failures |
| --- | ---: | ---: | ---: | ---: |
| AArch64 | 1,536 | 24 | 0 | 0 |
| x86-64 | 2,208 | 46 | 0 | 0 |

Original failures are exactly the raw writable nonzero timeout checks.
The strict parser passes six positive and 2,364 negative controls, requiring
every semantic row and complete storage cohorts/class layouts.

The matrix runs as root and UID1000/GID2000. It exercises raw pselect6,
libc pselect and raw x86-64 select with writable/read-only timeout pages:
empty and nonempty expiry; queued socket readiness; EBADF, EINVAL and EFAULT;
invalid timeout and mask controls; zero and absent timeouts; and maximum
signed64 seconds with canonical subseconds. Descriptor 1023 stays open to
align Linux/Vinix table capacity. All three full guarded fd sets, timeout and
mask-pack guards, restored masks and unchanged socket data are checked.

Handled-signal cases cover empty and nonempty waits with SA_RESTART enabled
and disabled. An observer must see the calling thread sleeping through
`/proc/self/task/TID/stat` before sending the signal. Pending-signal pselect
cases test atomic temporary unmasking. The handler checks that writeback is
already visible, and its effective mask is correct; the caller checks EINTR
and mask restoration. Time bounds use monotonic samples surrounding the
syscall, with allowance only for raw select's sub-microsecond truncation.

Each native credential cohort warms 64 cycles, then measures 200 complete
cycles of expiry, readiness, argument errors, read-only inputs, maximum
durations and pending-signal pselect calls. Observer threads are excluded from
this storage loop. All slab classes, large-page counts and allocator taint
must remain flat. Reference runs explicitly skip Vinix storage measurements.
Original/fixed large-page counts are 89/89 on AArch64 and 222/222 on x86-64
in both credential cohorts, with taint 0/0 and every live slab class flat.

The generated-C audit limits changes to the two entrypoints, private select
helper and three timeout helpers/declarations. It requires unchanged heap
allocation, cleanup, timer and poll call counts, one added explicit stack slot
for synchronous usercopy, deadline/writeback order, zero/null guards and
microsecond truncation. New stack storage is never retained by usercopy or
ppoll. Signal state stays in the child entry frame until worker joins and
`_exit`.
Independent lifetime review passes for both architecture outputs. The C audit
passes two positive and eighteen scoped mutation controls. Both full
allocation scans report the same 391 AArch64 / 291 x86-64 sites and 180
pre-existing excess groups against allowed.txt; this patch adds none. The
global allocation gate remains open.

Fresh registered selecttimeout, selectorder, selectempty, maskwait and
selectfds cases pass on both fixed kernels. Existing strict wait/descriptor
parsers remain unchanged. Each case compiles its frozen fixture sources;
retained probe binaries do not substitute for registered builds.

## Evidence and reproduction

Run `tests/linux-compat/run.v --cases selecttimeout` with an isolated kernel
and fresh external state directory. The registered case freezes both fixture
sources and has a 300-second default budget. `selecttimeout-reference.v`
accepts `--arch`, `--kernel`, `--init`, `--launcher` and `--state-dir` to boot
the identical native probe ELF on Linux. Build `selecttimeout-evidence.v`
without `-prod`, using `-cc cc -cflags -O2`; its modes are `self-test`,
`generated BEFORE-C AFTER-C` and `BUNDLE`.

The complete external bundle is `/Users/alex/.cache/vx-st-1114/bundle`.
It retains original/fixed kernels, generated C, build/compiler input/output
pins and commands, source snapshots/archive, Linux kernels/initramfs, native
images/firmware, serial output, registered receipts, allocation scans and
review. Its 587-file manifest has SHA-256
`cadc55ab490c283cf7d6f8929994508887a2544c9794510447839595ba897769`.
The complete evidence audit passes, including every retained artifact hash.

## Remaining scope

This qualifies native 64-bit default-personality timeout behavior for the
listed profiles. Timeval normalization, STICKY_TIMEOUTS personalities, partial
page-crossing copies, pointer aliasing/concurrent mutation, signal/error
races, GNU wrappers, foreign/32-bit ABIs, ppoll timeout writeback and timer
slack accuracy remain separate. Broader §15 semantics, application
installation/integration and translated-runtime gates remain open.
