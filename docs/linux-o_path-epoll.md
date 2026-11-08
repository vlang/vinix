# Native O_PATH epoll refusal

Native epoll_ctl now rejects O_PATH in either descriptor slot with EBADF.
It imports both descriptors before checking the epoll resource type, so a
path-only or missing target retains EBADF even when the first descriptor is
an ordinary file. Native epoll_wait, epoll_pwait and epoll_pwait2 also reject
path-only epoll descriptors. Existing event and timeout imports are unchanged.
See [Linux's descriptor admission](https://github.com/torvalds/linux/blob/v6.12/fs/eventpoll.c).

The V `opathepollfixture` runs unchanged static musl ELFs on Linux 6.12.51 and
native ARM/x86 production kernels. It checks ten O_PATH descriptions as root
and UID1000/GID2000: unlinked regular files, CLOEXEC/dup/high aliases,
directories, proc files, symlink inodes and a procfs magic link. Raw and musl
epoll_ctl cover ADD/MOD/DEL, empty and edge-triggered event masks, both path
slots, invalid descriptor combinations and ordinary-file epoll descriptors.
Actual epoll self calls and wrong-type calls with valid targets retain EINVAL.
Every call preserves event input guards, status flags and the ordinary-file
cursor; failed calls leave the actual epoll set empty.

Wait controls use raw epoll_pwait/pwait2, musl epoll_wait/pwait and raw x86
epoll_wait, with canonical output buffers, valid sizes and zero timeouts.
All refused outputs remain untouched. The pinned musl headers do not provide
epoll_pwait2; the initial attempt to use that wrapper is retained as a failed
compilation, and the real raw syscall is tested instead.

All 8,960 ARM and 9,040 x86 checks pass on the final native and Linux kernels.
Original kernels fail 6,080 and 6,160 respectively. Native storage controls create
and close transient aliases around target-O_PATH, self and wrong-type errors,
including wait errors, so leaked lookup references would retain new FD objects.
Warmup precedes 200 full cohorts per credential group. Every slab class,
large-page count and write-after-free counter must remain unchanged.

Both native credential cohorts pass: all 18 ARM / 14 x86 live slab classes
stay flat, with 63/63 ARM and 160/160 x86 large pages and zero writes after
free. Every maintained replay passes on both candidate kernels.

Maintained replays on the same kernel cover ordinary-file epoll refusals,
O_PATH poll/POLLNVAL, pressure/virtual-file/pidfd notifications and masked
waits. Independent review found every target lookup and deferred epoll lookup
balanced before returning or installing listeners. Successful registrations
retain their original ownership.

Both isolated source trees start at `bf83be98e`; only `kernel/file/epoll.v`
changes. Pending select/exec work from other sessions is excluded. Production
builds use private V `0.5.2 395d574`, LIMINE_MP=1, ALLOC_TRACK=0 and link seed
42. ARM uses 16 KiB pages and x86 uses 4 KiB pages. The preceding poll kernels
provide the matched baseline; their full receipts and source trees are retained.

The external audit bundle is:

`/Users/alex/.cache/vinix-linux-compat/opathpoll-20261109`

It includes source worktrees, full generated C, kernel/probe ELFs, compilation
and build receipts, Linux kernels, boot images, raw logs and failed attempts.
`opathepoll-evidence.v BUNDLE` checks complete native/reference manifests,
probe/kernel identities, baseline failures, heap retention and maintained
replays. It writes `opathepoll-artifacts.json` with SHA-256 checksums. The
parser passes four positive and 2,094 negative missing/duplicate/altered/
failure/retention controls. Restore the complete original bundle before audit.

The complete audit passes both architectures. The manifest SHA-256 is
`eb0254efd1ce17de1ff4250476457445e8fb8529d4f5e8847049fb2ab66e6997`.
Final probes are `compile-epoll-{arm,x86}-r2`; native, reference and baseline
receipts are `{native,reference,baseline}-epoll-{arm,x86}-r1`. Candidate builds
are `build-epoll-{arm,x86}` and replays use `epoll-regression-*-{arm,x86}`.

For fresh native runs, compile `tests/linux-compat/run-opathepoll.v` with the
native guest tool modules on V's module path, then supply `--arch`,
`--kernel-dir` and a fresh external `--state-dir`. The reference controller
accepts the identical probe ELF and a supplied Linux kernel; `--self-test`
exercises the result parser.

This qualifies the described native musl descriptors and valid argument
layouts. Malformed signal-mask/output-range precedence, invalid flag and
timeout combinations, descriptor upper words, concurrent close/reuse, epoll
self aliases, cancellation and GNU/foreign/32-bit paths remain separate.
Section 15's broader acceptance gates remain open.
