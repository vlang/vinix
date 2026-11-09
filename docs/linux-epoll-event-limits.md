# Native epoll event-count limits

Native epoll_wait, epoll_pwait and epoll_pwait2 now reject event counts above
`INT_MAX / sizeof(struct epoll_event)` with EINVAL, before descriptor lookup
or event collection. The largest accepted count is 134,217,727 on AArch64
(16-byte events) and 178,956,970 on x86-64 (12-byte events). Previously oversized
waits could succeed, report descriptor/copy errors or consume one-shot readiness.
The existing ABI event size controls the guard; no allocation or ownership code
changes. See [Linux's event-count guard](https://github.com/torvalds/linux/blob/v6.12/fs/eventpoll.c).

The V `epollmaxfixture` runs unchanged static musl ELFs on Linux 6.12.51 and
native production kernels. Root and UID1000/GID2000 cohorts exercise twelve
counts: signed minimum, -1, zero, small valid counts, each architecture's last
two valid counts, first two oversized counts, x86 boundary values and signed
maximum. Raw epoll_pwait/pwait2, musl epoll_wait/pwait and raw x86 epoll_wait
cover empty/ready epoll sets, aliases, missing descriptors, ordinary files and
O_PATH handles. Invalid counts also use null and noncanonical output pointers.

Each call checks the exact return/errno, output data and guards, restored signal
mask, unchanged mask/timeout inputs, one-shot readiness and queued pipe data/
flags. A valid follow-up wait must still receive the event after rejection.
Raw pwait2 controls require unreadable timespec EFAULT and negative/unnormalized
timespec EINVAL before the count/descriptor checks, for both valid and oversized
counts. Signal masks are readable and correctly sized throughout.

All 8,496 ARM and 9,792 x86 checks pass on the candidate and Linux kernels.
Matched originals fail exactly 920 checks each. The checker requires every
passing and failing baseline assertion, rather than accepting only a summary.

The first ARM Linux reference run with stack buffers failed 160 assertions.
The final fixture maps its output at a low hint and requires an address no
higher than 4 GiB, leaving space for the declared array range below the user
address limit. Only 16 KiB is mapped: these tests deliver at most one actual
event. The initial reference and compilation failures remain in the bundle.
Initial fixed-array expressions required an unavailable runtime helper. V
matches and explicit descriptor closes resolved compilation; neither the
compiler nor its prelude was changed.

After warmup, 200 native cohorts per credential group repeat the largest valid
and first oversized count through empty, ready, duplicate and missing descriptors.
Transient aliases are closed each cycle. All 18 ARM / 14 x86 live slab classes
stay flat, large pages remain 68/68 and 177/177 respectively, and write-after-free
counters remain zero. These are zero-time ready/error cleanup measurements.

Five maintained suites pass on both candidate kernels: negative millisecond
timeouts, O_PATH epoll refusal, ordinary-file epoll refusal, asynchronous
notifications and masked waits. A separate standalone ARM run exercises the
committed native controller with the same supplied probe ELF.

Both isolated kernel worktrees start at `459ead9e8`; only the maxevents guard
in `kernel/file/epoll.v` changes. Other sessions' pending select/exec edits are
excluded. Production builds use private V `0.5.2 395d574`, LIMINE_MP=1,
ALLOC_TRACK=0 and link seed 42. ARM uses 16 KiB pages with HVF; x86 uses 4 KiB
pages with TCG. Baseline kernels retain the preceding timeout fix and are
preserved with their complete `epollnegative-20261109` audit bundle.

The external bundle is:

`/Users/alex/.cache/vinix-linux-compat/epollmax-20261109`

It preserves source snapshots/worktrees, generated C, probe/kernel ELFs, build
receipts, Linux kernels, boot images, raw logs and failed attempts. Final probes
are `compile-{arm,x86}-r3`, native/reference/baseline runs are their respective
`*-{arm,x86}-r2` directories, and candidate builds are `build-{arm,x86}`.
Maintained receipts are `regression-*-{arm,x86}`; the standalone receipt is
`standalone-arm-r1`.

`epollmax-evidence.v BUNDLE` verifies recorded input/output hashes, complete
candidate/reference/baseline manifests, flat storage and maintained replays.
Its parser passes six positive and 774 sampled missing/duplicate/altered/
failure/retention rejection controls. Historical checkers are unchanged;
restore the complete original bundle and referenced dependencies before audit.
The auditor writes `epollmax-artifacts.json` beside the external receipts.
The complete audit passes both architectures. The manifest SHA-256 is
`26707f0f2bde56aa1005e6d345a7db4891d6eb192e0b0db702d0eca6a5085ca6`.

For fresh native runs, compile `run-epollmax.v` with the native guest tool
modules on V's module path, then supply `--arch`, `--kernel-dir`, a fresh
external `--state-dir`, and optionally `--init PROBE-ELF`. The reference controller
accepts that same ELF, a Linux kernel and an optional precompiled launcher;
`--self-test` exercises the parser.

This qualifies normalized native count words with valid signal masks and
the described timeout/output layouts. Descriptor/count upper words, valid-count
output-range faults, malformed-mask precedence, close/reuse races, GNU libc,
cancellation and foreign/32-bit paths remain separate. Section 15's broad
compatibility gates remain open.
