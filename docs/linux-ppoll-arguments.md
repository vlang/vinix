# Native ppoll argument validation

Raw ppoll now decodes nfds as unsigned32, validates its timeout first, then
validates/imports the signal mask before checking the descriptor count and
poll array. A non-NULL mask requires the full native size argument to equal
eight bytes; a NULL mask ignores that size. The temporary mask is installed
before core errors and restored on syscall exit. The internal wait receives
no additional mask, so installation happens once.

This follows the native entrypoint layering in
[Linux v6.12 fs/select.c](https://github.com/torvalds/linux/blob/v6.12/fs/select.c#L1031).
Previously, an invalid count or poll array could hide timeout/mask errors,
mask sizes were ignored, and high count-register bits could cause EINVAL even
when the low unsigned32 count was zero or one.

## Qualification

Original and fixed production kernels are built in isolated worktrees from
`9fe8e86079f056dcf3ff0b39d6969016bd4df1cf` plus the retained file.v patch,
using V 0.5.2 `7d74206`, `PROD=true LIMINE_MP=1 ALLOC_TRACK=0` and link seed 42.
Their input maps differ only in file.v. Each architecture runs the identical
static musl probe ELF on original/fixed Vinix and Linux 6.12.51:

| Architecture | Checks | Original failures | Fixed failures | Linux failures |
| --- | ---: | ---: | ---: | ---: |
| AArch64 | 19,600 | 1,004 | 0 | 0 |
| x86-64 | 19,600 | 1,004 | 0 | 0 |

Root and UID1000/GID2000 cross seven count-register profiles with eight mask
profiles, five timeout profiles and five poll-buffer/descriptor profiles.
Counts include zero, one, unsigned32 maximum and distinct high words with
low zero/one. Masks include NULL with ignored sizes, valid masks, wrong
zero/large sizes, inaccessible masks, and `0x100000008` to distinguish
size_t from unsigned32. Timeout controls are zero, inaccessible, negative
seconds/nanoseconds and out-of-range nanoseconds. Descriptor controls are
ignored negative slots, queued UNIX sockets, closed slots, inaccessible arrays
and read-only poll output.

Each call checks return value/errno, the complete guarded pollfd, timeout,
mask argument/value guards, restored mask and unchanged queued socket data.
Zero-count cases verify that inaccessible/read-only poll pointers are ignored.
The strict parser requires every semantic row, and analytically pins the
original return/errno/output differences from its earlier validation order.
It passes six positive and 1,696 negative controls.

Each native credential cohort warms 64 full matrix cycles and measures 200
cycles, requiring flat live slab classes, large pages and allocator taint.
Linux reference runs explicitly skip Vinix storage checks.
Both AArch64 original cohorts keep large pages at 85/85, and both fixed
cohorts at 83/83. Both x86-64 kernels keep 222/222. Every live slab class
stays flat and taint stays 0/0.

Generated-C changes are limited to the ppoll entrypoint and its declaration.
The two explicit stack slots, one poll-array allocation and scratch reservation
are retained. Invalid timeout/mask/count returns precede reservation; after
reservation, array cleanup and budget release cover import failure and all wait
returns. Neither stack slot is retained by the saved mask, which copies the
mask value. The new fixture guards are synchronous stack storage; each child's
poll-buffer mapping remains live through its final `_exit`.
Independent lifetime/ABI review passes, including saved-mask restoration on
early EINVAL/EFAULT/ENOMEM exits and unchanged EINTR handling. Generated-C
controls pass two positives and eighteen scoped mutations. Full allocation
scans retain 391 AArch64 / 291 x86-64 sites and the same 180 pre-existing
excess groups against allowed.txt. The global allocation gate remains open.

Fresh registered ppollargs, maskwait and selectfds pass on both fixed kernels.
Selecttimeout passes on AArch64 but refuses two x86-64 raw-select negative-count
calls because their 500,000-microsecond timeout remains unchanged; its strict
oracle requires a decrease. The exact failed ELF replay passes on the original
kernel and refuses one call on the fixed kernel. An identical numeric-diagnostic
ELF, preserving every original check, refuses one call on each kernel and records
`original=0/500000 actual=0/500000`. All runs and refusals are retained. The
existing timeout fixture/checker remain unchanged. The cause of this variable
remaining-time result is unqualified; no clock-granularity explanation is
treated as a passing regression. Registered results are 4/4 on AArch64 and
3/4 on x86-64.

## Evidence and reproduction

Run `tests/linux-compat/run.v --cases ppollargs` with an isolated kernel and
fresh external state directory. Both fixture sources are frozen and pinned;
the default budget is 300 seconds. `ppollargs-reference.v` accepts `--arch`,
`--kernel`, `--init`, `--launcher` and `--state-dir` for the same native ELF
on Linux. Build `ppollargs-evidence.v` without `-prod`, with
`-cc cc -cflags -O2`, and use `self-test`, `generated BEFORE-C AFTER-C`
and `BUNDLE` modes.

The complete external bundle is `/Users/alex/.cache/vx-pa-1114/bundle`.
It retains original/fixed kernels, generated C, build/compiler input/output
pins and commands, source snapshots/archive, Linux kernels/initramfs, native
images/firmware, all serial output, registered receipts including the failed
x86-64 timeout run, both unmodified replays, both numeric diagnostics,
allocation scans and review. Its 639-file manifest has SHA-256
`fa21bda6d3f7af40d1e35821ca144215c46a2a1edde7ae1e1dd962d6a994420d`.
The complete audit passes for ppoll comparison and artifact integrity while
explicitly retaining the unqualified regression. The versioned
`ppollargs-timeout-diagnostic.v` reproduces the diagnostic sources exactly
without changing the original timeout checks.

## Remaining scope

This qualifies the listed native raw 64-bit argument profiles with zero valid
timeouts. Nonzero remaining-time writeback, ppoll interruption output,
personality flags, resource-limit/count-capacity profiles, pointer aliasing and
concurrent mutation, partial copies, pending-signal/error and pressure races,
GNU wrappers and foreign/32-bit ABIs remain separate. Broader §15 semantics,
application installation/integration and translated-runtime gates remain open.
