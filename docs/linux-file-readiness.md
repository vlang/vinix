# Native ordinary-file readiness

Ordinary regular files and directories now report Linux's default readiness
mask: POLLIN, POLLOUT, POLLRDNORM and POLLWRNORM. EOF, an empty file,
the description's access mode and its current offset do not suppress these
bits. Explicit resource readiness callbacks still take precedence. See the
[Linux 6.12 definition and fallback](https://github.com/torvalds/linux/blob/v6.12/include/linux/poll.h).

The `filepollfixture` V probe passes 3,840 AArch64 and 5,120 x86-64 checks
on native production Vinix kernels and identical static musl ELFs on Linux
6.12.51. Root and UID1000/GID2000 children exercise raw ppoll, musl ppoll/poll,
and raw x86-64 poll. Ten descriptions include unlinked files, readonly,
writeonly and mode-3 opens, directories, `/proc/version`, empty/populated
memfds and high-numbered file/directory aliases. Four empty/before-EOF/EOF/
beyond-EOF phases cover sixteen event masks, exact revents/return counts,
unchanged flags and buffer guards. Original kernels fail 1,920 AArch64 and
2,560 x86-64 checks. Every failure remains in the external bundle.

After warmup, each credential group repeats 200 complete poll cohorts.
All 18 ARM / 14 x86 live slab classes remain flat, with zero writes after
free. Large-page counts stay 63/63 on ARM and 160/160 on x86 for both
credential groups. The change adds no allocation or release operation.

The unchanged existing `selectready` probe also passes all 6,720 ARM and
8,960 x86 checks, including the ordinary-file cases previously failing in
[the ready-count qualification](linux-select-ready-counts.md). Its existing
socket cleanup cohorts stay flat. The tested worktrees start at `667833da2`
and explicitly snapshot the shared checkout's pending `pselect.v` ready-count
correction as a prerequisite; that correction is owned by another session.
No in-progress exec changes were imported. `snapshot.json` pins both changed
kernel inputs. V reports `0.5.2 ccb7729`; both builds use production mode,
LIMINE_MP=1, ALLOC_TRACK=0 and link seed 42. ARM uses 16 KiB pages and x86
uses 4 KiB pages.

Complete worktrees, generated C, build/compile receipts, kernel/probe ELFs,
Linux kernels, images, raw serial logs, source hashes and unsuccessful fixture
preparations are retained outside Git at:

`/Users/alex/.cache/vinix-linux-compat/filepoll-20261109`

`filepoll-evidence.v` audits the complete native/Linux result manifests,
probe/kernel identities, baseline failures and storage records and writes
`filepoll-artifacts.json` with SHA-256 checksums. `filepollcheck.self_test`
passes four positive and 2,414 missing/duplicated/altered/failure/retention
negative controls. The first native fixture attempt passed semantic checks
but failed because its heap parser used the wrong written-after-free line;
the corrected final fixture is `compile-{arm,x86}-r4`, run unchanged in
`native-{arm,x86}-r1` and `reference-{arm,x86}-r1`. Earlier evidence remains.

The manifest SHA-256 is
`8a3bd775f3b78ecac567669c5de281c637729ed9a7662041c5c74b2a44306cba`.

For fresh runs, compile `tests/linux-compat/run-filepoll.v` with the native
guest tool modules on V's module path, then supply `--arch`, `--kernel-dir`
and a fresh external `--state-dir`. It snapshots the kernel and fixture,
builds and boots the actual probe and validates its entire result manifest.
`filepoll-reference.v` runs the identical ELF on a supplied Linux kernel;
`--self-test` exercises the checker without a guest. Restore the full original
bundle before running `filepoll-evidence.v BUNDLE`.

This qualifies the listed native musl memory-backed descriptions. Disk-backed
files, concurrent mutation, O_PATH errors, epoll admission, cancellation and
GNU/foreign/32-bit paths remain separate. Section 15's three broad acceptance
gates remain open.

The [epoll follow-up](linux-epoll-file-admission.md) qualifies ordinary-file
refusals separately and preserves asynchronous pressure/pidfd readiness and
virtual-file admission through explicit callbacks.
