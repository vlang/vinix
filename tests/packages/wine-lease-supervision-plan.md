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

## Clone-parent publication coordination, 2026-11-13

The follow-up built from `9cb643dc2` removes early raw parent-table reads from
both architecture clone paths. Shared `userland/child_publication.v` selects
the parent only after descriptor/thread/TID setup, holding the process-table
lock through PPID assignment and child-list insertion. A CLONE_PARENT creator's
current parent is used if still live; otherwise the locked reaper lookup skips
exiting ancestors. No selected parent pointer escapes the lock. Ordinary clone
keeps the creator as parent; process teardown already waits for that creator's
active kernel thread. The existing creator fallback when no reaper exists and
init-death limitations remain. No workload-linked lease guarantee is added.

Both kernels build successfully in the isolated sparse worktree
`/Users/alex/.cache/vinix-clone-parent-20261113-01`, retaining build logs,
saved architecture kernels, ARM generated C, final x86 generated C, both
changed clone paths and the new helper. Generated C inspection confirms the
helper uses borrowed pointers and a stack pointer temporary for insertion;
it adds no per-call allocation beyond the existing child-list growth.

The expanded native prerequisite suite passes `arm-01` and `x86-01` in
`/Users/alex/.cache/vinix-clone-parent-probe-20261113-01`.
Eight paired ordinary/CLONE_PARENT rounds verify exact child PPIDs, creator
versus outer wait ownership, statuses 37/29 and final ECHILD. The previous
lease, disabled-subreaper and nested-transfer checks also pass. The controller
requires the new marker and retains parsed guest sources, generated C, commands,
kernel/tool hashes and before/after admission. These are behavior regressions;
they do not force exit during the original early-selection window, qualify
all clone flags/namespaces, measure kernel leaks or requalify real Wine.
Deterministic race controls and production Wine supervision remain open.

Complete in-place typed inventories, both recorded and independently checked:

- `/Users/alex/Library/Caches/vinix-codex/section14/clone-parent-kernel-20261113-01.inventory.json`,
  SHA-256 `fa1495150f4c093ff0f93d6b18ccdeb3eaeeaf7863d4569b00a374e35388d713`.
- `/Users/alex/Library/Caches/vinix-codex/section14/clone-parent-probe-20261113-01.inventory.json`,
  SHA-256 `6bb1a35787c5c14d260e3c47a10bc391fefcba10ad266a8251aec4340337f40d`.

Adjacent logs retain both passes. Keep both original workspaces and the linked
dependencies/tool namespaces; link targets are recorded without claiming a
complete toolchain-content inventory. The earlier sealed workspaces are intact.

## Deterministic publication interleavings, 2026-11-13

Starting from `596f48829`, the maintained
`tests/packages/parent-race-probe.v` and `parent-race-check.v` force both
publication windows in explicitly instrumented kernels. PID 1 arms a gate
for one target PID, waits for its paused phase, kills and reaps the selected
parent, and only then releases publication. Targets run as uid/gid 1000
without supplementary groups and must be refused access to the gate control.
The clone case checks a CLONE_PARENT child's PPID and exact wait ownership.
The adoption case pauses an exiting process after its child-list detachment,
retires its former adopter, then checks its worker's PPID and wait ownership.
Statuses 37/23 and final ECHILD are required. Pipe handshakes establish the
ordering; sleeps only poll the explicit phase and do not select the race window.

The gate exists only with `-d parent_publication_fixture`. Its private prctl
operation `0x56585041` accepts only global PID 1, retains scalar PID/mode/phase
state, and pauses without process-table or child-list locks. A 20-second gate
deadline, target alarms and the controller's 90-second deadline bound failure.
The current protocol waits for target completion before rearming. Rearming
immediately after release, before the paused caller observes it, is unsupported.

Two deliberately unsafe-order controls require the outer fixture flag:
`-d parent_clone_old` caches the parent before the pause and publishes afterward;
`-d parent_adopt_old` releases the table lock after selecting/pinning an adopter,
pauses, then inserts into that cached adopter. Pins keep retired objects alive,
isolating lost publication from a use-after-free. These are controlled ordering
mutations, not byte-identical historical kernels. An independent read-only
lifetime review approved their pin/unpin and lock ordering; its notes are retained.

For each architecture, build the fixed fixture, both controls and a default
kernel in an isolated worktree. Force V regeneration when changing flags with
`make ... -W userland/child_publication.v`; the general build stamp does not
encode arbitrary VFLAGS. The controller takes:

```text
CHECK FRESH_OUTPUT ARCH KERNEL SYSROOT GCC_INSTALL CLANG V fixed
CHECK FRESH_OUTPUT ARCH CLONE_CONTROL SYSROOT GCC_INSTALL CLANG V clone-refused
CHECK FRESH_OUTPUT ARCH ADOPT_CONTROL SYSROOT GCC_INSTALL CLANG V adopt-refused
```

The fixed mode requires both passing race markers. Control modes require a
noninterrupted guest refusal at exactly `clone child wait ownership` or
`adopt child wait ownership`; other failures and unexpected success refuse.
The selected expectation is retained before generated-artifact admission.
Final `arm-fixed-run-03` and `x86-fixed-run-03` pass; each architecture's
`clone-old-run-03` and `adopt-old-run-03` fail at their intended guest gates
and pass the host's corresponding negative-control check. Both default kernels
build, contain no fixture/control function symbols in generated C, and pass
the preceding ordinary subreaper/clone suite in `*-production-run-01`.

The isolated kernel worktree is
`/Users/alex/.cache/vinix-parent-race-kernel-20261113-01`.
Build logs, all eight saved kernels and generated C, final source copies,
guest runs, commands, expectation/result files, parsed guest source admission
and review notes are at `/Users/alex/.cache/vpr-20261113-01`. Earlier failed
build/run logs remain retained, including filename exclusion, global-name
collision and scalar mutable-argument corrections. Host input/output checks
pass for all final runs. Complete in-place inventories are recorded and
independently checked with the existing maintained V inventory tool:

- `/Users/alex/Library/Caches/vinix-codex/section14/parent-race-kernel-20261113-01.inventory.json`,
  SHA-256 `bd4ec8adbfd79f1e4b29e9d30f893e1bc69104b54b5cb7a3cc394c123d33c7f2`.
- `/Users/alex/Library/Caches/vinix-codex/section14/parent-race-runs-20261113-01.inventory.json`,
  SHA-256 `d89c7fcf54682112dff287ef5863f3bd782d00a6da61aff092b2440de929ca3c`.

Keep the complete original workspaces, linked dependencies and tool namespaces.
This qualifies these two forced publication orderings and their controls, not
all process/namespace races, init death, kernel leak freedom, complete C
toolchain contents, real Wine supervision or roadmap section 14 completion.

## Standalone holder primitive, 2026-11-13

Following `4a1457330`, `tools/packages/launchhold` adds a standalone synchronous
holder for the qualified Linux AMD64/AArch64 static toolchains. It is not wired
to package or Wine launch paths. The caller supplies an already verified shared
generation lease with CLOEXEC above standard streams, keeps its arguments and
lease valid, and must not unlock/reuse the lease or let another waiter collect
the holder. Default waitable SIGCHLD policy is required throughout the call;
ignored/custom handlers and SA_NOCLDWAIT refuse before workload creation.

The parent prepares argv/status storage, blocks the calling thread's full
kernel signal mask before `_Fork`, then immediately restores its own mask.
The private non-execing holder enables/read-checks subreaping, closes unrelated
descriptors using close_range, starts the client and retains the borrowed
lease copy until the original client and adopted descendants retire. Only the
holder collects arbitrary children; its caller waits for its exact holder PID.
The client closes the lease, resets caught signal dispositions before unmasking,
preserves ignored dispositions and restores the caller's mask before chdir/exec.
Raw kernel signal/wait/write/close/poll operations avoid inherited libc
cancellation state, and `_Fork` bypasses user pthread_atfork callbacks.
Generated C and independent read-only lifetime review confirm stack-only
post-fork records without V allocation/formatting or environment reconstruction.

The normal result preserves the initial client status, separately from cwd/exec
failure records. Unexpected waits retain the lease and retry with one diagnostic
attempt to stderr. This is a fail-closed primitive, not a complete recovery UI.
The caller's lease descriptor remains open and its subreaper state is unchanged.
SIGKILL of the holder remains outside the guarantee: no kernel-owned workload
reference is added. Wine prefix serialization, authenticated foreground server
ownership, descriptor handoff, caller wait ownership and production recovery
still need integration/qualification before enabling this for signed Wine.

`tests/packages/lease-holder-check.v` compiles/admit-checks actual parsed guest
sources, records literal commands and selected tools/kernels, and verifies
generated artifacts and source hashes before/after boot. It runs with:

```text
CHECK FRESH_OUTPUT ARCH KERNEL SYSROOT GCC_INSTALL CLANG V standard
CHECK FRESH_OUTPUT ARCH KERNEL SYSROOT GCC_INSTALL CLANG V fault
CHECK FRESH_OUTPUT ARCH KERNEL SYSROOT GCC_INSTALL CLANG V signal
CHECK FRESH_OUTPUT ARCH KERNEL SYSROOT GCC_INSTALL CLANG V signal-refused
```

Both architectures pass final `*-standard-05`: statuses 37/126/127/143,
double-fork/setsid adoption, retained lease after caller death, catchable holder
cancellation, lease-free workload descriptors, unrelated-lease retirement and
both low/high descriptor orderings. Registered at-fork callbacks demonstrably
run for a calibration child and are skipped by the holder; that unrelated child
remains the caller's to reap. Ignored SIGUSR2 survives exec. Caller mask/reaper
state and its borrowed lease remain intact. Ten refusal cases cover missing
cwd/executable, invalid/inheritable leases, process/FD exhaustion and unwaitable
SIGCHLD policies, including mask restoration after fork failure.

Both `*-fault-05` runs force persistent EIO after initial-client collection,
kill the caller, and require the lease to remain busy after worker retirement.
Exactly one diagnostic is retained; the fixture explicitly kills/reaps the
control holder and adopts its unreaped worker for cleanup. Both `*-signal-05`
runs inject a caught signal immediately after the first fork and before child
unmask/exec; the holder stays protected and the client returns the default
signal status. `*-signal-refused-05` preserves caught handlers deliberately and
must refuse at exactly `inherited handler ran before exec`. Injection branches
require `lease_holder_fixture` plus their mode flags. A macOS compile/unit run
also passes the unsupported-host refusal. The saved production kernels from
the preceding publication-race gate are unchanged; no kernel rebuild was needed.

Initial review found the inherited-handler window; it was fixed and re-reviewed
before final qualification. Earlier standard-02/fault-02 successes predate that
fix and are superseded. Failed compile logs, preliminary runs, review notes,
final source copies, all generated C/binaries/commands and the eight final runs
remain at `/Users/alex/.cache/vlh-20261113-01`. The complete in-place inventory
is `/Users/alex/Library/Caches/vinix-codex/section14/lease-holder-20261113-01.inventory.json`,
SHA-256 `334faa96655a4735d9c5a35f91bb5520d8c665d3ee8f777b9e81d78457c31c89`.
Recording and separate complete verification pass; adjacent logs retain results.
Keep the original workspace and input namespaces. This is local primitive
qualification, not a complete C toolchain inventory, hermetic build, leak
measurement, package sandbox acceptance or real Wine supervision qualification.

## Standalone prefix launch guard, 2026-11-13

Source `49015cd1c` adds `Prefix.acquire_launch(data)` and the owned
`wineadapter.LaunchGuard` primitive. It duplicates captured data/prefix directory
descriptors with CLOEXEC, opens `.vinix-managed-launch` without following links,
requires an empty ordinary single-link file owned by the effective UID/GID with
mode 0600, and takes a nonblocking exclusive flock. Unsupported locking and
contention refuse. Every partial acquisition closes its owned descriptors.
The guard survives `Prefix.close`, supports idempotent close, and leaves the
coordination file in place. Removing a live flock file could split ownership.

`recheck` reopens the canonical data path and compares directory and guard-file
identities and policy with the held descriptors. This coordinates cooperating
managed launchers; arbitrary same-account programs can still replace paths or
bypass advisory locking. Rechecks detect replacements at their boundaries,
not continuously. The primitive neither authenticates a Wine server nor changes
`wine-runner`, nested aliases or the generation lease holder.

The shared maintained V fixture runs under an ordinary macOS account and as
uid/gid 1000 in native ARM64/x86_64 guests. Final `arm-05` and `x86-05` pass
independent-open and child-process contention, independent guard ownership,
close/reacquire, retained coordination file, 1,000 repeated acquisitions and
refusals, malformed modes/content/hardlinks/symlinks/FIFO/directory refusal,
data/prefix/guard replacement, permission changes and restoration/retry.
Native exec checks find no descriptors above standard streams within the
process descriptor limit. Descriptor counts remain flat after the repeated
operations and refusal paths. Host normal/production heap controls retain zero
V bytes across the repeated operations; address/undefined sanitizers and the
existing prefix regression also pass. This does not measure kernel allocations.

The controller uses the preceding gate's unchanged production kernels, admits
actual parsed guest sources, and verifies selected source/tool/kernel/firmware
and generated artifact hashes before/after boot. Commands, generated C, serial
logs, earlier failures, final source copies and ownership self-review remain at
`/Users/alex/.cache/vwg-20261113-01`. The complete typed in-place inventory is
`/Users/alex/Library/Caches/vinix-codex/section14/wine-launch-guard-20261113-01.inventory.json`,
SHA-256 `af38424d5581714d17ae3d58a626347631cee7c6bc832d308f46b4bfc3004f23`.
Recording and separate complete verification pass with adjacent logs. Preserve
the original workspace and historical input namespaces. This is selected-input
primitive qualification; complete toolchain inventory, sandbox acceptance,
authenticated foreground server startup/socket handoff, production Wine lease
coverage and retention across holder death remain open.

## Server identity prerequisite, 2026-11-13

