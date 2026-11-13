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
