# Wine generation lease supervision proposal

Read-only audit on 2026-10-26 against Vinix source
`35f133e442c79004cd0127211734790d0d20f9cf` and upstream Wine 9.17. The
controller/current-CLI admission source remains at
`14abbc8a3ef793d090019251a33119a3b2615a7a` (integrated as `a464f1b6c`).
This is a proposed V implementation and qualification plan. No supervisor,
kernel fix, reproducer, target build or native run was added by this audit.
The two kernel findings below are static findings, not reproduced failures.

Follow-up: `tests/packages/wine-subreaper-probe.v` adds a native prerequisite
probe for SET/GET subreaper, double-fork adoption across a new session, saved
client status 37, adopted-worker status 23, a busy independent lease open
after client exit and release after worker retirement. A pipe gates the worker
without relying on a sleep to keep it alive; a 30-second alarm bounds blocking
operations. Descendants explicitly close the holder's lease descriptor.
Run the Linux executable with one fresh absolute external state directory.
The native controller `tests/packages/wine-subreaper-check.v` now compiles and
boots both architectures. Final `arm-07` and `x86-07` runs pass the positive
probe and a disabled-subreaper control which must detect missing adoption.
The probe runs outside PID 1 as uid/gid 1000 with no supplementary groups;
PID 1 adoption alone cannot satisfy the positive assertion. Explicit `i32`
pipe slots match C's descriptor ABI. Earlier production-build, missing GCC,
pipe-width and x86 boot/console failures remain retained. ARM uses the selected
musl-cross GCC runtime; x86 uses the existing plain-USTAR ISO helper and com1.
This is not race coverage or Wine lifetime acceptance.
The current clone-parent publication and exit adoption paths still require
the coordinated review and deterministic controls described below. No production
lease handling is changed by this probe.

The controller binds its embedded sources, discovers and admits actual parsed
guest V sources, records commands/generated C/QEMU arguments, and checks selected
tool/kernel/firmware/source hashes and generated artifacts before/after boot.
It does not inventory the complete C toolchain/sysroot, prove reproducibility,
measure kernel leaks or exercise pledge/unveil. Both selected kernels remain
unchanged from the earlier Wine pledge qualification. The successful runs end
with the fixture alive; guest shutdown is not qualified.

Complete raw attempts and source copies are retained at
`/Users/alex/.cache/vinix-wine-subreaper-20261112-01`.
The external typed inventory is
`/Users/alex/Library/Caches/vinix-codex/section14/wine-subreaper-20261112-01.inventory.json`,
SHA-256 `3329ea4f6ef815d110738f43e03c8f47ac9f5a5954ea1fcb9a4121626023fd83`.
Recording and separate complete verification use the maintained workspace
inventory tool from `845f18d93`; adjacent record/check logs retain results.
This is an in-place integrity seal; keep originals and historical namespaces.

The follow-up to `913a98e1a` adds a controlled nested-adopter transfer check.
An ordinary non-init outer subreaper starts an inner subreaper, which starts
a client and detached-session worker. After client status 37 is collected,
pipe handshakes require the worker's PPID to name the inner subreaper. Only
then does the outer send SIGTERM to the inner and require signal status 15.
A second handshake requires the worker's PPID to name the outer; worker
status 23 and a final ECHILD complete the check. Both waits use explicit
32-bit status slots, pipe operations retry EINTR, and alarms bound blocking
failure paths. This controls death after completed adoption, not death during
publication; neither publication-race finding below is resolved.

Fresh `arm-02` and `x86-02` runs pass this new required marker and the existing
lease/disabled-subreaper checks on the same unchanged selected kernels.
The first compile attempts failed because a helper parameter shadowed C's
write function; those attempts remain retained, alongside the final sources,
generated C, commands and run receipts, at
`/Users/alex/.cache/vinix-wine-subreaper-transfer-20261112-01`.
The complete typed inventory is
`/Users/alex/Library/Caches/vinix-codex/section14/wine-subreaper-transfer-20261112-01.inventory.json`,
SHA-256 `cc52e860b6b0eab86dc2edddf6d7276515db450828434f11192ffecc2c499118`.
Recording and separate complete verification pass with the same retained
inventory tool; originals remain required. Scope and toolchain limitations
above still apply. No production supervisor or kernel fix is claimed.

## Adoption publication coordination, 2026-11-13

The follow-up built from `7b8ed3db9` changes `kernel/userland/exit.v` so that
the process-table lock covers adopter selection, child PPID updates and child
list insertion. `claim_teardown` takes this same lock before setting `exiting`;
a selected live subreaper therefore cannot start teardown in the gap between
selection and insertion. `find_reaper_locked` borrows table entries while that
lock is held. The selected adopter is pinned before unlocking, retains that
pin through notification and releases it at the existing unpin site. Temporary
ancestor pins are no longer needed. The lock order is table then child list;
the wait/reap path releases its child-list lock before table operations.
The global PID-1 fallback and init-death behavior retain their existing scope.