Source `2662d54e0` adds the observational
`wineadapter.verify_server_identity(socket_fd, lock_fd, child)` primitive for
Linux AMD64/AArch64. The caller borrows both CLOEXEC descriptors and exclusively
owns the direct, unreaped child with default waitable SIGCHLD throughout the
call. Nonblocking `waitid` with WNOWAIT checks that child before and after
inspection without consuming its status. F_GETLK must identify that child as
the first-byte POSIX write-lock owner; the connected Unix stream's SO_PEERCRED
must identify the same PID and effective UID/GID. Terminal poll states refuse.
The first-byte lock matches the inspected
[Wine 9.17 server](https://github.com/wine-mirror/wine/blob/wine-9.17/server/request.c).
No socket protocol bytes are consumed, locks changed, descriptors closed or
processes signalled. The caller must prevent other waiters or descriptor reuse;
numeric PIDs alone do not establish this ownership contract.

Final `arm-03` and `x86-03` native runs pass under uid/gid 1000. Two child-owned
listeners and locks prove acceptance and distinct live peer/lock-owner mismatch
refusals. Queued protocol data survives 1,000 successful checks with zero
retained V allocations and flat complete current-limit descriptor counts.
Named refusals also cover invalid/equal descriptors, invalid/self/nonchild PIDs,
regular-file/datagram/unconnected peers, missing CLOEXEC, unsafe lock mode,
ignored SIGCHLD/SA_NOCLDWAIT, unlocked/read-locked files and disconnected peers.
Exited-child refusal leaves status 23 collectible; reaped children refuse too.
The ordinary macOS host check passes the unsupported-platform refusal only.

`tests/packages/wine-server-identity-check.v` uses the preceding gate's unchanged
production kernels. It admits actual parsed guest V sources, explicitly hashes
the repository heap-tracker header, and checks selected executable, firmware,
kernel and generated artifact hashes before/after boot. Raw commands, generated
C, logs, earlier failed compiles, final sources and ownership self-review remain
at `/Users/alex/.cache/vwi-20261113-01`. Complete typed inventory:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-server-identity-20261113-01.inventory.json`,
SHA-256 `ba409af8c195f1b4d398bd920e2dc2f72bafe7e0dce27ec83f4206801b5c4a25`.
Recording and separate verification pass with adjacent logs. Preserve originals
and historical input namespaces. The raw validation note's standard-descriptor
category is broader than the fixture: descriptors 0–2 are not separately tested.
Foreign UID/GID variants, AF_INET peers, injected kernel failures, mid-check
exit interleavings and kernel heap retention are also outside this gate.

This qualifies a V fixture, not a real Wine launch. Signed foreground startup,
captured/rechecked prefix/server-directory/lock/endpoint identities, refusal of
pre-existing servers, bounded connect, retained socket handoff and generation
lease integration remain open. It changes neither `wine-runner` nor the holder.

## Server directory capture, 2026-11-13

Source `00215ed4e` adds `LaunchGuard.prepare_server_directory(data)` and the
owned `ServerDirectory` capture. It derives Wine's private UID/device/inode
namespace from the held prefix descriptor, opens directories without following
links, requires account-owned mode 0700 directories and retains an empty,
single-link account-owned mode 0600 lock file with CLOEXEC. Real/effective UID
and GID must match. Preparation and rechecks keep the existing launch guard
live; closing the Prefix alone does not invalidate them. Close frees owned
strings/descriptors and retains Wine's files and directories.

`recheck` compares the held base/server directory and lock identities against
fresh descriptor-relative opens, with upstream guard checks. `require_idle`
also requires an unlocked first byte and an absent `socket` entry before a
future startup. Any existing entry, including a dangling link or real Unix
socket, refuses without being removed or rewritten. Lock inspection errors
refuse too. Callers must hold no POSIX record locks on that file: F_GETLK
ignores their own locks, and closing another descriptor could release them.
Namespace-only rechecks intentionally permit a running server's lock/socket.
This does not reserve the namespace against noncooperating same-account code;
rechecks and idle checks are observations at their respective boundaries.

The shared maintained fixture passes final `arm-02`/`x86-02` under uid/gid 1000,
plus ordinary macOS normal/production heap controls and address/undefined
sanitizers. Each heap-enabled run retains zero V bytes over 1,000 successful
capture/recheck/close cycles and 1,000 refused endpoint captures. Descriptor
counts stay flat after success/refusal paths and return to their initial count
after all captures close. A pipe-gated foreign child holds the real POSIX lock;
preflight/capture refuse without releasing it, then accept after status 23 is
collected. Other refusals cover malformed lock types/content/modes/hardlinks,
directory symlinks, permission/special-bit changes, base/directory/lock
replacement, closed captures and closed guards. Restoring original identities
permits retry. The generated C keeps temporary records on the stack; the account
check returns no scalar result to avoid the qualified compiler's observed
escape-analysis boxing. Earlier failed heap controls remain preserved.

The controller admits actual parsed guest V sources, explicitly hashes the
repository heap tracker, and verifies selected tools/kernel/firmware and
generated artifacts before/after boot. Complete attempts, final sources and
ownership self-review remain at `/Users/alex/.cache/vwd-20261113-01`. Typed
inventory:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-server-directory-20261113-01.inventory.json`,
SHA-256 `f79c4c8f8e86970716ba1e7e84e4a8156037495a450449517415b4f7bc897d6a`.
Recording and independent complete verification pass with adjacent logs.
Preserve original bundles and historical input namespaces. Full C toolchain
inventory, kernel heap retention, sandbox acceptance and concurrent mutation
interleavings are outside this gate. Signed foreground startup, endpoint
identity capture/authenticated socket handoff, generation lease integration and
holder-death recovery remain open; runner and holder behavior is unchanged.

## Endpoint metadata capture, 2026-11-13

Source `09e5ed998` adds `ServerDirectory.capture_endpoint(guard, data)` and the
owned `ServerEndpoint` for Linux. It holds an O_PATH/CLOEXEC reference to the
`socket` inode plus an independently duplicated parent directory descriptor.
It requires an account-owned single-link socket with mode 0600; O_PATH with
O_NOFOLLOW captures a symlink itself so the type check refuses it. Rechecks
validate the enclosing namespace, captured parent and current socket inode.
An inode moved into a different captured prefix refuses at the parent-identity
gate. Close releases only the two owned metadata references and is idempotent.

Final fixture source `663e0f7e6` passes `arm-01` and `x86-01` in the second
series, outside PID 1 as uid/gid 1000. A child owns the real Unix listener and
first-byte record lock. Both 1,000 successful capture/recheck/close cycles and
1,000 unsafe-mode refusals retain zero V bytes; descriptor counts stay flat and
return to the initial count after all objects close. Original queued protocol
bytes survive. Fresh connections with matching child/lock/peer identities
still succeed after repeated metadata closes and after the ServerDirectory
closes while independent metadata remains. The reverse lifetime control keeps
a metadata capture open while the actual listener child exits with status 0;
a new connect must then fail with ECONNREFUSED before the metadata closes.

Refusals cover missing nodes, wrong mode, hardlinks, symlinks/dangling links,
ordinary files, FIFO/directory entries, a different well-formed socket inode,
removed endpoints, replacement directories, closed captures and closed parents.
Restoring original identities permits recheck. A fresh capture of a correctly
formed non-listening replacement deliberately succeeds: metadata capture alone
does not authenticate an owned/live server or connect the client. This remains
an observational namespace prerequisite, separate from startup and peer checks.
The macOS host check qualifies unsupported-platform capture refusal only.

The controller admits actual parsed guest V sources, explicitly hashes the
repository heap tracker and verifies selected tools/kernel/firmware and generated
artifacts before/after boot. Production kernels from the preceding gate remain
unchanged. First-series sources/results and host check remain at
`/Users/alex/.cache/vwe-20261113-01`, with complete typed inventory
`/Users/alex/Library/Caches/vinix-codex/section14/wine-server-endpoint-20261113-01.inventory.json`,
SHA-256 `1cfc4154251cf034d95991ad7116bd2e4c63f039b92495a42d246ba812694ac0`.
Final sources, generated-C ownership self-review and both complete final runs
are at `/Users/alex/.cache/vwe-20261113-02`; inventory
`/Users/alex/Library/Caches/vinix-codex/section14/wine-server-endpoint-20261113-02.inventory.json`,
SHA-256 `ae498805500895f409d38bcef5463a225296c7a3a3d24dd2fb4ea194817a9e27`.
Both recording and separate complete verification pass with adjacent logs.
Keep both workspaces and historical input bundles. Full C toolchain inventory,
kernel heap retention, credential-change/fault injection, concurrent namespace
interleavings, sandbox acceptance and real signed Wine startup are outside this
gate. Signed foreground startup, bounded authenticated connect and retained
socket handoff, generation lease integration and holder-death recovery remain
open. Neither the runner nor holder is enabled or changed by this prerequisite.

## Authenticated retained connection, 2026-11-13

Source `25084430a` adds `ServerEndpoint.connect` and owned `ServerConnection`
for Linux AMD64/AArch64. It checks the expected direct unreaped child and lock
owner before contact, duplicates the endpoint metadata, and connects through
the retained O_PATH descriptor's `/proc/self/fd` link. It does not fall back to
the canonical pathname or change the launcher's cwd. Authorized procfs descriptor
links are a prerequisite; sandbox access has not yet been qualified. After
connecting it rechecks namespace, child, lock and peer identity. The returned
protocol socket is blocking with CLOEXEC, and its independent metadata survives
closing the original endpoint capture. Close releases three owned descriptors
without signalling or reaping the server. The caller must retain exclusive wait
ownership and default waitable SIGCHLD; explicit client inheritance is separate.

The socket retry/poll budget is 1–5000 ms, excluding filesystem latency.
Final `arm-02` and `x86-02` pass under ordinary uid/gid 1000 with the unchanged
production kernels. A relative-binding child serves beneath a pathname longer
than 108 bytes; parent cwd remains unchanged. A forced replacement control
connects to the original held inode while its old pathname names a foreign
listener. The connector refuses the stale capture and independently rejects
the newly captured foreign listener's peer, despite the expected child still
holding the lock. The refused foreign fixture remains responsive and drains
the connection without receiving client protocol bytes.

Both 1,000 connect/recheck/greeting/close/drain cycles and 1,000 unlocked-owner
refusals retain zero V bytes. Descriptor counts remain flat through success,
foreign-peer and backlog-timeout paths, then return to their initial count.
Five queued clients fill the configured backlog; a sixth with a 50 ms budget
must time out after at least 50 ms and before five seconds. Invalid budgets,
closed objects and retired children refuse; original child status 37 remains
collectible. The retained socket keeps CLOEXEC and restores blocking mode.
The existing peer suite also passes final `identity-arm-02`/`identity-x86-02`
after the shared owner-check refactor. The macOS host check covers unsupported
platform refusal only. This is a V protocol fixture, not real Wine handoff.

The controllers admit actual parsed V sources and the repository heap tracker,
and verify selected tools/kernel/firmware and generated artifacts before/after
boot. Complete attempts, final sources and generated-C ownership self-review
remain at `/Users/alex/.cache/vwc-20261113-01`; typed inventory:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-server-connection-20261113-01.inventory.json`,
SHA-256 `1761a6733bbb88b8bd44cccf6e16ed1ba5c10d62a95c519518c34e91d78cce9e`.
Recording and separate complete verification pass with adjacent logs. Preserve
original bundles and historical namespaces. Full C toolchain inventory, kernel
heap retention, injected pending-connect/poll/signal failures, descriptor
exhaustion and arbitrary concurrent mutation remain outside this gate. Signed
foreground spawning, actual client descriptor inheritance and Wine bootstrap,
sandbox qualification, generation lease integration and holder-death recovery
remain open; the runner and holder are unchanged.

## Owned server child primitive, 2026-11-13

Source `9c9fce18b` adds `ServerDirectory.start_child` and `ServerChild` for Linux
AMD64/AArch64. Idle namespace admission precedes a direct `_Fork`; the child
starts in the held prefix directory and closes descriptors above stdio except
its CLOEXEC exec-report pipe. Arguments and environment are borrowed/inherited;
the caller still admits the executable/environment and supplies foreground
arguments. No implicit daemonization, signed-binary claim or readiness claim
is made. Exec-report EOF can also result from pre-exec signal death: live
child/lock/peer authentication remains necessary.

The owner preserves default waitable SIGCHLD, excludes other waiters, copying
and asynchronous cancellation, and collects or explicitly terminates the child.
Nonblocking report/collection calls retain ownership on error. Termination
checks direct unreaped ownership with WNOWAIT, signals only that PID and waits
exactly it; its wait is unbounded and does not collect descendants. Parent mask
restoration failure returns an owned child with a pending saved mask rather
than losing the PID. Call `exec_ready` immediately on the spawning thread to
restore/check it; collection/termination also retry restoration. Cleanup of a
cancelled owner outside these calls remains the caller's responsibility.

Final `check-05` passes eight native runs with unchanged production kernels:
`arm-05`/`x86-05`, plus `signal-`, `close-` and `mask-` controls on each arch.
Ordinary uid/gid 1000 executes 100 spawn/exec/collect cycles with zero retained
V bytes and flat descriptors in both standard and mask-recovery runs. Execed
children check literal/empty arguments, prefix cwd, account, descriptor isolation
and inherited signal policy. Forbidden atfork callbacks never run. Natural
exit 37, repeatable exec failure/exit 126, owned termination 137 and pre-exec
SIGTERM/143 preserve exact status; an unrelated child remains alive. The signal
control verifies caught handlers reset before unmasking; the close control
injects isolation refusal before close_range; the mask control skips the first
parent restore and exercises recovery. Generated C confirms the injected mask
branch and allocation-free child path; raw report read/wait/close avoid libc
cancellation points. The host check covers macOS refusal/empty PID only.

An execed V server takes the Wine lock and serves a retained authenticated
connection using the owned PID, then retires naturally. Existing lock/endpoint,
invalid arguments, ignored SIGCHLD and NOCLDWAIT refuse without replacing a
foreign entry. PID1 observes exact suite status zero before its final marker;
the harness stops QEMU afterward. This is a protocol fixture, not signed Wine.

The controller admits actual parsed V sources and heap-tracker header, and
checks selected tools/kernel/firmware and generated artifacts before/after boot.
Complete attempts, final sources and ownership self-review are retained at
`/Users/alex/.cache/vsc-20261113-01`; complete typed inventory:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-server-child-20261113-01.inventory.json`,
SHA-256 `0c89a54afde5854497d6f728fd6459928a14e2b391f643548b22a13acb189046`.
Recording and separate verification pass with adjacent logs. Byte-verified
sparse media and APFS kernel clones preserve logical contents and original
paths; historical bundles remain intact. Full C toolchain inventory, kernel
heap retention, resource exhaustion, sustained mask-restore failure and arbitrary
signal/namespace/wait races remain unqualified. Signed Wine foreground startup,
translator/sandbox acceptance, client socket inheritance/bootstrap, generation
lease integration and holder-death recovery remain open. Runner/holder wiring
is unchanged.

## Bounded server readiness, 2026-11-13

Source `3f4d42bbd` adds `ServerChild.await_connection`. It polls exec status,
unreaped child liveness, namespace continuity and the Wine lock, then captures
and authenticates the endpoint with the existing retained connector. Foreign
lock owners refuse even before a socket appears; an endpoint without the owned
lock refuses too. Ownership is re-read when a socket appears, allowing the
child's legitimate acquire/bind transition between observations. A single
1–5000 ms budget covers polling/connect waits, excluding filesystem latency and
scheduling guarantees. Global deadline overrun closes a newly returned socket.
Every outcome preserves caller ownership of the child; the operation neither
signals nor collects it. Existing exclusive-wait/SIGCHLD/cleanup contracts apply.

Final controller `check-02` passes native `arm-03` and `x86-02` with unchanged
production kernels and ordinary uid/gid 1000. Each runs 100 complete
spawn/await/greeting/close/collect cycles and 100 pending timeouts with zero
retained V bytes and flat descriptors. A 20 ms timeout takes at least 20 ms
and less than five seconds, preserving the live PID; that same child can then
start and authenticate successfully. The returned socket is blocking/CLOEXEC
and preserves the greeting. Foreign entry/lock, unsafe mode and replaced prefix
refuse while children remain live. Retired/failed children refuse without
consuming exact statuses 37/126. Invalid budgets refuse. Caller cwd, configured
signal mask and descriptor counts remain intact. PID1 collects suite status
zero before its final marker; the harness then stops QEMU. The macOS host
check covers unsupported refusal only.

Generated-C review found fallible-scalar escape boxing in the first readiness
frame. A void exec-check helper keeps owner/stat/endpoint/connection values on
the stack; the final native allocation checks pass. Fixture cleanup now frees
only borrowed argument-array buffers. The initial failed run and a separate
ENOSPC preboot attempt are retained. Reconstructed initial sources match their
original input pins; final sources and ownership notes are also retained.

Complete workspace: `/Users/alex/.cache/vsr-20261113-01`; typed inventory:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-server-readiness-20261113-01.inventory.json`,
SHA-256 `36d6048c9e7bb6d85ef7496a3480cd7a3b926c33035cdf2da146c2208530c716`.
Recording and separate complete verification pass with adjacent logs. Actual
parsed V sources and heap tracker are admitted; selected tool/kernel/firmware
and generated artifacts are checked before/after boot. Byte-verified sparse,
cloned and filesystem-compressed own artifacts retain their logical contents;
keep all originals and historical namespaces. Full C toolchain inventory,
kernel heap retention, injected syscall failures and deterministic internal
lock/bind or arbitrary namespace interleavings remain unqualified. These are V
protocol fixtures. Signed Wine/translator/sandbox startup, actual client socket
inheritance/bootstrap, generation leases and holder-death recovery remain open;
the production runner and holder are unchanged.

## Bridge environment boundary, 2026-11-13

Source `3f0b67a8d` changes the production runner to call
`wineadapter.clear_bridge_overrides` before setting its canonical runtime
environment. Top-level `wine-runner` removes inherited `WINESERVERSOCKET` so
inherited state cannot select its server connection. Nested `wine`, `wine64`
and `wineserver` aliases preserve Wine's handoff value exactly, including absence
and empty values. The helper never parses or closes a descriptor named by that
variable. Existing loader/translator/Wine overrides still clear for all roles;
unsetenv failures now stop launch. Unknown roles refuse before any mutation.
Call only in the launching process without concurrent environment mutation.

Final `controller-02`/`matrix-01` passes normal, production and ASan/UBSan host
checks with zero retained tracked V bytes across 1,000 preserve/clear cycles.
Cases cover empty, numeric, opaque and oversized top-level values; byte-exact
nested handoff; all eight override variables; unrelated SDK identity; unknown
role refusal; and borrowed descriptor liveness/CLOEXEC flags. Fixture environment
values are restored, including absence/empty distinctions. Explicit panic guards
remain active under `-prod`. Both actual Linux production runner targets build
as static ARM64/x86_64 ELFs; generated C contains the new helper call. These
binaries were not booted, packaged or signed. Existing signed packages keep
their original runner until rebuilt.

The controller admits actual parsed V sources, binds embedded test/helper/runner
sources, and verifies selected compiler/header and generated output hashes.
Commands, generated C, executables, logs, receipts and final sources remain at
`/Users/alex/.cache/vbe-20261113-01`; complete typed inventory:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-bridge-environment-20261113-01.inventory.json`,
SHA-256 `f89f8a33cfb43381ad90deae1f39752a4e5f0ac4acef435d588bae456829ce46`.
Recording and separate verification pass with adjacent logs. Preserve the
complete workspace and historical bundles. Full C toolchain/compiler-environment
inventory, libc environment allocation retention, injected unsetenv failure and
Linux/Wine execution are outside this gate. Future managed launch must clear
inherited state first, then install its owned authenticated socket only in the
initial client's handoff environment. Signed foreground startup, actual socket
inheritance/bootstrap, generation leases and holder-death recovery remain open.

## Authenticated client descriptor handoff, 2026-11-13

Source `3e5d64d34` adds `ServerConnection.start_client` and owned `ClientChild`.
It rechecks connection/namespace/server identity, prebuilds argv and explicit
envp, replaces all supplied `WINESERVERSOCKET` entries with the owned FD, then
forks a direct client. The child starts in the captured prefix and retains only
stdio, protocol socket and CLOEXEC report; only its socket clears CLOEXEC before
execve. The manager raw-closes its socket and both metadata references before
unmasking, leaving the original connection closed. Pre-fork errors preserve it;
after successful fork, even exec failure returns an owned, waitable client.
Other command/environment admission remains the caller's responsibility. This
API does not provide descendant retirement or generation leases.

Final `check-01` passes `arm-01`, `x86-01`, `signal-arm-01` and `signal-x86-01`
with unchanged production kernels and ordinary uid/gid 1000. Normal runs each
complete 100 server/connect/client-exec/collect cycles with zero retained V
bytes and flat parent descriptors. The client receives exactly one descriptor
above stdio, reads the untouched queued greeting and exits 42; server EOF and
status 37 establish that no manager transport copy remains. The client restores
CLOEXEC after consumption, checking the intended Wine-style FD step only.
Literal/empty arguments and explicit environment survive; stale duplicate socket
entries disappear and parent-only variables are absent. Parent environment,
configured mask and unrelated non-CLOEXEC descriptor remain intact.

Invalid command/environment and nonblocking sockets refuse before fork without
consumption. Missing client exec reports stage 4/status 126 and releases the
transport. Pending caught SIGTERM before child setup produces default status
143, not the old handler's 89, while server status remains 37. Forbidden atfork
callbacks never run. Exec-report EOF alone still proves neither exec nor
liveness. Exclusive waits, default SIGCHLD, single ownership and cancellation
contracts apply. Generated C confirms stack ABI records, allocation-free child
setup, prebuilt pointer buffers and parent cleanup; all post-fork parent closes
use raw syscalls. The host test covers macOS refusal only.

Source `5f8a5f071` also makes the macOS ARM harness clone fresh firmware-variable
stores with copy-on-write where available, retaining ordinary-copy fallback for
unsupported/cross-volume cases. A production host test checks separate identities,
bidirectional write isolation and existing/symlink target refusal. Both ARM runs
boot through this path and preserve the original firmware hashes. The initial
ENOSPC host build is retained as a failure; fallback is not forced in this gate.

Complete attempts, sources and ownership notes: `/Users/alex/.cache/vch-20261113-01`.
Complete typed inventory:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-client-handoff-20261113-01.inventory.json`,
SHA-256 `10d50d5375195a9d93cb7117d56e859fb557bdd2c68c6c05bc144683c5be6ab5`.
Recording and separate verification pass with adjacent logs. Controllers admit
actual parsed V sources/heap tracker and verify selected tool/kernel/firmware
and generated-artifact hashes before/after boot. PID1 collects exact suite status
zero before the harness stops QEMU. Byte-verified filesystem compression and
APFS staging clones preserve logical contents and artifact paths; all historical
bundles remain intact. Full C toolchain inventory, kernel heap retention,
resource exhaustion, injected fork/close/mask failures and arbitrary namespace
mutation remain unqualified. These are execed V protocol fixtures. Real Wine
cwd/config bootstrap, credentials/SCM acceptance, signed runtime/translator and
sandbox startup still need qualification before production wiring. Generation
lease integration and holder-death retention remain open.

## Retained x86 Wine startup diagnostic, 2026-11-13

Source `57596fcd7` adds `wine-owned-check.v`, `wine-owned-probe.v` and the
`wineoverlay` module. Two fresh x86_64 builds/boots pass as ordinary uid/gid
1000: the manager starts real Wine 9.17 with `--foreground`, authenticates its
lock owner and socket against the owned unreaped child, and transfers that
connection to the actual Wine client using `start_client` and an explicit
environment. The retained Win64 application reports image protection, W^X,
exception/read-fault recovery, shared-data and private-dispatch-child success.
Client and foreground server both retire naturally with exact status zero.
PID1 collects the suite's zero status before its final marker and harness stop.

Each run uses a fresh private APFS clone of the pinned `native-x86-09` ISO from
the [shared-user baseline](wine-shared-user-check.md). The private builder
replaces only the fixed ordinary USTAR `/sbin/init` payload with the new guest
ELF and a zero tail. Streaming verification compares every other ISO byte and
the complete replacement/padding before and after boot. The original kernel,
runtime, application, catalog and signatures remain unchanged; `overlay.json`
binds image/guest/payload hashes and bounds. The harness's separately generated
small rootfs/initramfs are retained but are not the complete guest filesystem.
The retained kernel is not a qualification of the current production kernel.

Production and ASan/UBSan host overlay checks pass, including ten refusals for
outside-slot mutation, wrong original payload, oversized replacement, corrupted
padding/payload, duplicate or linked init, invalid extent, bad checksum and
missing end marker. The overlay requires stopped trusted host writers; it is
not an archive extractor or a hostile namespace-race boundary. The controller
admits actual parsed guest V sources and verifies selected tool, firmware,
source and baseline hashes. No historical auditor was weakened.

Complete attempts, source views, generated C, binaries, commands, logs and both
diagnostic images: `/Users/alex/.cache/vwo-20261113-01` (frozen).
Complete typed inventory:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-owned-20261113-01.inventory.json`,
SHA-256 `2e44d89a0183dd296adef9e70152e8a564fd61a04425cb26430a6f111005e19b`.
Recording and independent verification pass with adjacent logs. Final
`run-02` uses the complete current sources; `run-01` preserves its earlier
overlay-test source view. Original audit bundles remain intact and required.

This is a direct ordinary-account diagnostic with explicitly supplied SDK
context from the retained baseline. Fresh package/signature admission,
sandbox startup, ARM/translator and production-runner wiring remain open.
The client starts in the prefix, leaving application cwd/relative-path
semantics unqualified. No generation lease or descendant barrier is installed;
holder-death retention remains open. Full C toolchain/environment inventory and
kernel/V heap retention are not established by this check.

## Captured client working directory, 2026-11-13

Source `60464316d` adds `ServerConnection.start_client_in`, borrowing a
caller-admitted directory FD instead of always starting in the prefix. It
captures a CLOEXEC duplicate and checks directory type before fork; the child
uses the existing async-safe fchdir/close/signal/exec path. The duplicate is
closed in the parent on every return and does not survive child exec. Existing
`start_client` retains its prefix default. Directory package identity/access
policy and exclusive descriptor lifetime until return remain caller duties.

Final `check-02` passes `arm-02`, `x86-02`, `signal-arm-01` and `signal-x86-01`
on the unchanged production kernels from `/Users/alex/.cache/vpr-20261113-01`.
Each standard run completes 100 cycles with zero retained parent V bytes and
flat descriptors. The client reads a relative file from the captured directory
after its old pathname is replaced by a decoy; parent cwd, environment, mask,
borrowed FD and unrelated FD remain intact. Invalid/non-directory descriptors
refuse before fork without consuming the socket. Permission-denied fchdir
reports stage 1/status 126; missing exec remains stage 4/status 126. Both
preserve owned collection and server EOF/status 37. Signal controls still
return 143 and preserve parent resources. Host unsupported-platform checks
pass. Generated C confirms stack stat storage and unchanged child setup calls.

`wine-01` also passes using the unchanged retained x86 image/kernel described
above: real Wine starts `bin/program.exe` relative to the captured application
directory, completes the Win64 checks, and both client and foreground server
exit zero. The controller requires the relative-startup marker and verifies
the complete image delta, padding and selected input hashes. This establishes
initial relative executable resolution, not Windows relative data-file APIs
or every Wine cwd/config bootstrap branch. Fresh signed/sandbox startup, ARM
Wine, production runner/lease wiring and descendant/holder-death retention
remain open. Full C environment and kernel heap retention remain unqualified.

Complete sources, commands, generated C, binaries, results and boot evidence:
`/Users/alex/.cache/vcwd-20261113-01` (frozen). Initial `check-01` ARM/x86 runs
also pass; its original source is retained separately. Complete typed receipt:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-client-cwd-20261113-01.inventory.json`,
SHA-256 `24bc547b141a3229e84222e15516dad5d94ba02ca57a75e5bf4a917a82fcd158`.
Recording and independent verification pass with adjacent logs. Historical
originals and prior frozen workspaces remain intact and required.

## Real Wine lease composition, 2026-11-13

Source `d1f087db7` composes the standalone holder with the owned Wine manager
in a diagnostic; production launch paths remain unchanged. It also privately
names the holder's C `read` binding, fixing an incompatible global declaration
when `appsdk` and `launchhold` are imported together. ARM/x86 standard holder
regressions pass with that binding change.

Final `check-03` passes `lease-03` and `death-01`: ordinary uid/gid 1000 runs
the retained real Wine/app closure, authenticates its foreground server and
hands its socket to the real Win64 client. After collecting client status zero,
the manager deliberately exits 37 without cleanup while a `--persistent=20`
server is still alive. The observer requires non-zombie server PPid equal to
the holder and an independently opened exclusive lease attempt to remain busy.
The holder returns saved manager status 37 only after descendant retirement;
the observer then requires a free lease and absent server proc entry. This
does not establish the individual server's final status.

In `death-01`, the observer enables/read-checks subreaping, kills and reaps the
original caller with SIGTERM, and checks the lease remains busy. The observer
already closed its shared copy, so the waiting original caller cannot supply
this protection. It then collects the adopted holder by exact PID/status 37.
`unheld-02` closes the lease and bypasses the holder: real Win64 execution
still passes, but the guest refuses exactly at `live Wine lease was not busy`.
Its `passed=false` result is the required negative control, accepted only at
that gate. `owned-01` also passes the original startup/natural-retirement mode.

Leased modes actually embed the retained production x86 kernel from
`/Users/alex/.cache/vpr-20261113-01/x86-production-01`, SHA-256
`ed5a26544945c8c599c0adc05efcbace8dae10e058f8fb66131f04caa8292fa7`.
The controller rebuilds a private ISO and checks regular-file membership and
contents against the original, replacing the kernel and permitting only BIOS
boot-info-table regeneration (unused in this baseline). The retained entire
initramfs is identical before the existing fixed-init overlay. Full-byte
comparison against the new kernel baseline then permits only the diagnostic
ELF plus zero tail in the init slot. Selected tool/input and generated image
hashes pass before/after boot. Original image and historical auditors remain
unchanged. An initial combined-build refusal and earlier successful runs are
retained with their source views.

Complete sources, generated C, binaries, literal commands, images and logs:
`/Users/alex/.cache/vwlease-20261113-01` (frozen). Complete typed receipt:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-real-lease-20261113-01.inventory.json`,
SHA-256 `2b7e4be2c1233b9960e9a3d9242fcea59fa226446f49af55d1e5383e39a64b7e`.
Recording and independent verification pass with adjacent logs; an initial
verification attempted before recording finished is also preserved.

This uses a synthetic flock lease, not production generation collection or
fresh signed/sandbox acceptance. Manager exit deliberately releases the prefix
guard while Wine lives; concurrent launch/recovery policy is not qualified.
ARM Wine, Windows relative data-file APIs, production wiring, holder SIGKILL
retention and a kernel-owned workload reference remain open. No new kernel
publication/barrier, full C environment, reproducibility or heap-retention
guarantee follows from this diagnostic.

## Windows relative file APIs, 2026-11-13

Source `9fa3075a4` adds the standalone unsigned Win64 program
`wine-cwd-program.v` and `cwd`/`cwd-wrong` controller modes. The existing
`wine-pe-check` producer builds a real AMD64 PE32+ executable with verified
before/after inventories of its selected V vlib/thirdparty, MinGW and explicit
producer/compiler/source inputs. The diagnostic controller embeds the supplied
PE in a generated guest source, binding the original template, generated V,
actual parsed source closure and PE/copy hashes. It accepts an explicit PE;
it does not independently admit the complete producer proof or a package.

Final `check-02` passes `cwd-02`: ordinary uid/gid 1000 uses the owned foreground
server and authenticated socket handoff to start the PE in a captured writable
directory containing a space. Windows `GetCurrentDirectoryA` matches the exact
requested Z: path; relative `CreateFileA`/`ReadFile` read known input bytes.
The parent writes a relative output and `CreateProcessA` launches the same
relative executable, also containing a space, with quoted argv0 and NULL cwd.
The child repeats the cwd/read checks and writes a separate output. Child,
client and direct foreground server all exit zero. The native manager checks
both output files' exact contents and their absence from the prefix, where a
different input decoy was installed. PID1 collects manager zero before PASS.

`wrong-01` supplies a wrong expected cwd and requires exact Windows exit 41;
other statuses refuse. `owned-01` and `death-01` preserve original startup and
caller-death lease-retention regressions. Cwd modes use the actually embedded
retained production kernel and verified ISO rebase described above. The
historical init slot is unchanged: stripping the new diagnostic ELF's symbols
fits its embedded PE while retaining generated C and build commands. Initial
DWORD ABI and oversized-guest failures remain preserved with source views.

Complete producer, guest builds, sources, binaries, commands, images and logs:
`/Users/alex/.cache/vwcwd-20261113-01` (frozen). Complete typed receipt:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-windows-cwd-20261113-01.inventory.json`,
SHA-256 `cc9a246b349d49a84dfb4bc005609031b651f14023aee5042d28a2182a797f20`.
Recording and independent verification pass with adjacent logs. PE SHA-256 is
`fbc7514123ab98fba5f83add3ca716b875f941d2000b5b41e6d5ca118e80cdd7`;
its separate producer receipt remains in `pe-02/proof.json`. Original images
and historical evidence remain intact and required by their own auditors.

This covers these Windows APIs on retained x86 Wine outside the sandbox with
an unsigned scratch payload. Fresh signed/published startup, arbitrary path
encodings/mappings, broader bootstrap and ARM Wine remain unqualified, as do
production runner/lease/recovery wiring and holder SIGKILL retention. No heap,
complete Linux C environment or reproducibility guarantee is added.

## Owned Wine under package sandbox policy, 2026-11-13

Source `a4d2c5344` adds `sandbox` and `sandbox-cwd` diagnostic modes. They execute
the current owned manager through the retained `/usr/bin/vinix-sandbox`. The manually supplied
policy matches current Windows + process promises in `pkgcore/launch.v`:
`stdio rpath wpath cpath flock exec prot_exec fattr sendfd recvfd proc unix`.
Grant classes remain application/runtime `rx` and private data `rwc`; sandbox
automatically unveils the diagnostic `/sbin/init` itself `rx`. The current
launch-plan source is hash-bound as an input, not executed to generate this
policy. No additional promises, `/proc` grant or blanket `/tmp` grant is used.

An ordinary uid/gid 1000 stage prepares data and an existing readable file
outside the grants, then execs the retained sandbox and fresh manager. Inside,
opening that file must fail with EACCES/ENOENT. A disposable fork attempts an
AF_INET stream socket and must die with SIGABRT; an ordinary socket error or
success followed by exit 97 cannot satisfy the check. Only then does the
manager prepare the prefix, start/authenticate its owned foreground server and
transfer the connection to Wine. Both the retained Win64 application and the
separate cwd/read/write/child-inheritance diagnostic pass, followed by exact
client/server zero and PID1 suite-zero collection.

The retained production x86 kernel is actually embedded using the previously
verified ISO rebase; all retained sandbox/runtime/app file contents remain
unchanged. Fresh init/source/PE hashes, parsed V closure and complete image
delta/padding checks are verified. Default startup and caller-death lease
regressions also pass. Earlier runs and source views are preserved, including
a stopped attempt that unnecessarily required a kernel pledge report on the
serial port; this x86 setup exposes the exact SIGABRT status there, not that
kernel text. Final `check-04` passes `sandbox-03` and `cwd-03`, requiring the
file-denial and signal-status markers plus complete Wine/client/retirement
markers. `check-03` also passes `owned-01` and `death-01`; its source view
predates only the correction to the sandbox serial-text requirement.

Complete source views, builds, binaries, commands, images, results and logs:
`/Users/alex/.cache/vwsbox-20261113-01` (frozen). Complete typed receipt:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-owned-sandbox-20261113-01.inventory.json`,
SHA-256 `97c0c4b8d70932e6ffb7f5a31a228f72076cd222dc58496c3a43601655e97f3b`.
Recording and independent verification pass with adjacent logs. The unchanged
cwd PE and its producer proof remain in the earlier frozen
`/Users/alex/.cache/vwcwd-20261113-01/pe-02` bundle. Preserve both complete
workspaces and original historical namespaces.

This exercises the retained sandbox binary with a supplied matching policy
and explicitly constructed SDK context. It is not fresh package/signature
admission, a rebuild of the current sandbox, production Wine-runner or lease
wiring, ARM acceptance or a general path/recovery guarantee. Holder SIGKILL
retention, broader mappings and complete C environment/heap qualification
remain open.

## Prefix contention and post-manager relaunch, 2026-11-13

Source `7cdb6b63d` adds `lease-recovery`. `check-01/recovery-01` passes a
controlled sequence with the real retained x86 Wine/app closure. A file barrier
pauses the manager after server authentication while it holds the prefix guard;
the observer must fail guard acquisition at `already has a managed launch`
before allowing client execution. After Win64 client zero and deliberate
manager exit 37, the observer confirms the live server was adopted by the
holder. It can now acquire the guard, but server-directory admission must
refuse at `Wine server lock already has an owner`. It neither connects to nor
signals/reaps that foreign server. Its proc entry and busy lease remain.

Caller SIGTERM and exact collection again leave the lease busy until holder
and Wine retirement. The adopted holder returns saved manager status 37; the
lease becomes free and the original server proc entry disappears. A second
direct diagnostic manager then reuses the existing prefix path without fixture
cleanup of Wine's namespace. Idle admission, fresh owned authentication, real
Win64 execution and exact client/server zero pass. This second launch is not
leased; it checks prefix reuse, not another generation collection boundary.
The diagnostic's temporary directory creation is idempotent for reuse.

`sandbox-cwd-01` also passes the retained sandbox policy, unveil/pledge refusals
and Windows relative-file/child-inheritance checks. Both boots use the actually
embedded retained production x86 kernel and preserve original runtime/app/
sandbox contents through the verified rebase and fixed-init overlay. Parsed V
source, selected input hashes and complete image/padding verification pass.

Complete builds, source views, generated C/binaries, commands, images and logs:
`/Users/alex/.cache/vwrecover-20261113-01` (frozen). Complete typed receipt:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-prefix-recovery-20261113-01.inventory.json`,
SHA-256 `6c498d1d2808a65f513d17f2a4064e4464b484e0ccbc0365462341d179df0658`.
Recording and independent verification pass with adjacent logs. The unchanged
unsigned cwd PE remains in the prior frozen `vwcwd-20261113-01/pe-02` bundle;
preserve both complete workspaces and original historical namespaces.

These are controlled contention and post-manager checks. They do not retain
the prefix guard after manager death, delete stale sockets, attach to/kill a
surviving foreign server, qualify arbitrary namespace races, or enable
production recovery/lease wiring. Fresh signing/current-launcher admission,
ARM Wine and holder SIGKILL retention remain open. No new kernel, full C
environment, heap-retention or reproducibility guarantee is added.

## Opt-in owned SDK entrypoint, 2026-11-13

Source `564c23f44` adds `-d wine_owned_manager` to the SDK's actual
`wine-runner.v`. Only the x86_64 top-level entry uses owned prefix/server
admission and authenticated client handoff. It captures the initial cwd,
snapshots the canonical environment before fork, collects the client result
and returns it after direct server retirement. Still-owned direct children are
cleaned up on errors. Existing SDK/process/architecture/application-argument
checks run first; nested aliases remain exec bridges. Default builds keep the
bridge and enabled top-level entries on other architectures refuse.

Final `check-04/runner-03` compiles this actual source with the flag and admits
its parsed V closure, embeds a compressed fresh ELF in the diagnostic init,
then executes it through the retained sandbox with the supplied SDK environment
and current Windows process policy. The runner itself calls `appsdk.load()`.
The unchanged retained Win64 application passes; PID1 collects the actual
runner's exact zero result. `refused-01` changes argv[1] and requires the exact
application-path admission error and exit 126. `recovery-01` preserves the
earlier diagnostic's guard/server refusal and post-caller-death relaunch checks.
Default ARM and x86 runner builds also compile/link; those are smoke checks,
not fresh native runtime qualifications.

An initial run reached Win64 PASS but failed cleanup. Generated C exposed a
typed array free retiring borrowed command strings; the final code frees only
that buffer. The failed run, earlier source views and successful correction
remain retained. Both runner and guest parsed sources, selected input hashes,
compressed/raw ELF and complete ISO payload/padding verification are checked.
The existing verified rebase embeds the retained production x86 kernel while
preserving runtime/app/sandbox bytes. No historical auditor was weakened.

Complete sources, failed/successful builds, generated C, binaries, commands,
images and logs: `/Users/alex/.cache/vwentry-20261113-01` (frozen). Typed receipt:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-sdk-entry-20261113-01.inventory.json`,
SHA-256 `57a8123d0eee6746b50741c14b34a8b2fa37af12d030878dbd59b488e7d2978f`.
Recording and independent verification pass with adjacent logs. Keep the
complete workspace and original input/historical evidence namespaces.

This stages the real SDK entrypoint, not the default package launch path. The
outer generation lease/descendant holder is still required: waiting for the
direct server alone is insufficient. Package-builder enablement, fresh signed
package/CLI acceptance, current sandbox rebuild, ARM owned execution, broader
SDK-level fault/status coverage and holder SIGKILL retention remain open.
No full C environment, reproducibility or heap-retention guarantee is added.

## Opt-in generation lease dispatch, 2026-11-13

Source `3b9310aea` threads the already verified generation lease from both
`run_application` and prepared `Service` launches into a shared leased-mode
implementation. Plan/payload/data admission still precedes execution. With
`wine_owned_manager`, x86 Windows launches use `run_generation_launch` to pass
the borrowed FD and complete plan to `launchhold.run`. Shared callers retain
their original lease/state ownership and exact-holder wait; subreaping and
arbitrary descendant reaping stay in the private holder. Default/non-Windows
dispatch uses the original launcher. Missing leases and other enabled target
architectures refuse. The builder does not activate this flag by default.

`generation-launch-check.v` passes `held-01` on the unchanged production x86
kernel, calling the actual private pkgcore dispatcher. Ordinary uid/gid 1000
creates a synthetic shared lease; an execed client double-forks a session
worker. The worker must confirm holder PPid before readiness. An independent
exclusive lease attempt stays busy until release; exact client status 37 is
preserved across worker status 23, then the lease is free. Missing-lease
refusal and the non-Windows original exec-error path pass too. `unheld-01`
compiles without the flag and must refuse at worker readiness timeout, exposing
lost holder adoption. Its failed guest result is the expected control.

The holder's raw syscall declaration is privately named to avoid pkgcore's
incompatible global declaration, with unchanged syscall arguments/policy.
ARM/x86 standard holder regressions and a separate real current SDK-entrypoint
run pass. Full package CLI default and opt-in builds generate C and link with
the established V-library pointer compatibility option. Those CLI builds are
smoke checks, not complete native CLI/signature admission. Native fixture
controllers admit parsed sources and verify selected input/generated hashes;
PID1 collects the positive fixture's exact zero before PASS.

Complete builds, source views, generated C/binaries, commands, images and logs:
`/Users/alex/.cache/vwdispatch-20261113-01` (frozen). Typed receipt:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-generation-dispatch-20261113-01.inventory.json`,
SHA-256 `3f7ad14a39a24f072f32d11297d477e8a142ffdec6b83ea2d3781df0b5f473cf`.
Recording and independent verification pass with adjacent logs. Preserve this
complete workspace and the original checker/input/historical namespaces.

This connects the real package dispatcher but does not qualify the complete
installed-generation collection/CLI/signature-to-owned-SDK pipeline. Both
package core and SDK must use the flag. Fresh signed runtime/app rebuilding,
default enablement, ARM owned Wine and holder SIGKILL/kernel-owned retention
remain open. Synthetic-lock tests and separate component runs do not establish
these remaining gates or full C environment/heap/reproducibility guarantees.

## Low-numbered generation leases, 2026-11-13

Source `9c877b770` fixes an opt-in dispatch edge case: opening a verified lease
after closing stdio can yield FD 0–2, while the holder requires FD >=3. The
package dispatcher checks CLOEXEC and retains a private F_DUPFD_CLOEXEC copy
above stdio, sharing the same open description/lock. It closes only that copy
after holder completion/error; it never moves, unlocks or reopens the caller's
descriptor. Default/non-Windows dispatch and the holder itself are unchanged.

`check-02/held-01` passes normal and FD0 launches in the native pkgcore fixture.
The workload sees FD0 closed; session adoption, busy lease until release,
saved status 37 and final free lease pass. Before closing its own FD, the
caller verifies it remains live/CLOEXEC and still holds the lock. An inheritable
FD0 refuses before launch without changing it; restoring CLOEXEC permits retry.
Missing leases and non-Windows exec errors remain checked. `unheld-01` still
detects lost adoption at the required readiness-timeout gate. Parsed source,
selected input and generated artifact hashes pass before/after boot. Generated
C confirms cleanup closes only the private duplicate after the synchronous call.

Complete builds, sources, C/binaries, commands, images and logs:
`/Users/alex/.cache/vwlowfd-20261113-01` (frozen). Typed receipt:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-generation-lowfd-20261113-01.inventory.json`,
SHA-256 `89141ac3b9d634d39cfa13c0ed5fd1e9447c248fb0a5e9b4d109e01364380d2d`.
Recording and independent verification pass with adjacent logs. Keep the
complete workspace and original input/historical namespaces.

FD0 is the tested low-slot representative; FD1/2 share its code path but are
not individually exercised. These are synthetic-file native checks, not fresh
installed collection or package/CLI/signature acceptance. Default enablement,
ARM owned execution, holder SIGKILL retention and broader resource/heap/C
environment qualification remain open.

## Fresh signed owned x86 launch, 2026-11-13

Source `557448492`, with patch-writer prerequisite `62ef8d012`, connects the
fresh signed console package to the owned Wine path. The producer and native
controller accept explicit x86-only `--owned-manager`; the controller builds
both the current guest and package CLI with `-d wine_owned_manager`. Before
signing it checks the runtime mode/source receipt, actual compiler arguments
and runner output digest. Four controls pass: ARM producer/controller refusal
and both directions of controller/runtime mode mismatch. Default activation
remains unchanged; these controls are not a full receipt-mutation matrix.

`native-02` passes fresh local publisher key generation, runtime/application
signing, publishing, catalog verification and installation of generation 1.
The current CLI runs through the verified generation lease, private holder,
retained sandbox and actual current `appsdk.load`/owned foreground server with
authenticated socket handoff. The freshly compiled original Win64 probe passes
image, W/X, exception, read-fault, shared-data and private-dispatch checks;
outside-write refusal passes. CLI status is 0, readiness is observed, and the
real generation lease is busy at readiness and free after return. Every
observed Wine PID is absent when the CLI returns, checked before PID1's old
assistance loop can reap anything. This does not prove an arbitrary-descendant
barrier. The result is `passed=true`, `interrupted=false`, 31.636 seconds;
the harness subsequently stops QEMU, without qualifying guest shutdown.

Historical distribution staging is missing and the first producer attempt
correctly refuses it. A fresh stage reconstructed from retained APKs, the four
existing V Wine patches and retained font configuration matches all 1,020
selected historical input file hashes, with zero differences. It does not
restore the old namespace or waive historical audits. The source offer remains
local-qualification-only and incomplete for redistribution. The first native
attempt retains a compiler-selection link refusal; explicitly selecting the
producer's cached V for the controller resolves it without a shim or relaxed
admission. Focused atomic patch-write tests pass; the existing full patch test
build remains blocked by deprecated integer types in its hosttest dependency.

Complete successful and refused attempts, commands, generated C/binaries,
selected source/tool snapshots and logs are frozen at
`/Users/alex/.cache/vwfull-20261113-01`. Typed receipt:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-fresh-owned-20261113-01.inventory.json`,
SHA-256 `5f618c2c8c96ccf03927ee09376e473004067b44e83571c2b13810855f43e15b`.
Recording and independent verification pass with adjacent logs. Snapshots
preserve the exact selected pre-documentation source and tool bytes, including
compiler, MinGW, sysroot and APK inputs. Original namespaces and complete
historical bundles remain required by their auditors. Snapshot copying does
not change the ISO clone refusal or establish hermetic/reproducible builds.

This closes the fresh locally signed x86 console integration gate. Default
enablement, ARM owned execution, fresh owned graphical acceptance, active
generation collection after initial-client exit with a live server, the full
new refusal matrix and holder SIGKILL/kernel-owned retention remain open.
Sandbox/account helpers and the production kernel are retained selected
inputs; this run adds no complete C environment or kernel/V heap guarantee.

## Collection after initial client exit, 2026-11-13

Source `d15403c58` adds explicit `--owned-manager --collection-probe` to the
native controller. A fresh signed x86 console application starts another real
Windows process and exits 37. The fixture identifies the initial Unix client,
foreground server and child, verifies ordinary credentials/private socket,
then observes the initial client absent with the server and child non-zombie.
The current CLI, verified generation lease/private holder, retained sandbox
and current owned SDK path remain connected throughout this check.

`native-08` passes real CLI removal and rollback into generations 2 and 3;
running generation 1 is explicitly neither active nor rollback. Three actual
CLI `gc` calls retain that generation and its unchanged PE while exclusive
nonblocking flock refuses with EAGAIN/EWOULDBLOCK. Initial-client absence,
server/child liveness and the waiting CLI are checked through the interval.
Only afterward does a private release file let the Windows child exit.
Natural retirement returns the original client status 37, with all three
observed Unix PIDs absent before any PID1 assistance. A fourth `gc` removes
generation 1 while active state and rollback remain. The result is
`passed=true`, `interrupted=false`, 104.291 seconds. This fixture uses 3 GiB
to stage the additional full runtime in guest tmpfs; it synthesizes no
generation or lease metadata.

`pe-05`/`prepared-03` freshly build the final probe and owned runtime.
`native-09` passes the separate ordinary signed Win64 API/W^X, private-prefix,
socket, outside-write refusal and strict observed-process retirement gate
with that same build: status 0, readiness observed, 56.692 seconds. Both
controllers pass input/generated-output rechecks; their complete input maps
are byte-identical. `modes-04` passes six early mode/architecture refusals,
including collection without owned mode and ARM collection, before signing
or workload creation. It does not qualify the full new refusal matrix.

Captured source/input bytes, generated C/binaries, images, logs and
successful/refused/interrupted attempts are frozen at
`/Users/alex/.cache/vwcollect-20261113-01`. `selected-inputs-01` preserves the
selected native and typed PE input bytes, covering both final native runs;
the earlier timed source view is preserved separately. Source/compiler
namespaces and complete historical bundles remain required by their auditors;
snapshots do not relocate or waive those checks. The distribution remains the
retained fresh stage from the preceding qualification, with an incomplete,
local-only source offer.

Typed receipt:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-collection-after-client-20261113-01.inventory.json`,
SHA-256 `80df5bc61627972ff191be9ab85b7de97e870f237130c4fa3d0e9160c146a2b4`.
Recording and independent verification pass with adjacent logs. Preserve the
entire frozen workspace, selected snapshots and original historical namespaces.

Early interrupted runs exposed a new fixture double free: explicit PID-string
cleanup followed by the selected compiler's deep string-array free. The final
code frees elements once and then the raw array header; generated C confirms
that ownership. A genuine 30-second rollback timeout and a full-volume PE link
failure are retained. Final rollback has a bounded 180-second deadline and the
worker waits for explicit release with a watchdog. Storage helper `4a80789fe`
verifies independent APFS replacements of 20,281 duplicate artifact files,
preserving bytes, modes, owners and paths with a complete replacement report;
earlier frozen bundles are untouched. Only unbound QMP sockets from stopped
interrupted guests were removed, with metadata recorded. No checker was weakened.

This qualifies local x86 console collection with a surviving Windows child
and server after initial-client exit. It adds no pure-idle-server collection,
signed caller-death, ARM owned execution, fresh owned GUI, default activation,
holder SIGKILL/kernel-owned retention or arbitrary-descendant/refusal guarantee.
Kernel, sandbox and account/session helpers are retained selected inputs;
complete C environment, kernel/V heap and hermetic/reproducible gates remain open.

## Owned build receipt preflight, 2026-11-13

Source `c620354d3` adds `--check-owned-build x86_64 PREPARED_BUILD` to the host
controller, sharing ownership receipt admission with normal owned launches.
Production and embedded-source checks still run first. Captured directory/file
opens reject symlinks at every receipt path component; final files must be
bounded and regular, with nonblocking opens preventing FIFO hangs. Marker,
output manifest and compiler argv bounds are 8 KiB, 1 MiB and 64 KiB; argv has
2–512 elements and the runner is bounded to 32 MiB. Exact marker fields, current
source hash, separate ownership flag and marker/runner output digests bind the
selected inputs. Default mode now rejects directory, FIFO and broken-link
ownership markers instead of treating them as absent.

`controls-03` passes two positive reads of the retained real producer receipt
and 32 mutations through both preflight and actual controller startup: 64
receipt refusals before signing/build output. These cover wrong/missing schema
fields and digests, changed runner bytes, absent/misjoined flags, empty/excessive
argv, malformed/oversized JSON, missing files, symlink files and parents,
directory substitution and a FIFO. Mutated marker hashes are updated where
needed to isolate field checks. Stale-source, non-production and ARM preflight
controls plus three default-mode nonregular-marker controls pass as well.
The V checker builds its own controller variants and preserves their source,
compiler commands and logs. Refinement `a5bbeb901` records every checked exit:
positive reads require 0, refusals require 1 and the expected message; timeouts,
interruptions, signals and lost waits cannot satisfy the refusal gate. Original
receipt/runner and selected source/tool hashes are unchanged afterward.

`legacy-modes-01` retains the prior six mode/architecture refusals. `native-01`
freshly signs/publishes/installs the retained owned runtime and application
through the hardened controller, rebuilding the current guest and package CLI.
Real Win64 API/W^X, image, exception/read-fault, shared/private-dispatch, private
prefix/socket, outside-write refusal and generation-lease checks pass. Status 0
and readiness are observed, and tracked Wine PIDs are absent before PID1
assistance. Result: `passed=true`, `interrupted=false`, 31.729 seconds. Parsed
source, complete selected-input and generated-output rechecks pass. This uses
the unchanged prior prepared runtime/PE, with their complete producer evidence
retained in the preceding frozen bundles; it does not rebuild those artifacts.

Current sources, generated C/binaries, mutation candidates, exact command/log/
exit records and the guest bundle are frozen at
`/Users/alex/.cache/vwreceipts-20261113-01`. `selected-inputs-01` preserves all
selected native input file bytes before documentation edits. FIFO controls are
retired only after execution with metadata retained; all other candidates and
intermediate diagnostic attempts remain. Preserve the prior complete bundles
and original namespaces too; snapshots do not waive historical auditors.

Typed receipt:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-owned-receipt-20261113-01.inventory.json`,
SHA-256 `d1c696da16ca6b0e7b61108360a89af9d47dc77f8b982b6e50e7f372523e3098`.
Recording and independent verification pass with adjacent logs. Keep the entire
frozen workspace and the referenced original producer/input bundles.

Preflight qualifies ownership bindings and bounded artifact reads, not complete
payload admission, compiler authenticity, concurrent-write immutability or
signing/guest success. The real signed regression is separate. Broader runtime
refusals, default activation, ARM ownership, fresh owned GUI, idle server and
caller death cases, holder SIGKILL/kernel-owned retention, full C environment/heap and
hermetic/reproducible qualification remain open.

## Signed caller death, 2026-11-13

Source `5d1c3c8af` adds explicit `--owned-manager --caller-death-probe` to the
host controller. The new define applies only to the guest observer; the actual
package CLI uses the existing owned production path. ARM, missing owned mode
and simultaneous lifetime probes refuse before signing/workload setup. The
expanded mode controls pass nine refusals, preserving prior mode behavior.

`native-02` freshly signs/publishes/installs the retained prepared runtime/PE
and rebuilds the current guest and package CLI. After the initial Win64 client
exits with a live Windows child/server, the fixture identifies exactly two
ordinary UID/GID 1000 package processes with the launch argv. Their direct
parent/child relationship distinguishes the non-execing holder from its caller.
An independent parent-chain check ties that holder to the actual runtime SDK
bridge and observed foreground server. Ambiguous or inconsistent roles refuse
before targeting the caller. It kills the ordinary caller with SIGKILL, observes its
absence and outer CLI status 137, and confirms the holder survives under PID1.
The original lease owner dies here; killing only the root wrapper would not
establish this case.

Real remove/rollback transactions make running generation 1 neither active
nor rollback. Three `gc` calls retain it and its unchanged PE while exclusive
nonblocking flock refuses EAGAIN/EWOULDBLOCK. The caller/outer CLI remain gone;
holder, server and Windows child remain live and non-zombie. Only afterward
is the child released. Wine retires naturally, and a targeted wait for the
adopted holder requires its saved status 37. Fixture PID1 collects that holder,
with no Wine-process rescue reaping. The initial client, caller, holder, server
and child are absent at completion. A fourth collection removes generation 1
while active state and rollback remain. Result: `passed=true`,
`interrupted=false`, 129.575 seconds.

`native-03` passes the existing live-caller collection case on the same input
bytes, preserving ordinary status 37 and natural/post-retirement cleanup:
`passed=true`, `interrupted=false`, 116.728 seconds. Both runs pass parsed-source,
selected-input and generated-output rechecks; complete input maps are
byte-identical. The first failed fixture attempt expected the SDK entrypoint
under the application instead of the runtime directory. That assertion was
corrected from the existing launch implementation; original source, generated
C, logs and failed result remain. That attempt never reached the caller-kill
step; its normal failure cleanup stopped the outer CLI and guest.

Sources, native input snapshots, C/binaries, boot media, literal commands,
logs and all attempts are frozen at `/Users/alex/.cache/vwdeath-20261113-01`.
`selected-inputs-01` preserves the complete selected native file bytes before
documentation edits. The prior prepared runtime/PE and original producer
bundles remain separate required inputs. No historical checker or previous
frozen bundle was modified; snapshots do not waive original namespaces.

Typed receipt:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-caller-death-20261113-01.inventory.json`,
SHA-256 `abd0a5e4f68381b2aa3cd67b534614d49ab6e5cd893e13d161e04b6ad80da867`.
Recording and independent verification pass with adjacent logs. Preserve the
entire frozen workspace and the referenced original producer/input bundles.

This qualifies local signed x86 package-caller SIGKILL while the private
holder, SDK manager, server and Windows child survive. It does not qualify
holder or SDK-manager death, whole-session/logout teardown, pure idle-server
collection, ARM ownership, fresh owned GUI, default activation, arbitrary
descendant/refusal cases or kernel-owned lease retention. Kernel, sandbox and
account/session helpers are retained selected inputs; full C environment,
heap and hermetic/reproducible gates remain open.

## Idle server after client retirement, 2026-11-13

Source `65c21e51c` adds `--owned-manager --idle-server-probe` to the signed x86
controller. It combines collection, caller-death and idle observation only in
the guest fixture. The actual package CLI retains its existing owned path;
runtime, kernel, Wine startup arguments and persistence remain unchanged.
Twelve architecture/mode refusal controls pass, including ARM, missing owned
mode and combined lifetime flags, before workload/signing output is created.

Final-source `native-04` freshly signs/publishes/installs the retained prepared
runtime/PE and rebuilds the current guest and package CLI. Credential, argv and
parent checks identify the ordinary caller/private holder, independently tied
to the SDK manager and actual server. Killing the ordinary caller removes the
original lease owner; the outer CLI reports 137 and the holder survives under
PID1. Remove/rollback makes generation 1 neither active nor rollback. Three
actual collections preserve its directory and PE while the Windows worker is
live and exclusive nonblocking flock reports busy.

A positive control matches the known live worker among two Wine clients.
After release, observed live client counts decrease through one to zero. The
matcher uses the selected runtime's exact Wine argv and process status; Z/X
processes count as retired. Retired zombies may still await their owner.
With zero live clients, the fourth collection and recheck take 183036000 ns while
server/holder remain live and non-zombie, caller/outer CLI remain gone, the
lease stays busy before and after, and generation/PE bytes survive. There is
no server pause or persistence extension. This qualifies an observed local
interval, not arbitrary idle duration or performance on other machines.

Wine/SDK retire naturally; fixture PID1 targeted-reaps only the adopted
holder and requires saved status 37, without Wine-process rescue reaping.
Initial client, caller, holder, server and worker are absent at completion.
A fifth collection removes generation 1 and preserves active/rollback.
Result: `passed=true`, `interrupted=false`, 87.561 seconds. Final-source
caller-death regression `native-05` also passes, 89.994 seconds, preserving
caller 137, holder 37 and its existing fourth post-retirement collection.
Both runs pass parsed-source, selected-input and generated-output rechecks;
their complete native input maps are byte-identical. `modes-02` passes all
twelve refusals with prepared receipt hashes unchanged.

Sources, input snapshots, generated C/binaries, boot media, commands, logs
and all intermediate positive attempts are frozen at
`/Users/alex/.cache/vwidle-20261113-01`. `selected-inputs-01` preserves all
selected native file bytes before documentation edits. The prior prepared
runtime/PE and full producer bundles remain separate required inputs;
original namespaces and historical audit requirements remain unchanged.

Typed receipt:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-idle-server-20261113-01.inventory.json`.
SHA-256 `98e0fa00f433c3e12c070cadfffb5b30faa17ed14dc8f64da92471bfd13f0144`.
Recording and independent verification pass with adjacent logs. Preserve the
entire frozen workspace and referenced original producer/input bundles.

Default activation, ARM ownership, fresh owned GUI, holder or SDK-manager
death, whole-session/logout teardown, arbitrary descendants/refusals and
kernel-owned retention remain open. Full C environment/heap and
hermetic/reproducible qualification also remain open; section 14 is incomplete.

## Process scan uncertainty, 2026-11-13

Source `ebee5d384` closes an observation gap in caller discovery and idle
client counting: a failed `/proc/<pid>/cmdline` read is accepted only if the
process directory has disappeared. An unreadable surviving entry refuses
instead of silently contributing to a possible zero-client result. Readable
empty command lines remain valid. Focused host controls cover disappearance,
unreadable surviving entries, empty reads and NUL-separated argv preservation.

Signed x86 `native-02` passes the caller-death/idle-server gate with the current
guest and package CLI: `passed=true`, `interrupted=false`, 89.28 seconds;
zero-client collection/recheck is 157573000 ns. Caller 137, holder 37, natural
retirement and final obsolete-generation collection pass, as do parsed-source,
selected-input and generated-output rechecks. The prepared runtime/PE are
retained inputs, freshly signed/published/installed, with their prior complete
producer evidence still required. Kernel/runtime/holder code is unchanged.

Evidence is frozen at `/Users/alex/.cache/vwproc-20261113-01`, including native
input snapshots, generated artifacts, source copies and logs. `native-01`
correctly refused a source edit during capture before boot. The cached V test
subcommand could not find its source tree; direct compilation and execution of
the same `_test.v` with that V passed. Original namespaces and historical audit
requirements remain unchanged. This hardens the observer; the preceding
default, ARM, GUI, holder-death and broader lifetime gates remain open.

Typed receipt:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-proc-scan-20261113-01.inventory.json`,
SHA-256 `a6d52989a98a129eb744552163620ce946e44247499e354c6409cc30980bedcd`.
Recording and independent verification pass with adjacent logs; preserve the
entire frozen workspace and referenced original producer/input bundles.

## Concurrent native holders, 2026-11-13

Source `3f7cd42d9` extends the standard native holder suite on both
architectures. Two simultaneous callers under the fixture ancestor each run
an independent holder, initial client and detached double-fork/setsid worker.
Both leases must be busy after readiness and initial-client exit. Releasing
the second worker first returns status 126 and frees only its lease; the first
lease must stay busy. The first then returns 37 and releases its lease.
An unrelated fixture child remains waitable with status 97, and the final
child inventory is empty. The existing single-caller unrelated-child test
also runs. This does not test threaded calls to two holders within one caller.

The host controller requires the new concurrent marker as well as the existing
standard suite marker. x86_64 passes in 7.141 seconds; AArch64 in 5.867 seconds,
both `passed=true`, `interrupted=false`, with parsed-source, selected-input and
generated-output rechecks. Production holder and kernel code are unchanged.
This qualifies the native primitive; signed concurrent Wine remains separate.

Complete commands, logs, source copies, generated C/binaries, media and selected
input byte snapshots are frozen at `/Users/alex/.cache/vwconcurrent-20261113-01`.
The original kernel qualification bundle and namespaces remain required;
snapshots do not replace historical audit contracts. Holder/SDK death, default
activation, ARM owned Wine, fresh owned GUI, whole-session teardown and broader
topology/heap/hermetic gates remain open.

Typed receipt:
`/Users/alex/Library/Caches/vinix-codex/section14/concurrent-holders-20261113-01.inventory.json`,
SHA-256 `be9d40f0fd6b8ca1ca43cc6b612caecb7f94327eb0a6a1aa692b364e4ef7bd70`.
Recording and independent verification pass with adjacent logs. Preserve the
entire frozen workspace and referenced original kernel/input bundles.

## Concurrent native caller death, 2026-11-13

Source `095428cd4` adds a separate concurrent-holder case to the standard
native suite. After both initial clients exit with detached workers live,
caller 0 receives SIGKILL and its exact signal status is collected. Both
leases must remain busy. Caller 1 then retires naturally with status 126;
its lease becomes free while the orphaned holder's lease stays busy. The
unrelated fixture child remains waitable with status 97. Releasing worker 0
allows targeted collection of the adopted holder with original status 37;
its lease becomes free and no children remain. The host requires this new
marker as well as the preceding natural concurrent-retirement marker.

The complete standard suites pass on retained production kernels: x86_64
13.793 seconds, AArch64 6.836 seconds, both `passed=true` and uninterrupted.
Parsed-source, selected-input and generated-output checks pass. Production
holder/kernel code is unchanged. This qualifies independent native callers,
not same-caller threaded invocation or concurrent signed Wine workloads.
Holder death, SDK-manager death and whole-session teardown remain separate.

Complete evidence and native input byte snapshots are frozen at
`/Users/alex/.cache/vwconcurrent-death-20261113-01`. Preserve the original
kernel qualification bundle and namespaces; historical audit contracts still
apply. ARM owned Wine, fresh owned GUI, default activation and broader
topology/heap/hermetic gates remain open.

Typed receipt:
`/Users/alex/Library/Caches/vinix-codex/section14/concurrent-holder-death-20261113-01.inventory.json`,
SHA-256 `e74660ec8b3aeeb31e89a28cba33875f591466ae3f6fdfff249751c277b98d67`.
Recording and independent verification pass with adjacent logs. Preserve the
entire frozen workspace and referenced original kernel/input bundles.

## Native descendant burst, 2026-11-13

Source `53657660a` adds a bounded 64-descendant burst after initial-client
exit. The detached worker forks without reaping its children, then exits.
Its final child waits until adopted by the holder and blocks for explicit
release. The observer requires the complete creation marker, adoption marker,
busy lease and caller still waiting. After release it requires original status
37, free lease and no remaining children. The controller requires the churn
marker in addition to the existing standard-suite markers.

Complete standard suites pass on retained production kernels: x86_64 23.404
seconds, AArch64 7.358 seconds, neither interrupted. Parsed-source, selected-input
and generated-output checks pass. Evidence, sources, C/binaries, media and
native input byte snapshots are frozen at `/Users/alex/.cache/vwchurn-20261113-01`.
Successful runs are `x86-02`/`arm-02`; initial launcher attempts ran before the
controller build completed and exited 127 without creating guests.

Typed receipt:
`/Users/alex/Library/Caches/vinix-codex/section14/holder-churn-20261113-01.inventory.json`,
SHA-256 `dcdd1d53fe0e88f8d58a65860f738aae8e0abebdbbdbd8796ae92f374e731a68`.
Recording and independent verification pass with adjacent logs. Preserve the
entire frozen workspace and referenced original kernel/input bundles.

Production holder/kernel code is unchanged. Preserve the original kernel
qualification bundle and namespaces; historical audit requirements still
apply. This is a native bounded burst, not arbitrary topology, signed Wine
churn or a memory-leak measurement. Holder/SDK death, session teardown, ARM
owned Wine, fresh owned GUI and default activation remain open.

## Injected descendant-wait interruption, 2026-11-13

Source `7676db6df` adds controller outcome `interrupt`. Both
`lease_holder_fixture` and `lease_holder_wait_interrupt` are needed to inject
one synthetic `-1/EINTR` result before the ordinary descendant-wait retry
branch. A raw diagnostic precedes setting errno. The fixture then uses the
existing caller-death lifetime case: busy lease after initial-client exit and
caller death, adopted holder status 37 after natural worker retirement, free
lease and no remaining children. The host requires exactly one injection and
zero unexpected-wait diagnostics. Ordinary outcomes require zero injections.

Final `interrupt-02` cases pass on x86_64 (8.012 seconds) and AArch64 (6.144).
Final `standard-02` regressions pass on x86_64 (10.387) and AArch64 (6.392).
All are uninterrupted and pass parsed-source, selected-input and generated
output checks. Per-architecture final input maps are byte-identical across
modes. Initial injection builds hit a V conditional-scope error before boot;
the corrected final runs and earlier diagnostics remain preserved.

Evidence and complete selected native input byte snapshots are frozen at
`/Users/alex/.cache/vwintr-20261113-01`. Retain the original kernel qualification
bundle and namespaces; historical audit requirements remain unchanged.

Typed receipt:
`/Users/alex/Library/Caches/vinix-codex/section14/holder-eintr-20261113-01.inventory.json`,
SHA-256 `96be40d8c26154f3b69d1cc437d294a377fbf27fd3363e021d5fea51951350fe`.
Recording and independent verification pass with adjacent logs. Preserve the
entire frozen workspace and referenced original kernel/input bundles.

This qualifies the retry branch with a synthetic result, not signal delivery
or a real kernel wait returning EINTR. No kernel or Wine runtime changes were
made. Holder/SDK death, session teardown, ARM owned Wine, fresh owned GUI,
default activation and broader topology/heap/hermetic gates remain open.

## Real caller-wait interruption, 2026-11-13

Source `4f64ce5f9` adds controller outcome `caller-interrupt`. An empty
SIGUSR1 handler is installed through libc, with automatic syscall restart
disabled. With a detached worker live, the observer sends sixteen signals.
A fixture-only diagnostic in the existing retry branch records actual
`wait4` returns of `-1/EINTR`; no wait result is injected in this case.
The observer requires a busy lease before/after signals and a caller still
waiting. Natural worker retirement must then return original status 37,
release the lease and leave no children. The host requires at least one real
interruption marker and zero synthetic injections or unexpected-wait errors.

Final `caller-interrupt-05` passes on x86_64 (8.725 seconds, fifteen observed
interruptions) and AArch64 (6.740 seconds, sixteen). Final `standard-05`
regressions pass on x86_64 (10.386) and AArch64 (6.507), with zero interruption
markers. All four are uninterrupted and pass parsed-source, selected-input
and generated-output rechecks. Per-architecture final input maps match across
modes. This qualifies actual caller wait interruption; the private holder
blocks signals and its earlier descendant-wait test remains synthetic.

Evidence and complete selected native input byte snapshots are frozen at
`/Users/alex/.cache/vwrealintr-20261113-01`. Earlier compile errors, storage-cap
failures and the x86 raw-sigaction fixture failure are retained. Final fixtures
use libc to supply the architecture signal return trampoline. No old frozen
bundle was deleted or modified; original kernel qualification and namespaces
remain required. There are no kernel or Wine runtime changes.

Typed receipt:
`/Users/alex/Library/Caches/vinix-codex/section14/holder-real-eintr-20261113-01.inventory.json`,
SHA-256 `7273be946b52420c1f2417cebae3c3bd11c5c9f8af6a64893e709833ae98d5a9`.
Recording and independent verification pass with adjacent logs. Preserve the
entire frozen workspace and referenced original kernel/input bundles.

Holder/SDK death, session teardown, ARM owned Wine, fresh owned GUI, default
activation and broader topology/heap/hermetic gates remain open.

## Closed standard streams, 2026-11-13

Source `ed6f1e2b9` adds controller outcome `closed-stdio`. The caller closes
descriptors 0/1/2 immediately before `launchhold.run`, requires `EBADF` for all
three, then requires them still closed at return. This exercises the holder's
existing status-pipe relocation out of standard descriptor slots. The existing
lifetime fixture requires a busy lease after initial-client exit with a live
detached worker, original status 37 after natural retirement, a released lease,
unchanged caller mask, unrelated-child status 97 and no remaining children.
The host requires the closed-stdio completion marker.

Final `x86-02` passes in 5.686 seconds and `arm-02` in 5.584, both uninterrupted
with parsed-source, selected-input and generated-output checks. Evidence,
generated artifacts, final source copies and complete native input byte
snapshots are frozen at `/Users/alex/.cache/vwstdio-20261113-01`. Earlier positive
runs precede the explicit before/after EBADF assertions and remain preserved.

Typed receipt:
`/Users/alex/Library/Caches/vinix-codex/section14/holder-closed-stdio-20261113-01.inventory.json`,
SHA-256 `dfe4032d975e5c0c2aa162ad08a7bed7381de77fe99b81203f22febce74a870a`.
Recording and independent verification pass with adjacent logs. Preserve the
entire frozen workspace and referenced original kernel/input bundles.

Production holder/kernel/Wine code is unchanged. Preserve the original kernel
qualification bundle and namespaces; historical audits remain required. This
qualifies native successful-launch pipe relocation, not signed Wine with
closed stdio or setup-failure reporting in this mode. Holder/SDK death, session
teardown, ARM owned Wine, fresh owned GUI, default activation and broader
topology/heap/hermetic gates remain open.

## Closed-stdio setup failures, 2026-11-13

Source `4ad960376` extends `closed-stdio` with independent cwd/exec refusal
callers. With descriptors 0/1/2 verified closed, the actual relocated status
pipe must report exact stage 7/`ENOENT` for missing cwd and stage 8/`ENOENT`
for missing executable. On return all standard descriptors stay closed, the
borrowed lease descriptor is intact, its lock remains busy, and the caller
has no children. After that caller closes its lease and exits zero, the
observer requires a free lock and no children. The controller requires the
new failure marker alongside the existing successful lifetime marker.

`x86-01` passes in 4.891 seconds and `arm-01` in 5.522, both uninterrupted
with parsed-source, selected-input and generated-output rechecks. Sources,
generated artifacts, media, commands, logs and complete native input byte
snapshots are frozen at `/Users/alex/.cache/vwstdio-failure-20261113-01`.

Typed receipt:
`/Users/alex/Library/Caches/vinix-codex/section14/holder-closed-stdio-failure-20261113-01.inventory.json`,
SHA-256 `c74416caf93d88444d83383fcc96f21d79f482be7549e9aaa3cfa9494dac987b`.
Recording and independent verification pass with adjacent logs. Preserve the
entire frozen workspace and referenced original kernel/input bundles.

Production holder/kernel/Wine code is unchanged. Original kernel qualification
and namespaces remain required; historical audit contracts still apply. This
qualifies native failure reporting, not signed Wine closed-stdio acceptance.
Holder/SDK death, session teardown, ARM owned Wine, fresh owned GUI, default
activation and broader topology/heap/hermetic gates remain open.

## Complete native matrix runner, 2026-11-13

Source `891c77caf` adds [`lease-holder-matrix.v`](lease-holder-matrix.v), which
runs all seven controller modes sequentially on both architectures. Build it
with the same V and repository/hardware-platform module paths as the controller,
then invoke the two compiled tools with reviewed inputs:

```text
MATRIX NEW_OUTPUT CHECK X86_KERNEL ARM_KERNEL X86_SYSROOT ARM_SYSROOT X86_GCC ARM_GCC CLANG V
```

The output must be new. Modes are `standard`, `fault`, `signal`,
`signal-refused`, `interrupt`, `caller-interrupt` and `closed-stdio`. Each child
must exit successfully with its exact controller completion marker; the unsafe
signal-handler control must still fail in the guest at its intended gate.
The matrix compares selected-input sets/hashes across modes within each
architecture and rechecks driver/controller/kernel/compiler pins after every
case. Children retain their existing parsed-source/input/generated checks.
Only a complete run publishes `completed.json` and the final input receipt.

`run-01` passes all fourteen controller-qualified cases. Complete driver,
commands, logs, C/binaries, guest media/results and native input byte snapshots
are frozen at `/Users/alex/.cache/vwmatrix-20261113-01`.

Typed receipt:
`/Users/alex/Library/Caches/vinix-codex/section14/holder-matrix-20261113-01.inventory.json`,
SHA-256 `8b5f56d132639b0f1160426275a270770527b1e50c7973e04c4fc3eb93b7a08c`.
Recording and independent verification pass with adjacent logs. Preserve the
entire frozen workspace and referenced original controller/kernel/input bundles.

Retain the original controller/kernel qualification bundles and namespaces;
historical audits remain required. This automates native qualification, with
no production changes. Signed Wine, holder/SDK death, session teardown, ARM
owned Wine, fresh owned GUI, default activation and broader environment/heap/
hermetic gates remain separate.

## Signed prefix contention after caller death, 2026-11-14

Source `86a76aaf6` extends both signed x86 caller-death observer modes. After
the ordinary caller dies with SIGKILL and the outer CLI reports 137, a second
actual package launch targets the same active generation/application before
remove/rollback. It must return 126 within fifteen seconds and report
`Wine prefix already has a managed launch`. The original caller stays gone;
holder, server and Windows worker remain live. The generation directory and
PE bytes survive, with exclusive flock busy before and after refusal. The host
controller requires this marker alongside the existing final lifetime markers.

`native-01` passes the idle extension in 96.964 seconds, including three
worker-live collections, the zero-live-client collection/recheck interval
177791000 ns, and fifth post-retirement collection. `native-02` passes the
caller-death regression in 92.201 seconds, including its fourth collection
after retirement. Both are uninterrupted, preserve holder status 37 and natural
retirement without Wine-process rescue reaping, and pass parsed-source,
selected-input and generated-output rechecks. Complete native input maps match.
The guest and actual CLI were rebuilt; the retained runtime/PE were freshly
signed/published/installed with prior complete producer evidence still required.

Evidence, final source copies, commands, C/binaries, media and complete native
input byte snapshots are frozen at `/Users/alex/.cache/vwcompete-20261113-01`.
There are no failed guest attempts in this bundle. Preserve the original
producer/kernel bundles and namespaces; historical audits remain required.

Typed receipt:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-competing-prefix-20261113-01.inventory.json`,
SHA-256 `cceeae6cac37ebff6084971505505a4b28ebfc020eecd0f32dd3c83121c8487a`.
Recording and independent verification pass with adjacent logs. Preserve the
entire frozen workspace and referenced original producer/kernel/input bundles.

This qualifies managed-prefix contention while the original manager survives.
Foreign-server refusal after manager death, concurrent Wine execution, holder/
SDK death, session teardown, ARM ownership, fresh owned GUI, default activation
and broad topology/heap/hermetic gates remain open. Production runtime, kernel
and sandbox permissions are unchanged.

## Signed SDK manager death, 2026-11-14

Source `585f95859` adds opt-in `--owned-manager --manager-death-probe` for
signed x86 console qualification. After ordinary caller SIGKILL/outer status
137, the observer verifies the SDK manager's parent, credentials and runtime
argv before targeting it with SIGKILL. It requires the manager gone and live
Wine server adopted by the private holder. A second actual package launch
must exit 126 at `Wine server lock already has an owner`; holder, server and
worker stay live and the generation lease stays busy. Remove/rollback then
makes generation 1 obsolete. Three real collections preserve its bytes and
PE; after natural Wine retirement the fixture targeted-reaps only the holder
and requires status 137, then a fourth collection removes that generation
while active/rollback remain. This is the killed SDK child's status; the case
does not claim preservation of initial application status 37 across SDK death.

Final `native-08` passes: `passed=true`, `interrupted=false`, 205.819 seconds,
with parsed-source, selected-input and generated-output rechecks. Fifteen mode/
architecture controls pass against the isolated controller. Actual CLI builds
receive only the existing owned define; the new define is observer-only.
Runtime/kernel/sandbox policy and Wine persistence are unchanged.

The new end-to-end recovery refusal has a separate sixty-second bound. Earlier
fifteen-second attempts timed out; the bounded process dump showed the second
ordinary package CLI still running under `vinix-session`, before SDK creation.
Existing managed-prefix modes retain fifteen seconds. Earlier source-edit,
bootloader and timeout failures remain preserved. Shared account-source churn
caused a correct audit refusal, so final qualification uses isolated tree base
`63fc675f1` plus archived `final-probe.patch`; the three changed files match the
root commit. Host compilation retains `-prod -gc none -manualfree`, with host
LTO disabled. The prepared runtime/PE were reused, freshly signed/published/
installed; prior complete producer/kernel bundles remain required.

Sources, isolated tree, all attempts, generated artifacts and complete final
native input byte snapshots are frozen at `/Users/alex/.cache/vwmanager-20261114-01`.
Use `selected-inputs-05` for the successful case; earlier snapshots correspond
to failed inputs. Preserve original namespaces and dependency bundles too.

Typed receipt:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-manager-death-20261114-01.inventory.json`,
SHA-256 `05da626283782d591e293c9d327fd8b72bc52d1fb469f13a99b1aae35d396268`.
Recording and independent verification pass with adjacent logs. Preserve the
entire frozen workspace, isolated tree and referenced original input bundles.

This qualifies one SDK-manager SIGKILL with a surviving holder. Holder death/
kernel-owned retention, full session teardown, ARM ownership, fresh owned GUI,
default activation and broader failure/topology/heap/hermetic gates remain open.

## Signed prefix relaunch, 2026-11-14

Source `c0d3fd3cf` adds `--owned-manager --relaunch-probe` for signed x86
same-generation recovery. It first exercises caller/SDK SIGKILL, server
adoption and foreign-owner refusal using the prior observer checks. Generation
1 stays active in this mode. After releasing the old worker, Wine retires
naturally, the fixture targeted-reaps the holder with status 137, all tracked
old processes disappear, and an exclusive lease probe succeeds.

The fixture writes a private-prefix sentinel, then invokes the real package
CLI again on the same active generation. The retained release marker lets the
fresh worker retire. The second launch must return 37 with exactly one initial
readiness, worker readiness and worker retirement marker, preserving sentinel
bytes. A fail-closed process scan must find no generation-runtime command line,
and the exclusive generation lease must again be free. Only afterward do real
remove/rollback transactions make generation 1 obsolete; collection removes it
while retaining rollback. This mode does not claim live obsolete-generation
collection; the separate manager-death mode continues to qualify that case.

`native-01` passes uninterrupted in 229.799 seconds with parsed-source,
selected-input and generated-output rechecks. All eighteen architecture/mode
refusal controls pass. The positive relaunch command has a 180-second bound;
existing refusal bounds remain unchanged. No runtime, kernel or sandbox policy
was changed. The guest and actual CLI were rebuilt; prepared runtime/PE inputs
were reused and freshly signed/published/installed.

Complete evidence is frozen at `/Users/alex/.cache/vwrelaunch-20261114-01`,
including isolated source base `2143d1fb8` plus `probe.patch`, generated artifacts
and complete native input byte snapshots. The three changed files match the
root commit. There are no failed attempts in this bundle. Original producer/
kernel bundles and namespaces remain required; historical audits are unchanged.

Typed receipt:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-prefix-relaunch-20261114-01.inventory.json`,
SHA-256 `b4ff0c2786ed73ee9360634395297cc5e347772e8e07b03754e38f38c15602a8`.
Recording and independent verification pass with adjacent logs. Preserve the
entire frozen workspace, isolated tree and referenced original input bundles.

This qualifies same-generation prefix reuse. Migration of absolute builtin
links between runtime generations remains open, along with holder death,
session teardown, ARM ownership, fresh owned GUI, default activation and broad
failure/topology/heap/hermetic gates.

## Runtime binding review, 2026-11-14

Source `6560bcd6f` adds `wineadapter.review_prefix_bindings()` and the standalone
`wine-prefix-review PACKAGE_STORE PRIVATE_DATA NEW_BUILTINS` utility. Run as the
prefix owner, it reports format-1 structural binding rows with observed and
replacement paths, selected generation, runtime identity and at most one prior
generation. Already-current bindings report prior generation zero. It opens
existing directories without following symlinks and checks prefix ownership,
directory identities, ordinary new assets, canonical generation paths and exact
basenames. It refuses foreign stores/runtimes, multiple prior generations,
linked new assets/directory components and ordinary files replacing prefix links.
It creates no directories and changes no prefix content or launch behavior.

The host binding tests and actual compiled CLI control pass, including unchanged
prefix snapshots, repeatable report cleanup, canonical generation/overflow
controls and the refusal cases above. Existing prefix tests also pass, including
their 1000-iteration controls; measured heap flatness is not claimed. Static Linux
x86_64 and AArch64 builds pass. Those binaries were not executed in guests, and
the signed Wine fixture was not rerun for this read-only utility. Earlier fixture
ownership, compilation and initial cross-link diagnostics remain in the bundle
alongside the passing final logs.

Evidence is frozen at `/Users/alex/.cache/vwbindreview-20261114-01`, including
final sources, copied host compiler, generated C, binaries and logs. This is not
a complete hermetic compiler/source closure. The typed receipt is
`/Users/alex/Library/Caches/vinix-codex/section14/wine-binding-review-20261114-01.inventory.json`,
SHA-256 `7232d1f65e3d0551ec1d3c131210ba2aacb15fcdf0e3e42024b834ffba5af22c`.
Recording and independent checking both pass complete bytes, sizes, types,
modes and link targets; adjacent record/check logs retain the results.

This review neither authenticates runtimes nor authorizes migration, and is not
a snapshot against concurrent mutation. Actual migration still needs fresh
authentication, idle-server admission, lease/launch serialization, rechecks and
interruption recovery. Migration application, holder-death retention, session
teardown, ARM owned Wine, fresh owned GUI acceptance and default activation
remain open; this checkpoint does not complete roadmap section 14.

## Omitted builtin links, 2026-11-14

Source `fcace5dad` closes a gap in the read-only binding review: checking only
the new runtime's names could overlook a link to a DLL removed by an upgrade.
The review now inventories system32 (at most 4096 entries) and refuses extra
absolute links into the selected package store's generation namespace. The
target need not exist or have a canonical generation spelling to be refused.
It preserves ordinary personal files and links outside that namespace, without
classifying those additions as signed builtins or deleting any entry.

Host library and CLI controls pass for old-generation, selected-generation and
malformed-generation extra targets. Refusal controls now run through the actual
CLI as well as the library, requiring exit 1 and the expected diagnostic.
Prefix snapshots confirm no changes on refusal; positive controls retain private
file contents and an unrelated personal link. Linux x86_64 and AArch64 static
cross-builds pass; no guest execution, signed Wine rerun or heap measurement is
claimed. The production launch path remains unchanged, and migration application
and the other section 14 gates above remain open.

Evidence is frozen at `/Users/alex/.cache/vwbindreview-20261114-02`, including
final source copies, generated C, host/target binaries and logs. Compiler identity
uses the exact compiler preserved in the preceding `-01` bundle; complete
hermetic source closure is not claimed. The receipt is
`/Users/alex/Library/Caches/vinix-codex/section14/wine-binding-review-20261114-02.inventory.json`,
SHA-256 `883a2d92f84d75a2d936cb4df8292abb25a6db2505ffa33e0158406399ad06af`.
Recording and independent checking pass complete bytes, sizes, types, modes and
link targets, with adjacent record/check logs. The preceding bundle is intact.

## Added builtin bindings, 2026-11-14

Source `1f8845883` extends the structural review to runtime inventories which
add DLLs. Each binding now has an operation: `keep` for a selected-generation
link, `replace` for a prior-generation link, and `create` for a missing entry.
Only `readlinkat` failure with ENOENT permits `create`; it records empty observed
text and a proposed target without creating a link. Existing files, directories
and unrelated dangling links at selected names remain refused. Prior generation
zero means no observed prior-generation bindings, and can accompany additions.

Host library/CLI tests pass, including JSON operation encoding, empty observed
text, unchanged prefix snapshots, repeatable cleanup, mixed create/replace/keep
rows and all three collision refusals through both interfaces. Linux x86_64 and
AArch64 static cross-builds pass; they were not guest-executed. The production
launch path is unchanged. Authentication, serialized migration application,
interruption recovery and the other section 14 gates remain open.

Evidence is frozen at `/Users/alex/.cache/vwbindreview-20261114-03`, with final
sources, generated C, binaries and build/test logs. The compiler binary remains
in the preceding `-01` bundle; complete hermetic closure and measured heap
flatness are not claimed. The typed receipt is
`/Users/alex/Library/Caches/vinix-codex/section14/wine-binding-review-20261114-03.inventory.json`,
SHA-256 `a1fd18fdb955bba277c02dce2226935351261b22fb780d7297283cc173502bd9`.
Recording and independent checking pass complete bytes, sizes, types, modes and
link targets; adjacent logs retain both results. Earlier bundles remain intact.

## Idle binding review coordination, 2026-11-14

Source `41fabf068` adds `capture_idle_binding_review()` and an opt-in `--idle`
mode for `wine-prefix-review`. The library capture holds the existing managed
launch guard, captures the private server namespace and checks idle admission
around structural review. Its `recheck()` requires identical binding rows and
an idle, unchanged namespace; repeatable `close()` releases owned descriptors
and report storage. The capture has one owner and excludes cooperating managed
launches while held. Unlike default read-only inspection, capture can create
coordination files/directories inside an existing prefix. It rewrites no builtin
links and starts no Wine process. CLI exit releases its guard: JSON cannot carry
idle admission forward to another command.

Host library/CLI tests pass: competing launch refusal, child-owned POSIX lock
refusal and recovery after retirement, unexpected endpoint refusal without
deletion, replaced lock identity, changed bindings/inventory, descriptor cleanup,
failed-capture guard release and the preceding review controls. Builtin snapshots
stay unchanged. Earlier test compilation and pipe-width handshake diagnostics
are retained; the corrected fixture uses C-width descriptors and a five-second
readiness bound. Linux x86_64 and AArch64 static cross-builds pass; no new guest
execution, signed Wine qualification or measured heap flatness is claimed.

Evidence is frozen at `/Users/alex/.cache/vwidlebind-20261114-01`, including
source copies, copied compiler, generated C, binaries, logs and earlier diagnostic
samples. The typed receipt is
`/Users/alex/Library/Caches/vinix-codex/section14/wine-idle-binding-review-20261114-01.inventory.json`,
SHA-256 `7094c609c7fcafaf8df7d81520a25c6419610738f4a8f9f58fb578e334c236de`.
Recording and independent checking pass complete bytes, sizes, types, modes and
link targets; adjacent logs retain the results. Complete hermetic source closure
is not claimed. The production launch path remains unchanged. Runtime
authentication, migration application and interruption recovery remain open,
alongside the other section 14 gates. Arbitrary same-account writes remain
possible; callers must hold no POSIX locks on the server lock file, because
F_GETLK does not report the caller's own locks.

## Binding directory continuity, 2026-11-14

Source `052d2aa08` retains system32 and builtin directory descriptors throughout
an idle review capture, comparing device/inode identities before and after
fresh structural review. Capture now performs that recheck before returning.
Host library/CLI tests pass, including replacement directories with identical
contents, restoration, descriptor cleanup and previous idle controls. Both
Linux architecture static cross-builds pass; no guest execution is claimed.

Evidence is frozen at `/Users/alex/.cache/vwidlebind-20261114-02`; its receipt is
`/Users/alex/Library/Caches/vinix-codex/section14/wine-idle-binding-review-20261114-02.inventory.json`,
SHA-256 `f8ef83e5736631f861f8d61a19f00a05d87836553e0a7fe50d312144aca90c1a`.
Record and independent check pass complete bytes, sizes, types, modes and link
targets, with adjacent logs. Final source copies and generated C/binaries are
included; the compiler binary remains in the preceding `-01` bundle. Complete
hermetic closure and measured heap flatness are not claimed. Directory continuity
does not pin individual assets or authenticate runtime bytes. Migration
application, recovery and the other section 14 gates remain open.

## Builtin byte continuity, 2026-11-14

Source `dc8129f30` records and rechecks SHA-256 digests for selected builtin
assets through captured-directory, no-follow opens. Reads use 64 KiB buffers,
require ordinary nonempty files up to 64 MiB each and cap the inventory at 1 GiB.
Pre/post-read metadata and EOF checks refuse observed read instability. Host
library/CLI controls pass, including same-size byte edits, restoration, a
65537-byte streaming comparison, empty-file refusal and previous cleanup checks.
Both Linux static cross-builds pass; no guest execution is claimed. Initial
compile and cleanup diagnostics are retained alongside passing corrected results.

Evidence is frozen at `/Users/alex/.cache/vwidlebind-20261114-03`; receipt
`/Users/alex/Library/Caches/vinix-codex/section14/wine-idle-binding-review-20261114-03.inventory.json`
has SHA-256 `00953c9078740656b248d7297496e72fa729a4e937ac664cca9c25bdcd04bacf`.
Recording and independent checking pass complete bytes, sizes, types, modes and
link targets. Final outputs use `-fixed` suffixes. The compiler binary remains
in the earlier `-01` bundle. These are continuity checks, not authentication of
initial runtime bytes or a concurrent-write snapshot. Migration application,
recovery, measured heap qualification and the other section 14 gates remain open.

## Expected builtin inventory, 2026-11-14

Source `780819bea` adds exact expected-inventory comparison to an idle capture,
matching runtime ID, generation, unique names, SHA-256 digests and byte counts
after a fresh capture recheck. Expectations are borrowed, not retained or
authenticated by this API. Host tests pass for exact input and mismatched hash,
size, name, runtime, generation and incomplete inventory. Tests use the retained
V compiler with `-backend c -gc none -manualfree` and repository module path.
This checkpoint has no new CLI, cross-build, guest or heap measurement claim.
An initial test syntax compilation failure is retained with final passing logs.

Evidence is frozen at `/Users/alex/.cache/vwinventory-20261114-01`; receipt
`/Users/alex/Library/Caches/vinix-codex/section14/wine-expected-inventory-20261114-01.inventory.json`
has SHA-256 `ee8c88e711d8f400fa9b5821d909b422b0cd9a59b2cf66d3f99a15c19e8cf63e`.
Recording and independent checking pass complete bytes, sizes, types, modes and
link targets. Package-service authentication integration, generation lease
retention, migration application and recovery remain open. Section 14 remains
incomplete; accepting a caller-supplied inventory alone establishes no trust.

## Retained runtime admission, 2026-11-14

Source `2fab29c31` adds `Service.wine_admission()`, retaining prepared package
state and its shared generation lease while exposing the selected runtime
manifest. It requires an ordinary account and installed real root, validates
state, selects an explicit Windows runtime dependency and invokes the existing
launch payload/policy/publisher-key verification. Close retires the owner once.

Host tests pass for valid runtime selection, wrong application/runtime kinds,
missing dependencies/packages, alternate-root refusal and descriptor close/reuse
safety. Built using the retained V compiler with `-backend c -gc none
-manualfree` and repository module path. These controls do not exercise a
successful signed installed-state admission, collection contention or guest
execution; those remain required before integrating migration. Prefix capture,
expected-inventory conversion, application and recovery remain open.

Evidence is frozen at `/Users/alex/.cache/vwadmission-20261114-01`; receipt
`/Users/alex/Library/Caches/vinix-codex/section14/wine-runtime-admission-20261114-01.inventory.json`
has SHA-256 `b6c9d8644b869e96834e0755e13fdd42caa209d4b15439d3ca11bedc2c67ffc7`.
Record and independent check pass complete bytes, sizes, types, modes and link
targets. This bundle contains the new sources, generated host C/binaries and
logs; complete source closure, cross-builds and measured heap flatness are not
claimed. Section 14 remains incomplete.

## Manifest-to-prefix bridge, 2026-11-14

Source `d78e07ea0` adds `Service.wine_prefix_review()`: one owner retains runtime
admission and idle prefix capture, derives builtin paths and expected hashes and
sizes from the runtime manifest, and compares them before returning. Close
releases prefix coordination before the generation lease. Host tests pass for a
synthetic admission, matching manifest, changed DLL refusal, empty/nested
inventory refusal, alternate-root refusal and descriptor/guard cleanup. Prefix
links remain unchanged. Tests use the retained V compiler with `-backend c -gc
none -manualfree` and repository module path. They do not qualify a successful
signed installed-state admission, collection contention, cross-build or guest
execution. No production launch integration or migration application is claimed.

Evidence is frozen at `/Users/alex/.cache/vwbridge-20261114-01`; receipt
`/Users/alex/Library/Caches/vinix-codex/section14/wine-manifest-bridge-20261114-01.inventory.json`
has SHA-256 `bff05ef7aece17aa609b72d77650ef869e7e1656e8495c4e28241e69e8a898ae`.
Recording and independent checking pass complete bytes, sizes, types, modes and
link targets. New source copies, generated host C/binaries and logs are retained;
complete source closure and measured heap flatness are not claimed. Signed
end-to-end qualification, migration application/recovery and the remaining
section 14 gates stay open.

## Persisted prefix-review lease, 2026-11-14

Source `194c95f1a` extends the host bridge controls with persisted generation
state decoded through `generation_lease()` under a package reader lock. The
combined review owns the real shared flock lease after the reader lock retires.
The collector's captured lease cannot acquire an exclusive lock before or after
review recheck; after repeatable owner close, it acquires that lock and passes
collection identity checks. Prefix coordination can also be acquired again.
The complete host bridge tests pass with the retained V compiler, `-backend c
-gc none -manualfree` and repository module path. Earlier missing-lock and
incorrect runtime-entrypoint fixture failures remain with final passing logs.

Evidence is frozen at `/Users/alex/.cache/vwleasebridge-20261114-01`; receipt
`/Users/alex/Library/Caches/vinix-codex/section14/wine-prefix-real-lease-20261114-01.inventory.json`
has SHA-256 `796f3be416aec33ec9ca52549bad765edfc6c6127d2db09635a05252079db6d2`.
Recording and independent checking pass complete bytes, sizes, types, modes and
link targets. New source copies, generated host C/binaries and logs are retained.
This verifies real lease ownership and collector-lock contention, not signed
publisher/payload admission, generation removal, cross-builds, guest execution,
complete source closure or measured heap flatness. Signed admission qualification,
migration application/recovery and the other section 14 gates remain open.

## Collection during prefix review, 2026-11-14

Source `626cd8d9c` extends the persisted-state host test through actual
`collect_locked()` calls under the package writer lock. Activation moves to
generation 3 with no rollback protection for generation 2. Three collection
attempts retain generation 2's builtin bytes while the combined review holds its
lease; review rechecks pass each time. After owner close, collection removes
generation 2, preserves generation 3 and its activation pointer, and leaves the
private prefix link text unchanged. The full host bridge test passes using the
retained V compiler with `-backend c -gc none -manualfree` and repository path.

Evidence is frozen at `/Users/alex/.cache/vwcollectbridge-20261114-01`; receipt
`/Users/alex/Library/Caches/vinix-codex/section14/wine-prefix-collection-20261114-01.inventory.json`
has SHA-256 `50f4f547b6a51dbddce81b59228abf4718707b1ab97637ea3fda63e0fdf30db9`.
Record and independent check pass complete bytes, sizes, types, modes and link
targets. Initial fixture-directory creation failure is retained beside passing
corrected logs, generated host C/binaries and new source copies. This qualifies
local collection retention/removal, not signed publisher admission, Wine
execution, cross-builds, guest behavior, complete source closure or measured
heap flatness. Signed service qualification, migration application/recovery and
the other section 14 gates remain open.

## Launch verification before prefix review, 2026-11-14

Source `e1c735889` materializes the persisted fixture's declared application and
runtime closure plus canonical desktop registration, then invokes the same
`verify_launch_payloads()` used by service admission. Positive verification,
revoked publisher-key refusal, undeclared runtime-entry refusal, changed
registration refusal and same-size DLL tamper refusal pass. Restored payloads
verify before the combined review, retained lease and actual collection tests.
The complete host bridge tests pass using the retained V compiler with
`-backend c -gc none -manualfree` and repository module path.

Evidence is frozen at `/Users/alex/.cache/vwverifybridge-20261114-01`; receipt
`/Users/alex/Library/Caches/vinix-codex/section14/wine-prefix-launch-verification-20261114-01.inventory.json`
has SHA-256 `03294574b04c0717be66888a27de93702134f330ff058cfe3b84c4e0ebf23cc6`.
Recording and independent checking pass complete bytes, sizes, types, modes and
link targets; new source copies, generated host C/binaries and logs are retained.
Provenance is locally constructed fixture metadata, not signed repository
publication/install or successful real-root service admission. No cross-build,
guest execution, complete source closure or measured heap qualification is
claimed. Signed service qualification, migration application/recovery and the
other section 14 gates remain open.

## Signed install and upgrade review, 2026-11-14

Source `f7ec0a197` adds a local signed-repository host fixture: generate a key,
pack separate Windows/runtime packages, publish a signed index, refresh trusted
metadata and install generation 1. Private service preparation acquires its real
lease and verifies the installed closure before manifest-to-prefix capture.
The initial review reports a current binding; close releases coordination.
A second signed publication upgrades the runtime to 2.0.0, changes one DLL and
adds another. Verified generation 2 reviews the preserved generation-1 prefix
as exactly one replacement and one creation. Recheck passes, old link text stays
unchanged and the new link remains absent. All host bridge tests pass using the
retained V compiler with `-backend c -gc none -manualfree` and repository path.

Evidence is frozen at `/Users/alex/.cache/vwsignedbridge-20261114-01`; receipt
`/Users/alex/Library/Caches/vinix-codex/section14/wine-signed-prefix-review-20261114-01.inventory.json`
has SHA-256 `767d97ab6e37492c456feb168fc72322560c64ad2648850d6208261968de82e4`.
Record and independent check pass complete bytes, sizes, types, modes and link
targets. Source copies, generated host C/binaries and logs are retained; final
upgrade evidence is `tests-upgrade.log`. An earlier attempt to run before build
completion is retained separately. Test payloads are marker files, never
executed. This qualifies signed publication/install/upgrade and review components
in an alternate-root fixture. Public real-root service admission, Wine execution,
guest/cross-architecture behavior, complete source closure and measured heap
qualification remain unproven here. The public alternate-root refusal is intact;
migration application/recovery and other section 14 gates remain open.

## Fresh service review admission, 2026-11-14

Source `549d27d83` adds `WinePrefixReview.recheck()`. It reloads configuration
under the package reader lock, requires the retained generation to remain
active, repeats launch payload/publisher/policy verification against the retained
state and rechecks adapter continuity. Construction performs this before return.
This differs from the adapter-only `owner.review.recheck()`, which cannot refresh
package trust or activation. Neither call authorizes a subsequent unguarded write.

The signed install/upgrade host fixture passes fresh recheck, publisher-key
revocation refusal, active-generation change refusal, restoration/retry and
closed-owner refusal, alongside prior bridge and collection tests. It uses the
retained V compiler with `-backend c -gc none -manualfree` and repository module
path. Evidence is frozen at `/Users/alex/.cache/vwfreshreview-20261114-01`;
receipt `/Users/alex/Library/Caches/vinix-codex/section14/wine-fresh-prefix-review-20261114-01.inventory.json`
has SHA-256 `87a26d1d8b6fb84696122a9f354f74eca04c7e6999a40202d7aa82cc2f1b1bb6`.
Record and independent check pass complete bytes, sizes, types, modes and link
targets. New source copies, generated host C/binaries and logs are retained.
Public real-root admission, actual Wine/guest execution, cross-builds, complete
source closure and measured heap qualification are not claimed. Migration
application/recovery and the remaining section 14 gates stay open.

## Installed review command, 2026-11-14

Source `5e3316b2f` exposes `vinix-package wine-prefix-review ID PRIVATE_DATA`.
The command uses combined service admission, rechecks freshness, emits JSON and
releases its retained guard/lease on exit. It rejects alternate roots (including
explicit `--root /`), offline/progress options, bad argument counts, invalid IDs
and relative private paths. It can create coordination files/directories but
changes no builtin links and starts no Wine process. JSON carries no admission
beyond command exit. The existing standalone structural utility is unchanged.

The production host CLI build and eight executable refusal controls pass. Builds
use the retained V compiler, `-backend c -gc none -manualfree`, repository and
`tools/accounts` module paths; CLI adds `-prod -cflags -fno-lto -ldflags -fno-lto`.
The initial missing account-module path build failure is retained. Evidence is
frozen at `/Users/alex/.cache/vwpublicreview-20261114-01`; receipt
`/Users/alex/Library/Caches/vinix-codex/section14/wine-public-prefix-review-20261114-01.inventory.json`
has SHA-256 `2e40bf434ad8e0dbdf6183e2081323da5e6365747b1f1b5154245bf5aab7a66e`.
Recording and independent checking pass complete bytes, sizes, types, modes and
link targets. New source copies, generated host C/binaries and logs are retained.
No successful real-root CLI admission, cross-build, guest/Wine execution,
complete source closure or measured heap qualification is claimed. Migration
application/recovery and the remaining section 14 gates remain open.

## Same-generation metadata freshness, 2026-11-14

Source `dbabc6dbe` compares canonical encodings of decoded active state and the
retained admission state under the package reader lock. A matching generation
number alone no longer permits changed manifests/provenance. Signed host fixture
tests pass for same-generation runtime version change refusal, whitespace-only
JSON acceptance, restoration/retry and changed organization allowlist refusal,
alongside preceding review/collection controls. Tests use the retained V compiler
with `-backend c -gc none -manualfree` and repository module path.

Evidence is frozen at `/Users/alex/.cache/vwmetareview-20261114-01`; receipt
`/Users/alex/Library/Caches/vinix-codex/section14/wine-metadata-review-20261114-01.inventory.json`
has SHA-256 `a63788b9a7aef91b75a6711689878b3dd5752c5bc14756012fdc83a1ebff53a6`.
Recording and independent checking pass complete bytes, sizes, types, modes and
link targets. Source copies, generated host C/binary and logs are retained. No
new production CLI build, cross-build, real-root admission, guest/Wine execution,
complete source closure or measured heap qualification is claimed. Migration
application/recovery and remaining section 14 gates stay open.

## Public Linux cross-build checkpoint, 2026-11-14

At source checkpoint `c8837b1067210017c0ac7dab37828e0856617f82`, the complete
public `tools/packages/main.v` CLI generates Linux C for AMD64 and ARM64.
Initial LLVM/musl links fail on the retained V library's `os.Process` waitpid
call: its zero-initialized status local is emitted as i64 while libc expects
int*. Compatibility links with `-Wno-error=incompatible-pointer-types` pass on
both targets, producing static x86-64 and AArch64 ELFs. That flag already appears
in native compatibility userland tooling. No compiler source or generated C was
patched. This does not qualify strict builds or runtime correctness of that ABI
boundary; it is not a clean default staging-build result.

Evidence is frozen at `/Users/alex/.cache/vwlinuxreview-20261114-01`; receipt
`/Users/alex/Library/Caches/vinix-codex/section14/wine-public-linux-review-20261114-01.inventory.json`
has SHA-256 `002ed561cfcaa06d2777683fd089f72b0312ab32fd462f4e6f3de6f95b19239f`.
Recording and independent checking pass complete bytes, sizes, types, modes and
link targets. Exact generated C, strict failures, compatibility logs, binaries,
partial source copies and validation flags are retained. Generation uses the
retained V compiler with repository/account module paths, `-prod -gc none
-manualfree`, standalone Linux defines and target architecture. Links use LLVM,
the repository musl sysroots/GCC 14.2.0 runtime and execute_capture_nix.c.
No guest execution, real-root admission, complete source closure or measured
heap qualification is claimed. Migration application/recovery and the other
section 14 gates remain open.

## Exclusive builtin additions, 2026-11-14

Source `e8041305b` adds explicit library `complete_additions()` methods on the
adapter capture and service owner. The service retains a package reader lock
through fresh admission and writes; the adapter retains prefix coordination,
refuses any replacement row before writing, creates links using exclusive
symlinkat and captured system32, updates its report, rechecks and synchronizes
the directory. No existing entry is overwritten or deleted. Partial progress
can be resumed through fresh capture, where matching links become keep rows.
This is not atomic across links and supplies no existing-link retarget operation
or CLI write command. Low-level callers still authenticate inputs and hold leases.

Host adapter tests pass for simulated interruption after one creation, resumption,
repeat calls and preservation of a personal-file collision appearing after
capture. Signed install/upgrade service tests pass for replacement-row refusal
without addition, explicit fixture preparation of the additions-only state,
creation and repeated calls. The fixture itself retargets the old link; the API
does not. Both test binaries pass with the retained V compiler, `-backend c
-gc none -manualfree` and repository module path. No actual SIGKILL/power-loss,
guest execution, cross-build or measured heap qualification is claimed here.

Evidence is frozen at `/Users/alex/.cache/vwadditions-20261114-01`; receipt
`/Users/alex/Library/Caches/vinix-codex/section14/wine-builtin-additions-20261114-01.inventory.json`
has SHA-256 `53dd6bd9bc535a083552ab5105fc64fde2c93ae8a8129c0daa29d75614abf81c`.
Recording and independent checking pass complete bytes, sizes, types, modes and
link targets. New source copies, generated host C/binaries and logs are retained;
complete source closure is not claimed. Existing-link migration/recovery,
real-root/guest qualification and the other section 14 gates remain open.

## Addition writer SIGKILL, 2026-11-14

Source `e04f3c3cf` adds an actual host process-death control. A forked child
captures the prefix and calls the unmodified additions API for 128 new builtins.
The parent observes the first link (ten-second bound), stops the child, requires
strictly partial progress and competing-launch refusal, then kills/reaps it with
SIGKILL. A fresh capture must recover coordination, count exactly the remaining
create rows and finish all links while preserving a private sentinel. The run
passes at 1/128 links before interruption, then completes the remaining 127.
All adapter tests pass using the retained V compiler with `-backend c -gc none
-manualfree` and repository module path. Cleanup kills/reaps a surviving fixture
child on failure. Production mutation code is unchanged by this checkpoint.

Evidence is frozen at `/Users/alex/.cache/vwkilladditions-20261114-01`; receipt
`/Users/alex/Library/Caches/vinix-codex/section14/wine-additions-sigkill-20261114-01.inventory.json`
has SHA-256 `ce06aea33f8bd39c5d85b731ecd64484a231f6e9fd5be02ee1ade0cc06793f97`.
Recording and independent checking pass complete bytes, sizes, types, modes and
link targets. Source copies, generated host C/binary and logs are retained.
This qualifies additions-only host process interruption, not power loss,
service-owner/guest execution, retargeting, complete source closure or measured
heap behavior. Existing-link migration/recovery and the other section 14 gates
remain open.

## Bounded addition rehashing, 2026-11-14

Source `9fd19dad6` removes a full inventory/payload recheck from each creation
iteration. Full checks still bracket creation and synchronization; each link
checks idle admission, captured directory identities and its target digest before
exclusive symlink creation. Payload rereading is a constant number of inventory
passes plus one read per addition, rather than one inventory pass per addition.
Non-target concurrent changes can refuse at the final check after partial work;
this remains an explicitly resumable, non-atomic multi-link operation.

Adapter and signed-service host tests pass, including changed-target refusal
before creation, personal-file collision preservation and actual SIGKILL
recovery. The interrupted writer installed 1/128 links; fresh capture completed
the remainder in 93 ms in this run. This is an observation, not a comparative
speedup claim. Tests use the retained V compiler with `-backend c -gc none
-manualfree` and repository module path. Evidence is frozen at
`/Users/alex/.cache/vwlinearadditions-20261114-01`; receipt
`/Users/alex/Library/Caches/vinix-codex/section14/wine-linear-additions-20261114-01.inventory.json`
has SHA-256 `c68b0f9a84270d9f31c8c8c99160b7349ef761af61fc37b6ae99dac6d2a3994b`.
Record and independent check pass complete bytes, sizes, types, modes and link
targets. Source copies, generated host C/binaries and logs are retained. No new
cross-build, guest execution, power-loss durability, complete source closure or
measured heap qualification is claimed. Retargeting/recovery and other section
14 gates remain open.

## Explicit additions command, 2026-11-14

Source `e25d945c1` exposes `vinix-package wine-prefix-additions ID PRIVATE_DATA`
through the existing service owner. It performs real-root admission and fresh
recheck, invokes the guarded additions-only method and prints resulting JSON.
The review command still performs no builtin writes. Existing-link retargeting
remains refused; interrupted additions use fresh review and explicit retry.

The production host CLI and V refusal runner build successfully. All sixteen
executable controls pass across review/additions commands: argument counts,
alternate roots including explicit slash, offline/progress flags, invalid IDs
and relative paths. Builds use the retained V compiler with `-backend c -gc
none -manualfree`, repository/account module paths; CLI also uses `-prod
-cflags -fno-lto -ldflags -fno-lto`. This checkpoint does not claim successful
real-root CLI execution, new service tests, guest execution or cross-builds.
Previously recorded signed service/additions and host SIGKILL controls remain
bounded evidence for the underlying method, not this CLI's installed success.

Evidence is frozen at `/Users/alex/.cache/vwaddcli-20261114-01`; receipt
`/Users/alex/Library/Caches/vinix-codex/section14/wine-additions-cli-20261114-01.inventory.json`
has SHA-256 `95c8d5b2720d9d94b61350846b708f4ed4d15d5c43cc77f3db4ae615924cdfb7`.
Recording and independent checking pass complete bytes, sizes, types, modes and
link targets. New sources, generated host C/binaries and logs are retained;
complete source closure and measured heap qualification are not claimed.
Retargeting/recovery, real-root/guest acceptance and other section 14 gates stay
open.

## ARM real-root prefix commands, 2026-11-14

Source `ebc9312be` adds the PID-1 guest probe and a runner taking
`NEW_WORK ARCH KERNEL COMPILED_CLI COMPILED_GUEST`. The probe generates a key,
packs marker Windows/runtime packages, signs and installs them at the guest's
actual root, then sheds groups and switches to UID/GID 1000. The ordinary child
prepares a prefix, removes one builtin link, and executes the public review,
additions, repeated additions and final review commands. Review must leave the
link missing, additions must create its exact signed target, and private sentinel
data must survive. Both exact success markers pass in the AArch64 VM in 5.827 s.
This exercises successful public real-root admission and fsync-backed additions,
not just the private alternate-root host components. Marker binaries are never
executed; no Wine/translation or graphical acceptance is established.

Evidence is frozen at `/Users/alex/.cache/vwguestprefix-20261114-01`; successful
result/serial/QEMU evidence is under `run-02`. The first boot's signing-seed
parent refusal remains under `run-01`; the corrected seed is in a mode-0700
root-owned directory. An initial host runner module-path build failure is also
retained. Receipt
`/Users/alex/Library/Caches/vinix-codex/section14/wine-prefix-arm-guest-20261114-01.inventory.json`
has SHA-256 `ff220821a49c19eacd0d9ff64b67c5104d34ade57905664bd6b4641145ee2776`.
Recording and independent checking pass complete bytes, sizes, types, modes and
link targets, including source copies, generated C, binaries, kernel copy and
boot artifacts. The retained kernel input is
`/Users/alex/.cache/vinix-wine-shared-pages-20261112/kernel-aarch64`.

CLI/probe C generation uses the retained V compiler, `-prod -gc none -manualfree`,
Linux standalone defines, ARM64 and repository/account module paths. LLVM links
against the repository AArch64 musl sysroot and GCC 14.2.0 runtime, with
`-Wno-error=incompatible-pointer-types` for the previously documented retained-V
waitpid boundary, plus execute_capture_nix.c. This is not strict-build, complete
source-closure, general ABI or measured-heap qualification. The runner accepts
precompiled inputs and is not a hermetic source admission checker. x86 guest
coverage, existing-link migration/recovery, power-loss durability and the other
section 14 gates remain open.

## Both-architecture prefix command refusals, 2026-11-14

Source `65bf2d28f` expands the PID-1 fixture to require public additions exit 1
while a managed launch guard is held, leave the missing link absent, then refuse
an ordinary personal DLL at that name without changing its contents. Releasing
the guard and removing the fixture collision permits successful creation and
repeat calls. The runner requires an additional exact refusal-success marker.
The signed-install real-root probe passes on x86_64 in 7.415 s and AArch64 in
5.734 s, retaining private data in both. Serial output records the managed-launch
and existing-symlink diagnostics. These are marker packages, not Wine execution.

Evidence is frozen at `/Users/alex/.cache/vwx86prefix-20261114-01`, with separate
`run-x86`/`run-arm` results, serial logs and QEMU artifacts. Receipt
`/Users/alex/Library/Caches/vinix-codex/section14/wine-prefix-dual-guest-20261114-01.inventory.json`
has SHA-256 `d91c413c90632a8bcb895803dcfe28441db5e1c09d9a2785a38e0d0b985bc163`.
Recording and independent checking pass complete bytes, sizes, types, modes and
link targets. Both kernel inputs are copied into the bundle: x86 uses retained
`/Users/alex/.cache/vpr-20261113-01/x86-production-01`; ARM uses the preceding
retained kernel. The ARM CLI is reused unchanged from the previous frozen guest
bundle; the expanded probes are rebuilt for each target. x86 CLI/probes use the
same retained V/LLVM-musl build flags and pointer-compatibility exception as the
preceding ARM report. This is not strict-build, complete source-closure, general
ABI, power-loss or measured-heap qualification. Existing-link migration/recovery,
actual Wine/translation acceptance and remaining section 14 gates stay open.

## Signed upgrade refusal in both guests, 2026-11-14

Source `ef4751dce` extends the real-root fixture with a second signed publication
and runtime upgrade to 2.0.0 after the ordinary account's initial additions pass.
The upgraded runtime changes a builtin and adds another; a fresh ordinary child
must successfully review generation 2 against its retained generation-1 prefix,
then require additions exit 1. Both original link targets and private sentinel
must survive, and the new extra link must remain absent. Serial output shows
generation 2/prior 1, two replacement rows, one creation row and the explicit
existing-link retarget refusal. Required upgrade and earlier success markers
pass on x86_64 in 8.041 s and AArch64 in 5.863 s.

Evidence is frozen at `/Users/alex/.cache/vwupgradeprefix-20261114-01`; receipt
`/Users/alex/Library/Caches/vinix-codex/section14/wine-prefix-upgrade-guests-20261114-01.inventory.json`
has SHA-256 `b82a2667fb4bf1c03f323aad071af9eefa233e3651f2e174719ba416d1477f06`.
Recording and independent checking pass complete bytes, sizes, types, modes and
link targets. Separate result/serial/QEMU bundles, generated probes, source
copies, CLI binaries and copied kernels are retained. Both unchanged CLIs and
kernels are reused from the preceding qualification; the expanded probes are
rebuilt with the retained V/LLVM-musl toolchains and documented pointer-type
compatibility flag. Marker payloads are never executed. This establishes
signed upgrade review/refusal, not existing-link migration, actual Wine,
power-loss durability, strict builds, complete source closure or measured heap
behavior. Retargeting/recovery and remaining section 14 gates remain open.

## Staged builtin retargeting, 2026-11-14

Source `3dc11504c` adds explicit library `migrate_bindings()` on the adapter
capture and service owner. The service retains package reader/lease and prefix
coordination while revalidating admission. Each old binding gets an exclusively
created selected-runtime stage at `wine/.vinix-builtin-next`, stage-directory
synchronization, fresh old-binding/stage checks and atomic rename into captured
system32, followed by synchronization of both directories. Matching staged work
is resumed first; unknown files or targets are preserved and refused. After
retargeting, exclusive additions finish the inventory. Repeated calls work.

This requires cooperating prefix writers to honor the guard; check-and-rename
cannot exclude arbitrary same-account filesystem writes. The operation is not
atomic across links and does not roll back partial progress. A fresh capture
can resume the same selected runtime with mixed prior/current links. No
retargeting CLI or automatic launch migration is enabled.

Final host adapter and signed service tests pass for real runtime-upgrade
retarget/addition, repeated calls, unknown-stage preservation, foreign-stage
refusal and simulated interruption after staging. The prior fixture's manual
retarget is replaced by the actual service method. Builds use the retained V
compiler with `-backend c -gc none -manualfree` and repository module path.
Evidence is frozen at `/Users/alex/.cache/vwretarget-20261114-01`; receipt
`/Users/alex/Library/Caches/vinix-codex/section14/wine-staged-retarget-20261114-01.inventory.json`
has SHA-256 `1aee6acc7888728ce1d0303e9c65c8f65c5bbafca70ecc24c4d6b1705ee75ae3`.
Recording and independent checking pass complete bytes, sizes, types, modes and
link targets, with source copies, generated host C/binaries and logs retained.
Actual retarget SIGKILL, guest/cross-build, power-loss durability, complete source
closure and measured heap qualification remain unproven. Those migration gates
and other section 14 requirements remain open.

## Retarget writer SIGKILL, 2026-11-14

Source `47805b6e4` adds actual adapter-process interruption during staged
retargeting. A child migrates 64 old-generation links; the parent observes the
first new target within ten seconds, stops the writer and requires strictly
partial progress. All 64 link texts at that stop must be old or selected targets,
and competing managed launch must refuse. After SIGKILL and exact child reap,
fresh capture must report the remaining old rows, finish migration, support a
repeat call and preserve private data. The run passes at 1/64 completed before
death, then resumes the remaining 63. All adapter tests pass using the retained
V compiler with `-backend c -gc none -manualfree` and repository module path.
The existing additions SIGKILL test also passes; production migration code is
unchanged by this checkpoint.

Evidence is frozen at `/Users/alex/.cache/vwkillretarget-20261114-01`; receipt
`/Users/alex/Library/Caches/vinix-codex/section14/wine-retarget-sigkill-20261114-01.inventory.json`
has SHA-256 `fa403c2c6c6e3431cd92a03d0d8d9d227c3988d7c2e1dd91511a9c9d41ed7bdb`.
Recording and independent checking pass complete bytes, sizes, types, modes and
link targets, with source copies, generated host C/binary and logs retained.
This qualifies adapter host process-death recovery, not service-owner lease
death, guest behavior, power loss, strict cross-builds, complete source closure
or measured heap behavior. Retargeting still assumes cooperating writers and
has no public CLI. Those gates and other section 14 requirements remain open.

## Staged migration in both guests, 2026-11-14

Source `1d9349204` extends the real-root signed-upgrade probe to acquire
`Service.wine_prefix_review()` as the ordinary account, call `migrate_bindings()`
twice, and require all rows current with prior generation zero. Every existing
and added DLL link must select generation 2. After owner close, public review
and additions commands plus normal prefix preparation must succeed, and private
sentinel data must survive. The runner requires an exact migration-success marker
in addition to the preceding installation/refusal/upgrade markers. x86_64 passes
in 6.876 s and AArch64 in 5.718 s. Migration executes through the newly compiled
probe's library API, not a new CLI command; automatic migration remains disabled.

Evidence is frozen at `/Users/alex/.cache/vwmigrateguest-20261114-01`; receipt
`/Users/alex/Library/Caches/vinix-codex/section14/wine-migration-dual-guest-20261114-01.inventory.json`
has SHA-256 `6a30139d8d8a2ffdf8f27b0c61c2e2fd670131498653f07698fed3004003b964`.
Record and independent check pass complete bytes, sizes, types, modes and link
targets. Both result/serial/QEMU bundles, generated probes, source copies, copied
kernel inputs and unchanged reused CLI binaries are retained. Builds use the
retained V compiler, `-prod -gc none -manualfree`, Linux standalone defines and
target architectures, then LLVM/musl with the documented pointer-type
compatibility exception and execute_capture_nix.c. This is not strict-build,
complete source-closure or measured-heap qualification.

Only marker payloads are installed; actual Wine execution/translation/GUI
compatibility is not exercised. Cooperating prefix writers remain an assumption.
Guest service-owner death and power-loss recovery, public retarget command
qualification and remaining section 14 gates stay open.

## Migration-owner death in both guests, 2026-11-14

Source `6e5616895` expands the signed real-root migration probe with 32 additional
old bindings. An ordinary child obtains full service admission and migrates;
its parent observes the first retarget, stops it and requires remaining old rows
with every sampled link either old or selected. A competing public additions
command must refuse. A separately opened generation lease must refuse exclusive
flock while the owner lives. After SIGKILL and exact reap, exclusive lease
acquisition must succeed, then release so fresh service admission can resume.
The resumed owner migrates twice, checks every target and private sentinel, and
passes public review/additions and prefix preparation. The runner requires an
exact owner-death success marker as well as all preceding markers.

x86_64 passes in 12.287 s and AArch64 in 6.686 s. Evidence is frozen at
`/Users/alex/.cache/vwownerkill-20261114-01`; receipt
`/Users/alex/Library/Caches/vinix-codex/section14/wine-owner-death-guests-20261114-01.inventory.json`
has SHA-256 `959056128e084b9c2951392264cc18af343e37adb0bccfe628e2cf9e9fc98e39`.
Recording and independent checking pass complete bytes, sizes, types, modes and
link targets. Both result/serial/QEMU bundles, compiled probes, source copies,
copied kernels and reused unchanged CLI binaries are retained. Builds use the
same retained V/LLVM-musl profiles and documented pointer-type compatibility
exception as preceding guest checks. No strict-build, complete source closure
or measured heap qualification is claimed. This proves process-death recovery
in these marker fixtures, not power loss, actual Wine/translation/GUI execution
or arbitrary same-account writer exclusion. No retargeting CLI or automatic
migration is enabled; those acceptance gates and other section 14 work stay open.

## Public migration command, 2026-11-14

Source `1be68013f` exposes `vinix-package wine-prefix-migrate ID PRIVATE_DATA`.
It shares review/additions argument, real-root and ordinary-account admission,
then explicitly invokes staged migration and emits the completed JSON report.
Automatic migration remains disabled. Cooperating-writer assumptions and
non-atomic multi-link/resumable semantics are unchanged.

The guest probe execs the CLI directly in the writer PID. It stops that actual
command after partial retargeting, checks its live prefix guard and shared
generation lease, kills/reaps it, verifies lease release, then resumes and repeats
through fresh public CLI invocations. Fresh service review verifies completion;
all targets, private data and normal prefix preparation pass. x86_64 completes
in 9.947 s and AArch64 in 6.351 s with all earlier markers plus a new exact CLI
recovery marker. The production host build and 24 executable refusal checks
across review/additions/migrate also pass.

Evidence is frozen at `/Users/alex/.cache/vwmigratecli-20261114-01`; receipt
`/Users/alex/Library/Caches/vinix-codex/section14/wine-public-migration-20261114-01.inventory.json`
has SHA-256 `e018a742784cd12bbd4c9e761167a703265c4c44f498ec42e79dd2eebde7c63a`.
Recording and independent checking pass complete bytes, sizes, types, modes and
link targets. New host/target CLIs, probes, generated C, source/kernel copies and
separate guest result/serial/QEMU artifacts are retained. Builds use retained V,
`-prod -gc none -manualfree`, repository/account module paths, Linux standalone
defines and LLVM/musl targets with the documented pointer-type compatibility
exception; host CLI uses the existing no-LTO flags. This is not strict-build,
complete source closure or measured heap qualification. Marker runtimes are not
Wine execution. Actual Wine/translation/GUI compatibility, power-loss recovery
and remaining section 14 work stay open.

## Public migration staging controls, 2026-11-14

Source `23fc6ecef` extends the public-command guest fixture with retained-stage
controls. An ordinary account puts a personal file, a nonempty directory and
a foreign symlink at `wine/.vinix-builtin-next` in turn. Each invocation of
`wine-prefix-migrate` refuses and preserves that entry, all 34 old builtin
links and private data, without creating the selected runtime's extra link.
The fixture then constructs a stage pointing at the authenticated selected
`new.dll`, whose row sorts after `base.dll`. When the public writer has
retargeted `base.dll`, `new.dll` must already be retargeted, demonstrating that
the retained stage was consumed first. The existing public-writer SIGKILL,
live guard/lease, fresh-admission resume and repetition checks still pass,
and no staging entry remains after completion.

Both guests pass the new exact marker and all earlier required markers:
x86_64 in 10.927 seconds and AArch64 in 6.419 seconds. The complete retained
bundle is `/Users/alex/.cache/vwstagecli-20261114-01`. Its typed inventory is
`/Users/alex/Library/Caches/vinix-codex/section14/wine-public-stage-20261114-01.inventory.json`,
SHA-256 `40db0c44083a946ce045956df3e442faac15de5ffa04f293c321df9986b553f4`;
recording and an independent comparison pass. Guest sources, generated C,
executables, runner, kernel inputs, build logs and boot evidence are retained.
The CLI executables are byte-identical copies from the preceding public
migration bundle (source `1be68013f`); only the fixture and checker changed.
Build flags and input identities are recorded in the bundle's build notes.

This checks reconstructed staging states through the real public command and
signed marker-package admission, not a power-loss event. Marker payloads never
execute Wine. The retained pointer-compatibility build exception remains;
strict compilation, complete build-input closure, measured heap behavior,
actual Wine compatibility and the other section 14 gates remain open.

## Bounded migration payload hashing, 2026-11-14

Source `6d85a6beb` removes two full-payload rehashes per replacement from
staged migration. Full authenticated payload checks still bracket the complete
operation. Each replacement retains all-row structural inspection, captured
directory identities and idle-server admission, but hashes only its selected
target before staging and again before rename. Digest and captured byte size
must match. Unrelated payload-byte changes may now refuse at the final full
check after recoverable partial progress. This retains the cooperating-writer
assumption; it is not an atomic transaction or arbitrary-writer exclusion.
Namespace inspection remains quadratic in row count; only payload hashing is
bounded independently of the number of replacement rows.

The committed `wine-prefix-migration-scale.v` diagnostic checks complete
retargeting, repeated migration, private data and staging cleanup with bounded
synthetic assets. Separately compiled baseline and candidate adapters pass a
sequential 64-row, 16 MiB comparison: migration takes 7.990 seconds before and
0.524 seconds after on this host. These are diagnostic timings, not a portable
performance threshold. A candidate 256-row, 64 MiB run also passes (8.164
seconds, in the initial concurrent diagnostic batch). All generated C,
executables, baseline sources and per-run logs are retained.

Focused host binding-review tests now apply their mutation/refusal controls to
both full review and per-replacement admission; signed service upgrade tests
also pass. Rebuilt CLI and guest probes pass all staging, signed marker-runtime
upgrade, guard/lease, SIGKILL/resume and repetition checks in x86_64 (17.597
seconds) and AArch64 (7.295 seconds). The runner and kernel inputs are unchanged.
The existing C pointer-compatibility exception remains; strict builds, complete
input closure and measured heap behavior are not qualified. Actual Wine
relaunch after migration, power-loss recovery and other section 14 gates stay
open. No real Wine launch was attempted in this scaling check.

Evidence is frozen at `/Users/alex/.cache/vwmigrationscale-20261114-01`.
Typed receipt:
`/Users/alex/Library/Caches/vinix-codex/section14/wine-migration-scale-20261114-01.inventory.json`,
SHA-256 `84afea79bbaf9ea9789e3bc5d56e14b03d2ccdf8481a130455d9872980dab029`.
Recording and independent comparison pass. Initial build/test-driver failures
and subsequent successful direct test builds are retained and explained in the
bundle's build notes. No historical bundle or auditor was changed.

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

At the original audit baseline, two publication paths prevented treating
`ECHILD` as a universal descendant barrier. The coordination fixes and
forced-ordering checks above address these findings; broader barrier and
abnormal-death requirements remain:

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

Both could leave a late child outside the ancestor's transferred list.
[`publish_user_thread`](../../kernel/sched/inherit.v#L54) does not repair parent
publication. Coordinated parent selection/adoption/exit fixes and focused
kernel regressions were prerequisites; merely forbidding `CLONE_PARENT` does
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
