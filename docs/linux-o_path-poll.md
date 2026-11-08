# Native O_PATH poll refusal

Native poll/ppoll now report POLLNVAL for O_PATH descriptions, including when
the requested event mask is empty. The flag check occurs after the descriptor
lookup and before consulting the underlying resource. It releases both lookup
references and never installs an event listener for the path handle. Other
entries still contribute their own readiness. See
[Linux's descriptor lookup and unconditional invalid-descriptor result](https://github.com/torvalds/linux/blob/v6.12/fs/select.c).

The V `opathpollfixture` runs identical static musl ELFs on Linux 6.12.51 and
both native production architectures. All 7,680 ARM and 10,240 x86 checks pass;
the original kernels fail every one. Root and UID1000/GID2000 exercise raw
ppoll, musl ppoll/poll, and raw x86 poll. Ten O_PATH descriptions include
regular files, CLOEXEC/dup/high aliases, directories, `/proc/version`, ordinary
and dangling symlink inodes and a procfs magic link. Unlinking the named files
and links does not change descriptor eligibility.

Sixteen event masks cover read/write/normal/priority/error/hangup/unused bits
and zero. Single-entry calls and mixed four-entry arrays check both path
entries, an ordinary-file control and an ignored negative descriptor. Exact
counts, revents, unchanged input fields, unused array tails, buffer guards,
descriptor flags, file data and shared cursors are required. Four phases put
the ordinary file empty, before EOF, at EOF and beyond EOF. Calls use zero or
finite timeouts; this does not qualify indefinite waits or signal-mask races.

Each credential group warms the complete cohort and repeats it 200 times.
All live slab classes and large-page counts remain flat, with zero writes
after free. The same candidate kernels pass the 3,840 ARM / 5,120 x86
ordinary-file checks with flat storage, four pressure/virtual-file/pidfd
cohorts and all 1,256 masked-wait checks per architecture. Independent review
found no reference, listener or allocation-lifetime defect in the new branch.

The isolated source base is `4b520a93b`, with only the `file.v` O_PATH branch
changed. Other sessions' pending select/exec work is excluded. The baseline
uses the preceding qualified kernel bundle, whose ppoll implementation is
unchanged; its separately recorded select-count prerequisite is outside this
poll fixture. Both production builds use private V `0.5.2 395d574`,
LIMINE_MP=1, ALLOC_TRACK=0 and link seed 42. ARM has 16 KiB pages; x86 has
4 KiB pages.

The complete external bundle is:

`/Users/alex/.cache/vinix-linux-compat/opathpoll-20261109`

It retains source worktrees, kernel and probe ELFs, generated C, build and
compile receipts, Linux kernels, disposable images and raw serial logs.
`opathpoll-evidence.v BUNDLE` audits complete result manifests, identities,
baseline failures, storage and the maintained replays, and writes the external
`opathpoll-artifacts.json` SHA-256 manifest. The parser passes four positive
and 2,414 negative controls for missing, duplicated, altered, failed and
non-flat results. Restore the complete original bundle before auditing it.

The complete audit passes both architectures. The manifest SHA-256 is
`3ca46ca6a34ec0aa3201ebb7e37b2525789b98b922ff08fbed5ce61390b3ed16`.

For fresh runs, compile `tests/linux-compat/run-opathpoll.v` with the native
guest modules on V's module path and supply `--arch`, `--kernel-dir` and a
fresh external `--state-dir`. `opathpoll-reference.v` accepts the identical
probe ELF and a supplied Linux kernel; `--self-test` exercises its parser.

This qualifies the described native musl poll paths. Select, epoll, concurrent
close/reuse, malformed argument precedence, NULL timeouts, GNU libc and
foreign/32-bit paths remain separate. Section 15's broader gates stay open.

The [epoll follow-up](linux-o_path-epoll.md) separately qualifies path-only
descriptor refusals in control and wait operations.
