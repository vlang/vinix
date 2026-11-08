# Native epoll ordinary-file admission

`epoll_ctl` now rejects ordinary regular-file and directory descriptions with
EPERM before looking for an existing watch or retaining a new registration.
This covers ADD, MOD and DEL. Linux makes the same distinction between
[default poll readiness and a poll operation usable by epoll](https://github.com/torvalds/linux/blob/v6.12/fs/eventpoll.c).

Virtual filesystem callbacks preserve procfs, sysfs and cgroup-file admission.
Pressure subscriptions, pidfds and DRM PRIME descriptions have explicit
readiness callbacks, taking precedence over the ordinary-file default added
in `a6fdca2bd`. Pressure callbacks use their existing status locks; pidfds use
the existing atomic status word. The PRIME callback preserves its previous
status; DMA-BUF fence readiness remains unimplemented. The independent review
found no new heap allocation, reference transfer or locking problem. Generated
C uses the existing stack scratch for all eight callback types.

The V `epollfilefixture` uses ten tmpfs/memfd descriptions, including read-only,
write-only and mode-3 handles, directories, high aliases and unlinked files.
Root and UID1000/GID2000 exercise raw and libc calls with all three operations,
seven event masks and four file/offset phases. Every refusal preserves input
guards and descriptor flags, and every following epoll_wait sees an empty set.
The original kernels fail 4,160 of 6,720 checks on each architecture; identical
static musl ELFs pass Linux 6.12.51. The original fixture's `/proc/version`
expectation was wrong: Linux permits that watch. That failed reference is
retained; the corrected refusal fixture uses an ordinary nonblocking file.

Final production kernels pass all 6,720 checks on each native architecture.
Both credential groups' warmed 200-cycle refusal cohorts keep all 18 ARM /
14 x86 live slab classes flat, with zero writes after free and unchanged
63/63 ARM / 160/160 x86 large-page counts. The same kernels pass the four
asynchronous cohorts, all 1,256 masked-wait checks per architecture and the
3,840 ARM / 5,120 x86 ordinary-file checks with flat repeated storage.

The `pollasyncfixture` separately verifies independent global/cgroup pressure
subscriptions, duplicate acknowledgement, initial/consumed readiness, cgroup
limit-change notifications, proc/sys/cgroup virtual-file watches and live,
exited and reaped pidfds. Linux-specific pressure endpoints are a native
regression, not part of the Linux reference workload.

Evidence, source worktrees, full generated C, kernels, probe ELFs, receipts,
images and failed attempts are retained outside Git at:

`/Users/alex/.cache/vinix-linux-compat/filepoll-20261109`

The source base is `667833da2` with the ordinary-file fallback and the shared
checkout's pending select-count correction frozen as prerequisites. The latter
belongs to another session. In-progress exec changes are excluded. Production
builds use LIMINE_MP=1, ALLOC_TRACK=0, link seed 42, 16 KiB ARM pages and
4 KiB x86 pages. A private copy of V and its libraries prevents another
session's compiler replacement from changing final build inputs. Earlier
build receipts retain changed-input refusals and an intermediate object whose
timestamp masked newer V source; final builds force full regeneration.
The private compiler reports V `0.5.2 395d574`; its executable SHA-256 is
`4a2a1338076b2888cdf144bc5a5b83964557bfb1b6b0835414c34fb5e39b7ac3`.

`epollfile-evidence.v BUNDLE` verifies the full reference/native refusal
manifests, probe/kernel identities, original failures, asynchronous regression
records, complete masked-wait records and ordinary-file regression storage.
It writes the external `epollfile-artifacts.json` SHA-256 manifest. The refusal
parser passes four positive and 1,454 negative manifest controls. The V host
pressure runner passes both the policy and subscription test files, including
readiness dispatch through a real regular-file resource box:

```sh
v -cc cc run tests/memory-pressure/run.v /path/to/fresh-host-state
```

The complete audit passes both architectures. The manifest SHA-256 is
`71fa9c0120e4180b01bf346e0a18518ae0c4e66954c38b891c3da9945306082a`.
Final kernel receipts are `build-epoll-{arm,x86}-r4`; corrected refusal probes
are `compile-epoll-{arm,x86}-r2`, tested in `native-epoll-{arm,x86}-r1` and
`reference-epoll-{arm,x86}-r1`. Native asynchronous receipts use
`native-async-{arm,x86}-r1`; replays use `regression-*-{arm,x86}-final`.

For fresh refusal runs, compile `tests/linux-compat/run-epollfile.v` with the
native guest modules on V's module path and pass `--arch`, `--kernel-dir` and
a fresh external `--state-dir`. The reference controller accepts the identical
probe ELF, a Linux kernel and a fresh state directory. Restore the complete
original bundle before auditing these receipts.

Pass `--case pollasync` to the native controller for the pressure, virtual-file
and pidfd regression. The historical shell host-test entry now delegates to
the V runner and still honors `V` and `KEEP_TEST_TMP`.

O_PATH errors, general epoll error ordering, full virtual-file event semantics,
DMA-BUF fences, disk-backed qualification, concurrent close/registration and
GNU/foreign/32-bit paths remain separate. The broad section 15 acceptance
gates stay open.
