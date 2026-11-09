# Native epoll wait integer words

Native epoll_wait and epoll_pwait now decode epfd, maxevents and the millisecond
timeout from each register's signed low 32 bits. Epoll_pwait2 reaches the same
descriptor/count conversion after importing its timespec. This matches Linux's
C int arguments while preserving full-width pointers and sigsetsize. Previously
nonzero upper words could cause EBADF/EINVAL or turn a zero timeout into a wait.
No allocation, ownership or readiness code changes. See
[Linux's wait syscall declarations](https://github.com/torvalds/linux/blob/v6.12/fs/eventpoll.c).

The V `epollwordsfixture` runs unchanged static musl probe ELFs on Linux
6.12.51 and native production kernels. Root and UID1000/GID2000 cohorts use
canonical/sign-extended words, zero extension and upper words 1, 0x7fffffff,
0x80000000 and 0xffffffff. Raw epoll_pwait/pwait2 and raw x86 epoll_wait exercise
empty/ready sets, aliases, missing descriptors, ordinary files and O_PATH handles.

Descriptor trials vary only epfd's upper word. Count trials vary the upper word
around signed minimum, -1, zero, one, two, the ABI's maximum count, its first
oversized count and signed maximum. Every call checks return/errno, guarded
output, restored masks, unchanged timespec/mask inputs, follow-up one-shot
readiness and pipe data/flags. Full-width sigsetsize controls still reject
decorated sizes whose low word is eight; that size argument must not be truncated.

Zero-timeout trials include 0xffffffff00000000, which must mean zero rather
than an indefinite wait. A child observes the parent's sleeping state before
sending SIGUSR1. The parent captures its result and handler count before reaping
the child. Correct calls return zero before that signal arrives during waitpid;
the original kernels sleep inside epoll and return EINTR instead. The handler
mask also distinguishes an interrupted pwait from the later ordinary wait.
Each trial waits for the child's signal to be handled before resetting its state.

All 8,712 ARM and 12,672 x86 checks pass on the candidate and final Linux runs.
Matched originals fail exactly 584 and 880 respectively. The parser requires
every expected case and failing baseline assertion, rather than just a summary.

After warmup, 200 native cohorts per credential group repeat decorated
descriptor/count words and full-width size errors through empty, ready,
duplicate and missing descriptors, closing a transient alias each cycle.
All 18 ARM / 14 x86 live slab classes stay flat; large pages remain 74/74 and
177/177 respectively, and write-after-free counters stay zero. These measure
ready/error cleanup, rather than repeated fork/signal trials.

Seven maintained suites pass on both candidate kernels: output ranges,
event-count bounds, negative timeouts, O_PATH and ordinary-file epoll refusals,
asynchronous notifications and masked waits. A standalone ARM run exercises the
committed native controller with the supplied probe ELF.

The original x86 Linux reference is retained: a clocksource console warning
split one case record, and the strict parser rejected it despite a zero-failure
guest summary. Final references use loglevel=4 to suppress ordinary console
chatter and read /proc/version in the launcher to retain the Linux identity.
Kernel errors remain visible. The auditor also requires rejection of the
original incomplete log and includes its artifacts and original sources.

Both isolated kernel worktrees start at `42db9d223`; only the shared wait's
three integer conversions change. Other sessions' pending select/exec work is
excluded. Production builds use private V `0.5.2 395d574`, LIMINE_MP=1,
ALLOC_TRACK=0 and link seed 42. ARM uses 16 KiB pages with HVF; x86 uses 4 KiB
pages with TCG. Matched baseline kernels and their complete preceding audit
bundle remain under `epollrange-20261109`.

The external bundle is:

`/Users/alex/.cache/vinix-linux-compat/epollwords-20261109`

It preserves source snapshots/worktrees, generated C, probe/kernel ELFs,
compiler/build receipts, Linux kernels, boot images and raw logs. Final probe/
launcher compilations and Linux references are `*-{arm,x86}-r2`; native and
baseline receipts are `*-{arm,x86}-r1`, candidate builds are `build-{arm,x86}`,
and maintained replays are `regression-*-{arm,x86}`. The standalone receipt is
`standalone-arm-r1`. Recompiling the launcher leaves the tested probe bytes
unchanged; native/reference receipt comparisons require that identity.

`epollwords-evidence.v BUNDLE` checks recorded input/output hashes, complete
candidate/reference/baseline manifests, flat storage and maintained replays.
Its parser passes six positive and 836 sampled missing/duplicate/altered/
failure/retention rejection controls. Historical checkers are unchanged; restore
the complete original bundle and its referenced dependencies before audit.
The auditor writes `epollwords-artifacts.json` beside the external receipts.
The complete audit passes both architectures. The manifest SHA-256 is
`91d15118d57973bece3c7472553b9d27a3592fff709856d813744c1bfda08558`.

For fresh native runs, compile `run-epollwords.v` with native guest tool modules
on V's module path and supply `--arch`, `--kernel-dir`, a fresh external
`--state-dir`, and optionally `--init PROBE-ELF`. The reference controller accepts
the identical probe, a Linux kernel and optional precompiled launcher;
`--self-test` exercises its result parser.

Epoll control/create integer words, malformed-mask precedence, canonical output
copy faults and their one-shot effects, concurrent close/reuse, GNU libc,
cancellation and foreign/32-bit paths remain separate. Section 15's broad
compatibility gates remain open.
