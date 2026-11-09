# Native epoll output-range admission

Native epoll_wait, epoll_pwait and epoll_pwait2 now reject output-array spans
outside the process address range with EFAULT before looking up epfd or
collecting events. The validated event count and architecture-specific event
size bound the complete span. This also preserves one-shot readiness when an
invalid range is rejected. No allocation, ownership or event-collection code
changes. See [Linux's admission order](https://github.com/torvalds/linux/blob/v6.12/fs/eventpoll.c).

This is an address-range check. It does not probe page mappings or permissions.
Null remains a canonical address, so an empty set can return zero with null,
unmapped or read-only output memory. An actual event copy can still fault.
Vinix uses its existing process address limit; Linux references may support a
larger virtual address space. The compared invalid spans are outside both
environments' ranges or cross the reference's highest user boundary.

The V `epollrangefixture` runs unchanged static musl ELFs on Linux 6.12.51 and
native production kernels. Root and UID1000/GID2000 cohorts exercise zero,
one, two and oversized event counts through raw epoll_pwait/pwait2, musl
epoll_wait/pwait and raw x86 epoll_wait. Descriptors include empty/ready epoll
sets, duplicate aliases, missing descriptors, ordinary files and O_PATH handles.

Six invalid output addresses cover high/kernel addresses, address-limit
crossings and unsigned wraparound. Every descriptor kind must report EFAULT
for valid counts, while invalid counts retain EINVAL. Canonical null, unmapped
and read-only controls cover empty and wrong/missing descriptors; actual copies
to these destinations are deliberately outside this qualification. Low mapped
buffers still receive events. Raw pwait2 controls preserve timespec-copy EFAULT
and negative/unnormalized-timespec EINVAL before invalid-range errors.

Each call checks exact return/errno, guarded event output, restored mask,
unchanged mask/timeout/read-only inputs, follow-up one-shot readiness and pipe
data/flags. Both credential groups use readable, correctly sized signal masks.
All 11,376 ARM and 14,112 x86 checks pass on Linux and candidate kernels.
Matched originals fail exactly 576 and 720 respectively. The parser requires
every expected case and failing baseline assertion, as well as the summary.

Native cleanup measurements repeat mapped output and two invalid ranges through
empty, ready, duplicate and missing descriptors, closing a transient alias every
cycle. After warmup, 200 cohorts per credential group leave all 18 ARM / 14 x86
live slab classes unchanged. Large pages remain 68/68 and 177/177 respectively;
write-after-free counters stay zero. These measure zero-time ready/error paths.

Six maintained suites pass on both candidate kernels: event-count bounds,
negative millisecond timeouts, O_PATH epoll refusal, ordinary-file epoll refusal,
asynchronous notifications and masked waits. A standalone ARM run also exercises
the committed native controller with the same supplied probe ELF.

Both isolated source trees start at `37e808b16`; only the range guard in
`kernel/file/epoll.v` changes. Other sessions' pending select/exec edits are
excluded. Production builds use private V `0.5.2 395d574`, LIMINE_MP=1,
ALLOC_TRACK=0 and link seed 42. ARM uses 16 KiB pages with HVF; x86 uses 4 KiB
pages with TCG. Baselines retain the preceding event-count fix and its complete
`epollmax-20261109` audit bundle.

The external bundle is:

`/Users/alex/.cache/vinix-linux-compat/epollrange-20261109`

It preserves source snapshots/worktrees, generated C, probe/kernel ELFs, build
receipts, Linux kernels, boot images and raw logs. Probes, native/reference/
baseline receipts and the standalone receipt use their `*-r1` directories;
candidate builds are `build-{arm,x86}`. Maintained receipts use
`regression-*-{arm,x86}`.

`epollrange-evidence.v BUNDLE` verifies recorded input/output hashes, complete
candidate/reference/baseline manifests, flat storage and maintained replays.
Its parser passes six positive and 936 sampled missing/duplicate/altered/
failure/retention rejection controls. Historical checkers are unchanged;
restore the complete original bundle and referenced dependencies before audit.
The auditor writes `epollrange-artifacts.json` beside the receipts.
The complete audit passes both architectures. The manifest SHA-256 is
`b8d902202fa0f05466db34a94f56e13c5909daeb38ec9c400ee0f315b28e5764`.

For fresh runs, compile `run-epollrange.v` with native guest tool modules on V's
module path, then supply `--arch`, `--kernel-dir`, a fresh external `--state-dir`
and optionally `--init PROBE-ELF`. The reference controller accepts that identical
ELF, a Linux kernel and an optional precompiled launcher; `--self-test` exercises
its parser.

Argument upper words, pointer tags, malformed-mask precedence, actual output-copy
faults and their one-shot delivery effects, concurrent close/reuse, GNU libc,
cancellation and foreign/32-bit paths remain separate. Section 15's broad
compatibility gates remain open.
