# Negative epoll millisecond timeouts

Native epoll_wait and epoll_pwait now treat every negative millisecond timeout
as an indefinite wait. Previously values below -1 returned EINVAL before the
descriptor lookup. Removing that guard also preserves EBADF for invalid epoll
descriptors with those timeouts. The existing timer, readiness and signal paths
already handle negative values without a timer; no allocation or lifetime code
changes. See [Linux's timeout conversion](https://github.com/torvalds/linux/blob/v6.12/fs/eventpoll.c).

The V `epollnegativefixture` runs unchanged static musl ELFs on Linux
6.12.51 and native ARM/x86 production kernels. Root and UID1000/GID2000 cohorts
exercise -1, -2, -3, -999, -1000, -1000000, -2147483647 and -2147483648,
with SA_RESTART enabled and disabled. Raw epoll_pwait, musl epoll_wait/pwait
and raw x86 epoll_wait cover already-ready pipes, delayed I/O, handled SIGUSR1
and invalid descriptors. Empty zero/positive timeouts are controls.

A child observes the parent's sleeping state through /proc before delivering
I/O or a signal. The parent checks the return, event data, output guards,
handler count, original and handler masks, pipe contents and status flags
before reaping that child. This distinguishes blocking wakeup from an early
error followed by a signal or write during waitpid. Both SA_RESTART settings
return EINTR for a handled signal, and pwait handlers see the temporary mask.

All 3,264 ARM and 4,352 x86 semantic checks pass on both candidate and Linux
kernels. The original kernels reproduce exactly 840 and 1,120 failures;
the checker requires every expected failing case and assertion, as well as
the passing -1 and nonnegative controls.

Native storage controls run 200 warmed cohorts per credential group. They
exercise every negative timeout through ready-event and invalid-descriptor
paths, with transient epoll aliases. All 18 ARM and 14 x86 live slab classes
stay flat, large pages remain 74/74 and 177/177 respectively, and write-after-free
counters remain zero. These cohorts measure ready/error cleanup; they do not
measure retention from repeated sleeping child/signal cohorts.

Four maintained suites pass on both candidate kernels: ordinary-file epoll
refusals, O_PATH epoll control/wait errors, asynchronous pressure/cgroup/virtual
file/pidfd notifications and masked waits. The standalone native runner also
replays the same ARM probe successfully. Its supplied-ELF mode avoids requiring
another probe compilation when an audited ELF is available. The earlier direct
runner attempt using the minimal external SDK failed to link its absent pthread
archive and GCC startup objects; that attempt is retained.

Both isolated kernel source trees start at `d2d1a7462`; their only code change
is the timeout guard in `kernel/file/epoll.v`. Other sessions' select/exec edits
are excluded. Production builds use private V `0.5.2 395d574`, LIMINE_MP=1,
ALLOC_TRACK=0 and link seed 42. ARM uses 16 KiB pages with HVF and x86 uses
4 KiB pages with TCG. Matched baseline kernels and their complete preceding
audit bundle remain under `opathpoll-20261109`.

The complete external bundle is:

`/Users/alex/.cache/vinix-linux-compat/epollnegative-20261109`

It retains source snapshots/worktrees, generated C, compilers, probe/kernel
ELFs, build receipts, Linux kernels, boot images, raw logs and failed attempts.
`epollnegative-evidence.v BUNDLE` checks recorded input/output hashes, complete
candidate/reference/baseline manifests, storage controls and maintained replays.
Its parser passes six positive and 9,814 missing/duplicate/altered/failure/
retention rejection controls. Historical checkers remain unchanged; restore
the complete original bundle and its referenced dependencies before auditing.

Final probes are `compile-{arm,x86}-r4`, kernels are `build-{arm,x86}`, and
the native/reference/baseline receipts use their corresponding `*-{arm,x86}-r1`
directories. Maintained replays are `regression-*-{arm,x86}`; the standalone
receipt is `standalone-arm-r2`.

The final formatting pass produces byte-identical probe and launcher ELFs to
the tested r3 compilation; the auditor checks that identity and retains the
original fixture snapshot separately.

Compile `run-epollnegative.v` with native guest tool modules on V's module path,
then supply `--arch`, `--kernel-dir`, a fresh external `--state-dir`, and optionally
`--init PROBE-ELF`. The reference controller accepts the identical probe ELF and
a supplied Linux kernel; `--self-test` exercises its result parser. The evidence
auditor writes `epollnegative-artifacts.json` beside the external receipts.
The complete audit passes both architectures. The manifest SHA-256 is
`66c9252415b3c9bf76ade22bee2e39655deccbccb6bf9cf99dfd07a121e46008`.

This qualifies the stated native musl paths and normalized signed timeout words
with valid output buffers and signal masks. Raw argument upper words, malformed
argument precedence, close/reuse races, GNU libc, cancellation and foreign/32-bit
paths remain separate. Section 15's broad compatibility gates remain open.