Both kernels build in the isolated sparse worktree
`/Users/alex/.cache/vinix-adoption-kernel-20261113-01`, with dependency symlinks
to the original checkout. ARM succeeds in `arm-build-02.log`, x86 in
`x86-build-03.log`. Earlier missing-linker and sparse-generator dependency
failures remain retained. The saved kernels are `vinix-aarch64` and
`vinix-x86_64`; ARM generated C is saved separately before cleaning its objects
for the x86 build. The worktree retains x86 generated C and the exact patch.

`run-arm-01` and `run-x86-01` pass the unchanged native prerequisite controller
from the preceding nested-transfer qualification: ordinary non-init adoption,
busy/released lease, disabled-subreaper refusal and controlled nested transfer
after adopter signal death. Selected source/tool/kernel hashes and generated
guest artifacts pass their before/after checks. These are regression checks;
they do not deterministically force the former selection/publication window.
No kernel leak, full security/desktop or real Wine requalification is claimed.
The separate late `CLONE_PARENT` publication finding remains unchanged, so a
general descendant barrier and production lease supervision remain unqualified.

The complete typed worktree inventory is
`/Users/alex/Library/Caches/vinix-codex/section14/adoption-kernel-20261113-01.inventory.json`,
SHA-256 `c74b91879a0d9c12ea9e6105b5755cca295206112ef8909850461c2af422bf33`.
Recording and a separate complete check pass; adjacent logs retain both results.
This is an in-place integrity seal. Keep the worktree, original linked
dependencies, selected external compiler and historical namespaces. Link
targets are recorded; this is not a complete toolchain-content inventory.

## Existing contract and gap

