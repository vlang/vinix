# Native poll result-field copyout

Poll and ppoll now write only each `pollfd.revents`, in array order. They no
longer require the input-only `fd` and `events` fields to be writable. A refused
output returns EFAULT after preserving earlier completed entries, and leaves
the failed entry and subsequent entries unchanged when each two-byte result is
contained within one page. Linux uses the same result-field loop in
[Linux 6.12 fs/select.c](https://github.com/torvalds/linux/blob/v6.12/fs/select.c#L953-L978).
Existing input import, EINTR output, timeout finishing, references, budgets and
array cleanup are unchanged. The kernel change allocates and frees nothing.

The new `pollcopy` fixture runs raw ppoll, musl ppoll/poll, and raw x86-64 poll
as root and UID1000/GID2000. Eight memory layouts include writable controls,
read-only headers with writable results, first/later read-only results,
zero-count calls and inaccessible input. One-, two- and three-entry arrays,
six event masks and six descriptor classes cover ordinary files, empty/ready
UNIX sockets, negative descriptors, closed slots and O_PATH handles. Every
case checks exact return/errno, all 64 surrounding bytes, description flags,
an unchanged queued byte and file contents/cursor. Unaligned user arrays are
initialized through byte copies from explicit aligned stack storage.

Identical final musl ELFs pass 10,368 AArch64 and 13,824 x86-64 checks on Linux
6.12.51. The unchanged original kernels fail 1,296 and 1,728 respectively,
entirely in the read-only-header layouts. Corrected native kernels pass every
check with identical ELFs. Both credential cohorts retain all 18 ARM / 14 x86
slab classes flat, with large pages 83/83 on ARM and 222/222 on x86-64 and
zero writes after free. Parser controls pass six positive and 1,024 negative
cases; generated-C scope and independent lifetime/ABI review pass.
The final registered ppolltime, ppollsignal and pollcopy cohorts pass 3/3 on
each architecture, including their unchanged semantic and strict storage checks.

Each native credential cohort warms 64 cycles, then measures 200 cycles across
every API and layout. Strict checks retain every slab class, large-page counts
and zero writes after free. The baseline runs keep the same inputs and guards.
Checker controls reject missing/duplicate/altered rows, failure markers, changed
storage, malformed/overflowing counts and incomplete slab layouts.

The isolated worktrees start at `4fbde3625b14eaf3d65c7ffba60d1bf6d86ae419`.
Original production kernels are the retained interrupted-poll builds at
`57c608b09ad4df7e1c9f894c2ed93bb18059536c`. Both corrected kernels use V 0.5.2
`7d74206`, PROD=true, LIMINE_MP=1, ALLOC_TRACK=0 and link seed 42. Generated-C
comparison permits only the `poll_user_fds` body change after canonicalizing
absolute-path hashes. Independent lifetime/ABI review covers the synchronous
source borrow, bounded address arithmetic, explicit fixture stack buffers and
restored mapping protections.

The retained external bundle is `/Users/alex/.cache/vx-po-1114/bundle`.
Its 839-file manifest has SHA-256
`fc7beca3a0aa026fc68e50ad70102e20d2f1580dd08f711d26cbb7321500058f`.
Failed initial builds without a selected compiler, V/C fixture compilation
refusals, the first unaligned-setup experiment and corrected final runs remain
separate artifacts.
The first registered cohorts ended before all three receipts were recorded
(two ARM cases and one x86 case completed); their partial logs remain retained.
`pollcopy-evidence.v BUNDLE` checks the complete inventory, builds, source/C/ELF
identities, exact baseline failures, same-ELF Linux/native outcomes, strict
storage and all selected registered results. Its `self-test`, `serial` and
`scope` modes expose the individual checks. Build without `-prod`.
The complete 839-file audit passes.

Fresh guest runs use `tests/linux-compat/run --cases pollcopy` with a matching
built kernel and fresh external state directory. The runner freezes both
fixture sources. `pollcopy-reference.v` runs that same probe ELF and its
recorded launcher on a supplied Linux kernel.

Concurrent caller mutation, signal/output-fault combinations, revents spanning
pages, output aliases, pressure, restart/cancellation and GNU/foreign/32-bit
paths remain separate. Section 15's broader application/runtime gates remain
open. This qualification does not resolve historical unrelated memory deltas.
