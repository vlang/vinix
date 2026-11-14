# Native select timeval normalization

Raw x86-64 select now carries whole millions of microseconds into seconds
before validating its timeout. For example, `{0, 1000000}` means one second,
and `{-1, 1000000}` means zero. A negative remainder remains invalid:
`{1, -1}` returns EINVAL, while `{1, -1000000}` means zero. The seconds
addition explicitly wraps at the native 64-bit ABI width; a resulting
negative second or subsecond value returns EINVAL.

This follows [Linux v6.12 kern_select](https://github.com/torvalds/linux/blob/v6.12/fs/select.c#L656),
with the kernel's [signed-overflow build policy](https://github.com/torvalds/linux/blob/v6.12/Makefile#L913).
Valid nonzero durations retain remaining-time writeback and read-only timeout
result preservation. A normalized zero skips writeback, including when the
original timeval was noncanonical. Pselect6 keeps its strict timespec rules.

## Qualification

Original and fixed production kernels are built in isolated worktrees from
`9b0a390bad3be71729d58d888d338339c03ef1d2` plus the retained pselect.v patch,
using V 0.5.2 `7d74206`, `PROD=true LIMINE_MP=1 ALLOC_TRACK=0` and link seed 42.
Input maps differ only in pselect.v. Each architecture uses the identical
static musl probe ELF on original/fixed Vinix and Linux 6.12.51:

| Architecture | Checks | Original failures | Fixed failures | Linux failures |
| --- | ---: | ---: | ---: | ---: |
| AArch64 | 5,184 | 0 | 0 | 0 |
| x86-64 | 10,368 | 480 | 0 | 0 |

The 36 explicit input profiles cover zero, canonical fractions, positive
carries, negative remainders, whole negative carries, negative seconds
rescued by carries, signed64 limits and overflowing seconds addition.
Expected normalized values are listed explicitly, independently of the
kernel arithmetic. Raw pselect6 supplies strict timespec controls on both
architectures; raw select is exercised only on x86-64, where its syscall exists.

Root and UID1000/GID2000 cross every profile with queued UNIX socket
readiness, a selected closed descriptor, negative nfds and an inaccessible
read bitmap, using writable and read-only timeout pages. Each call checks
return value/errno, all three full guarded fd sets, guarded timeout with
monotonic remaining-time bounds, unchanged mask pack, restored signal mask
and unchanged queued data. Descriptor 1023 stays open to align table capacity.
The original x86-64 failures are exactly 18 newly accepted profiles per
credential: three normalized zeros produce ten failures each, and fifteen
nonzero durations produce fourteen each.

Each native credential cohort warms 64 complete cycles and measures 200
cycles. All slab classes, large-page counts and allocator taint must stay flat.
The Linux runs explicitly skip Vinix storage checks. The strict parser
passes six positive and 1,648 negative controls, requiring every semantic
row and complete storage class/cohort records.
Original/fixed large pages are 83/83 on AArch64 and 222/222 on x86-64 in
both credential cohorts; all live slab classes are flat and taint stays 0/0.

The complete generated-C delta is limited to the raw select entrypoint.
Only two scalar locals are added; usercopy, core select, deadline and finish
call counts stay unchanged. No allocation, buffer address, owner, free or
wait lifetime changes. AArch64 generated kernel C is unchanged because the
raw select entrypoint is not dispatched there.
Independent lifetime/arithmetic review passes. Generated-C controls pass one
positive/eight scoped negative mutations on x86-64 and complete equality on
AArch64. Full allocation scans retain the same 391 AArch64 / 291 x86-64 sites
and 180 pre-existing excess groups against allowed.txt; this change adds none.
The global allocation gate remains open.

Fresh registered selecttimeval, selecttimeout, selectorder and selectfds
cases pass on both fixed kernels. Each case compiles its frozen fixture
sources, and the existing timeout/order/descriptor parsers remain unchanged.

## Evidence and reproduction

Run `tests/linux-compat/run.v --cases selecttimeval` with an isolated kernel
and fresh external state directory. Both fixture files are frozen and pinned;
the default case budget is 300 seconds. `selecttimeval-reference.v` accepts
`--arch`, `--kernel`, `--init`, `--launcher` and `--state-dir` to run the same
native probe ELF on Linux. Build `selecttimeval-evidence.v` without `-prod`,
with `-cc cc -cflags -O2`, and use its `self-test`,
`generated BEFORE-C AFTER-C` and `BUNDLE` modes.

The complete external bundle is `/Users/alex/.cache/vx-tv-1114/bundle`.
It retains original/fixed kernels, generated C, build/compiler input/output
pins and commands, source snapshots/archive, Linux kernels/initramfs, native
images/firmware, serial output, registered receipts, allocation scans and
review. Its 520-file manifest has SHA-256
`94fdf7b873d0af85294b21a59d2720f2ae1d30c8f2091d5ae061c44152f1094f`.
The complete evidence audit passes, including every retained artifact hash.

## Remaining scope

This qualifies the listed native raw 64-bit profiles with the default
personality. GNU/libc select wrappers, STICKY_TIMEOUTS, pointer aliasing and
concurrent mutation, partial page-crossing copies, pending-signal/error races,
foreign/32-bit ABIs and ppoll writeback remain separate. Broader §15 semantics,
application installation/integration and translated-runtime gates remain open.