[`generation_lease`](../../tools/packages/pkgcore/launch.v#L239) opens the
generation coordination file with `O_CLOEXEC`, takes a shared flock, and leaves
the caller owning that descriptor. Both ordinary launch paths close it when
their synchronous launch returns:
[`run_application`](../../tools/packages/pkgcore/launch.v#L221) and
[`PreparedLaunch.close`](../../tools/packages/pkgcore/service.v#L174).
[`run_launch_process`](../../tools/packages/pkgcore/launch_process.c.v#L53)
waits only its direct sandbox child and preserves its exit status and the
working-directory/exec failure record.

The Wine runner and nested aliases remain exec bridges. Wine may outlive the
first client through detached processes. The existing
[`wine-native` fixture](wine-native/main.v#L528) requires a busy lease at READY
and a free lease after observed processes retire, with PID1 assisting reaping.
It does not require the lease to stay busy after the client exits while the
server is still alive. A server version string or socket directory is not a
startup or lifetime proof.

## Smallest proposed launch API

Keep `run_launch_process(Launch)` and the shared parent process unchanged for
other launches. Thread the actual borrowed lease descriptor privately through
`run_leased_application`/`run_leased_mode` and the prepared service launch.
Only signed Windows launches would use a new
`run_leased_launch_process(Launch, lease_fd)`:

1. The caller retains its lease while forking one per-launch holder and waits
   for that exact PID. It never enables subreaping or waits for arbitrary
   children in the shared caller.
2. Before starting the sandbox child, the holder sets and reads back
   `PR_SET_CHILD_SUBREAPER`. Unsupported setup refuses before workload start.
   It never execs and retains its inherited lease descriptor. Its child closes
   that borrowed descriptor explicitly before sandbox setup.
3. Preserve the existing initial client status and fixed launch-failure record;
   collect the holder's own adopted descendants separately. After a qualified
   descendant barrier, return the saved client result, not the last daemon's
   result. This preserves the result but delays synchronous return until
   retirement. Earlier client-return timing would need a separately specified
   acknowledged result channel and holder-reaping policy.
4. Allocate argv/status storage before fork. The post-fork holder/child path
   must use bounded syscall/libc operations without V allocation or environment
   rebuilding. Catchable cancellation must not discard the lease while the
   workload remains alive; an unexpected wait error is not completion. After
   workload start, that failure must leave the holder alive with its lease
   rather than take an error return that closes the final descriptor. A
   bounded failure notification and recovery policy still need specification.

Vinix supports SET/GET subreaper in
[`container.v`](../../kernel/syscall/table/container.v#L387).
Fork preserves descriptor flags on
[x86_64](../../kernel/userland/clone_amd64.v#L225) and
[aarch64](../../kernel/userland/clone_arm64.v#L226), sharing the underlying
[`Handle`](../../kernel/file/file.v#L1030). `FD_CLOEXEC` closes at exec, not
fork ([x86_64](../../kernel/userland/userland.v#L529),
[aarch64](../../kernel/userland/userland_arm64.v#L1321)); sandbox setup also
[closes descriptors from 3 upward](../../tools/sandbox/core/native.v#L85).
Thus execing another helper cannot substitute for the non-execing holder.

Use explicit `i32` PID/status ABI storage and retry `EINTR`.
[`wait4`](../../kernel/userland/linux_task.v#L639) consumes a selected exit even
on status/rusage copyout failure; use a genuine writable stack status and null
rusage. Its locked [child scan](../../kernel/userland/linux_task.v#L502)
counts matching children not yet ready for reap. `ECHILD` means no matching
child in that list, subject to the publication findings below.

## Kernel prerequisites and abnormal death

Two publication paths prevent treating present-kernel `ECHILD` as a universal
descendant barrier:

- `CLONE_PARENT` selects an unpinned parent before setup, then appends without
  checking whether that parent has detached its children for exit
  ([x86_64 selection](../../kernel/userland/clone_amd64.v#L215),
  [append](../../kernel/userland/clone_amd64.v#L291),
  [aarch64 selection](../../kernel/userland/clone_arm64.v#L217),
  [append](../../kernel/userland/clone_arm64.v#L286)).
- [`find_reaper`](../../kernel/userland/exit.v#L510) pins a non-exiting
  subreaper, but [subsequent adoption](../../kernel/userland/exit.v#L262)
  appends without rechecking that it has not begun exit and detached its own
  list. The pin protects allocation lifetime, not adopter availability.

Both can leave a late child outside the ancestor's transferred list.
[`publish_user_thread`](../../kernel/sched/inherit.v#L54) does not repair parent
publication. A coordinated parent selection/adoption/exit fix and focused
kernel regressions are prerequisites; merely forbidding `CLONE_PARENT` does
not address the second finding. These paths are reachable for process-capable
packages: [`proc` promises](../../tools/packages/pkgcore/launch.v#L150) permit
process clone and SET subreaper
([pledge](../../kernel/syscall/table/pledge.v#L154)). This is not a claim that
every Windows launch grants those operations.

The holder can survive its caller's death, but cannot retain its own descriptor
after its own `SIGKILL`. [`exit`](../../kernel/userland/exit.v#L225) closes FDs
before child adoption; the final [`Handle.unref`](../../kernel/file/file.v#L140)
releases description locks. [Pidfds](../../kernel/proc/pidfd.v#L14) retain exit
identity/events, not the target's arbitrary FD table. No existing kernel
workload-linked lease-retention facility was found in this audit. Absolute
retention across holder death would require a separately designed kernel-owned
workload reference, inherited across fork/exec and released on actual final
member retirement. User-space holders alone must not claim this guarantee.

## Wine server ownership is a separate prerequisite

A managed launch should serialize its private prefix with a dedicated launch
guard, refuse an existing/foreign server, and start one owned direct foreground
server. Authenticate the live lock owner and connected Unix socket peer against
that unreaped child's identity and caller UID/GID, with prefix/server-directory
identity checks. Refuse unsupported locking, unexpected endpoints and bounded
startup failure without attaching to or killing a foreign server. Retain the
authenticated connected socket for the actual client.

Wine 9.17's
[`open_master_socket`/`acquire_lock`](https://github.com/wine-mirror/wine/blob/wine-9.17/server/request.c)
provide the foreground path. Its
[`server_init_process`](https://github.com/wine-mirror/wine/blob/wine-9.17/dlls/ntdll/unix/server.c)
consumes `WINESERVERSOCKET`, sets CLOEXEC and bypasses initial autodiscovery.
Keep nested aliases exec-only and preserve Wine's normal child handoff; qualify
any initial prefix/cwd setup skipped by this route. `wineserver -w` is
insufficient: its
[`main`](https://github.com/wine-mirror/wine/blob/wine-9.17/server/main.c)
ignores `wait_for_lock`'s result, which also reopens by pathname.

Wine's
[`spawn_process`](https://github.com/wine-mirror/wine/blob/wine-9.17/dlls/ntdll/unix/process.c)
double-forks and may create a new session, so PGID emptiness is insufficient.
[`process_sigkill` and `server_shutdown_timeout`](https://github.com/wine-mirror/wine/blob/wine-9.17/server/process.c)
also permit Wine bookkeeping retirement without independently confirming every
Unix process has died. Natural server exit complements, but cannot replace,
a qualified kernel descendant barrier.

## Proposed focused V qualification

First qualify the holder independently of Wine on each exact native x86_64 and
aarch64 kernel: SET/GET support; fork-versus-exec CLOEXEC; busy lease after
client exit with a live descendant and release after retirement; double-fork,
new session and rapid process churn; original status 37/126/127/signal and
cwd/exec errno; `EINTR`; pre-start setup refusal; unexpected wait failure;
caller death; two concurrent holders plus an unrelated caller child proving
no unrelated reaping. Kernel controls must cover both publication findings
without relying on probabilistic success. Holder death remains an explicit
limitation until a kernel retention facility is qualified.

Then extend the real signed Wine fixture with client-gone/server-live
collection refusal, authenticated foreground startup, busy/foreign-prefix
refusal, natural retirement and preserved original client result. Run the
complete existing packaged-Wine gate on both architectures; ARM translated
fork remains a separate prerequisite. Preserve exact source/compiler/kernel
inputs and complete results outside Git. The queued current-CLI diagnostic is
still selected-input evidence, not this future lifetime qualification.
