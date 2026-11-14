# Native select argument error order

Native pselect6 now imports its signal argument pack before the timeout,
validates the timeout before the mask, and validates/installs the mask before
checking nfds and descriptor sets. Raw x86-64 select imports and validates its
timeout before checking nfds. This follows the entrypoint layering in
[Linux v6.12 fs/select.c](https://github.com/torvalds/linux/blob/v6.12/fs/select.c).

Previously, an invalid nfds could hide an inaccessible timeout or mask header
behind `EINVAL`. An invalid descriptor bitmap could hide a bad mask size
behind `EFAULT`, and an invalid timeout could hide an inaccessible pselect
argument pack. The corrected order reports the Linux error without changing
the supplied buffers, timeout, mask header or queued socket data.

## Qualification

Original and fixed isolated production kernels were built from
`00b2908ddee97230f7a8a24537a5dd9d11b44300` plus the retained pselect.v patch,
with V 0.5.2 `f9ebca4`, `PROD=true LIMINE_MP=1 ALLOC_TRACK=0` and link seed 42.
The source input maps differ only in pselect.v. The identical static musl ELF
for each architecture runs on its original kernel, fixed kernel and Linux
6.12.51 reference:

| Architecture | Checks | Original failures | Fixed failures | Linux failures |
| --- | ---: | ---: | ---: | ---: |
| AArch64 | 9,720 | 210 | 0 | 0 |
| x86-64 | 11,340 | 222 | 0 | 0 |

Root and UID1000/GID2000 exercise raw pselect6 and, on x86-64, raw select.
The matrix crosses nfds -1/0/33; absent mask packs, NULL masks with ignored
sizes, valid masks, wrong mask sizes, inaccessible masks and inaccessible
packs; zero, inaccessible and invalid timeouts; valid empty sets, unreadable
read/write/exception sets, a selected closed descriptor and a queued UNIX
socket. Timeout refusals include negative seconds/subseconds, out-of-range
pselect nanoseconds and another negative-seconds raw-select control. All valid
timeouts are zero, so the probe never relies on an unbounded wait.

Each call checks return value, errno, all three complete guarded fd sets,
the guarded timeout and mask pack, restored mask and unchanged queued data.
Holding descriptor 1023 open aligns the Linux/Vinix table capacity. The
original failures are exactly errno mismatches: 210 pselect checks on each
architecture and 12 additional raw-select checks on x86-64.

Each native credential cohort warms 64 full matrix cycles and then measures
200 cycles. All live slab classes, including the AArch64 medium classes,
large-page counts and allocator taint stay flat. Original/fixed AArch64 large
pages are 83/83 in both cohorts; x86-64 is 222/222. Reference runs explicitly
skip Vinix storage measurements. The strict parser passes six positive and
896 negative controls, requiring every semantic row and complete storage
cohorts/class layouts.

The complete generated-C delta is limited to the two public entrypoints,
the private select helper and its declaration. Allocation, cleanup, wait and
mask-installation call counts are unchanged. Imported pack/timeout/mask
values stay on the stack; no heap promotion, boxing or reference owner is
added. Independent lifetime review confirms that both architecture exits
restore the saved mask before pending signal dispatch on EINVAL/EFAULT;
EINTR handling is unchanged. Two positive and twelve generated-C mutation
controls check ordering, mask validation, allocation and scope.

Fresh registered selectorder, selectempty, maskwait and selectfds cases pass
on both fixed kernels, retaining the strict existing empty-wait and descriptor
parsers. These cover normal handled-signal waits and restored masks in addition
to the new argument-error matrix. No retained probe binary substitutes for a
registered fixture build.

## Evidence and reproduction

Run `tests/linux-compat/run.v --cases selectorder` with the usual architecture,
isolated kernel and fresh state directory. The case freezes both fixture
sources and has a 300-second default budget. `selectorder-reference.v` takes
`--arch`, `--kernel`, `--init`, `--launcher` and `--state-dir` to run the exact
native probe ELF against Linux.

The complete external bundle is `/Users/alex/.cache/vx-se-1114/bundle`.
It retains original/fixed kernels, generated C, build/compiler input/output
pins and commands, source snapshots/archive, Linux kernels/initramfs,
native images/firmware, all serial output, registered receipts and review.
The 509-file manifest has SHA-256
`b96606d2d78b29f66e31f9fa915fd5bb6d1192e7345e586ef604cfd2664248a4`. Build
`selectorder-evidence.v` without `-prod`, using `-cc cc -cflags -O2`, and run
its `self-test`, `generated BEFORE-C AFTER-C` and `BUNDLE` modes.

## Remaining scope

This qualifies the selected native error-order combinations with canonical
counts and zero valid timeouts. Positive counts above 1024, smaller Linux
tables, argument aliasing/concurrent mutation, page-crossing partial copies,
pending-signal/error races, nonzero timeout writeback, timeval normalization,
GNU wrappers and foreign/32-bit ABIs remain separate. The broader §15
semantics, installation/integration and translated-runtime gates remain open.
