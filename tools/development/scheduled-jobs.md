# Per-account scheduled jobs

`vinix-jobs` runs interval jobs as the account that owns the schedule. It pins
each executable, passes an argument array and a selected environment, bounds
execution time, and records completion times and exit status. It does not change
UIDs, capabilities, mount policy or resource-group membership. Existing kernel
permissions and inherited resource limits apply to every child.

```
v -enable-globals -gc none -cc gcc -o vinix-jobs tools/development/jobs.v
./vinix-jobs init jobs.json /home/developer/job-state
./vinix-jobs watch /home/developer/job-state
```

Use `run-due STATE` for a single scheduling tick or `status STATE` to inspect its
receipt. `watch` polls once per second and replaces its own process after each
tick to reclaim the tick's allocations under Vinix's `gc none` runtime. Jobs run
serially. The next run is scheduled one interval after the last completion;
missed intervals are coalesced. There is no backlog or overlapping replay.
SIGINT/SIGTERM retire an active owned child group before the runner exits.
Retirement allows up to eight seconds for cooperating development commands
to stop their own child groups, then applies the owned group's SIGKILL fallback.
`vinix-build` relays interruption through its active qualifier or compiler;
the qualifier has a one-second child shutdown window and the build runner
has five seconds. Each leader remains unreaped until its group is retired.

Export an existing schedule for the desktop's Services tab:

```
vinix-jobs service-unit /home/developer/job-state > scheduled-ci.service
```

Choose **Import Linux service…**, select the exported file, then **Start**.
Import leaves the service disabled until that action. **Stop** disables the
watcher and gives it ten seconds to finish its normal eight-second child
retirement window. The unit uses `Type=simple`, `Restart=on-failure` and the
current scheduler executable with literal `watch STATE` arguments. Export
validates the private account-owned schedule and the native unit contract,
without executing jobs or changing the schedule or service registry. Credentials
and job environment values stay in their existing protected files and plan.

Spaces, quotes and backslashes in paths are quoted for the native importer.
Dollar/percent expansion, control bytes and arguments exceeding its bounded
record size are refused before any unit is emitted. The same unit uses the
supported Linux service subset; full systemd qualification remains separate.
Session persistence uses the existing service manager. Persistent-home cold
boot and the complete native Services-managed scheduler lifecycle still need
their own qualification. An interrupted job retains its existing owner
acknowledgement requirement across service restarts.

For repeatable CI builds, set `expand_attempt: true` on the job and put
`{attempt}` in its output argument. For example, pin `vinix-build` as the
executable and use arguments
`["build", "/home/developer/project-build.json", "/home/developer/ci-{attempt}"]`.
Each dispatch then gets a new numbered output directory. Expansion applies
only to argument strings and performs no shell or environment evaluation;
it is disabled by default, preserving literal braces in existing jobs.

State records both completed `runs` and reserved `attempts`. The runner
persists the next attempt before starting the child, including attempts
that fail a pin/credential check or time out. A killed owner can therefore
leave an unfinished attempt without reusing its output on retry. Explicit
acknowledgement keeps the reserved number; the next dispatch advances it.
Older receipts without `attempts` continue after their completed run count.
Counter exhaustion refuses execution instead of wrapping back to an old path.

```json
{
  "schema": 1,
  "uid": 1000,
  "jobs": [{
    "id": "ci",
    "executable": {"path": "/home/developer/bin/ci-project", "sha256": "EXECUTABLE_HASH"},
    "arguments": ["--offline"],
    "directory": "/home/developer/project",
    "interval_seconds": 3600,
    "timeout_seconds": 900,
    "environment": {"CI": "1"},
    "credential_files": {"CI_TOKEN": "/home/developer/.credentials/ci-token"}
  }]
}
```

Set `uid` to the actual owning account and obtain the executable hash with
`vinix-build hash`. Configuration is executable code chosen by that account.
The private state directory must be new, owned by the account and mode 0700.
Configuration and state are written atomically with file and directory fsync.
A lock rejects concurrent runners. The copied plan's hash prevents silent plan
replacement; initialize a new schedule when changing jobs.

Credential files are referenced by path and read anew for each execution, so
rotation does not require rewriting the schedule. The opened descriptor must
refer to a regular file owned by the calling account, with no group/world
permissions. Symlinks, NULs and values over 64 KiB are rejected. Values are
passed as environment variables only to the selected job. The scheduler omits
them from receipts and discards child stdout/stderr; a job can explicitly write
its own results. Unselected inherited environment variables are omitted.

Private files are opened without waiting for a FIFO writer, then checked through
the opened descriptor before any read. A FIFO credential fails the reserved
attempt without launching the job or leaving it in flight. A FIFO at a stored
plan or state path promptly refuses inspection and execution. These refusals
preserve the path for inspection; they do not replace it or read pipe content.

The runner publishes an in-flight receipt before starting each job. If it is
killed before recording completion, the job remains blocked on subsequent ticks.
After checking that the interrupted job and its descendants have stopped, its
owner can run `acknowledge-interrupted STATE JOB` to permit another run. This
never signals a saved numeric PID and prevents an automatic overlapping retry
after the owner was killed. No system daemon or boot service is installed by
these commands; service integration and production SSH/server/CI qualification
remain separate acceptance work.

`v -enable-globals -cc cc test tools/development/jobcore` checks real job
execution, credential handling, interval coalescing, interrupted-run refusal,
executable pins and deadline retirement. These are host tests; Vinix guest
qualification is recorded separately by the
[native workflow controller](../../tests/development/README.md). Its x86_64
and AArch64 fixtures run the public scheduler as UID/GID 1000, check private
credential/receipt ownership, selected environment and discarded child output,
and refuse public/symlinked credentials. Native lifecycle checks also require
deadline and SIGINT/SIGTERM retirement of the active job and its descendant,
concurrent-owner refusal, repeated watcher ticks with a stable owner PID, and
blocked retry after a killed owner. Recovery is qualified only after the fixture
retires its freshly observed group and explicitly acknowledges the interruption.
The host controller independently checks the native state and exact plan pins.
Service/boot and production server/SSH/CI acceptance remain open.

Attempt reservation validation on 13 October 2026 passed the host job suite,
including literal arguments, fresh numbered outputs, acknowledged interruption,
legacy-state migration and counter exhaustion. AArch64 HVF retained the HTTP
reference and account/job/build regressions in
`build/development17-20261013/guest-arm-job-attempt-a` (19 records). The x86_64
TCG account/job/build run passed in `guest-x86-job-attempt-b` (12 records).
The controller checks one reserved attempt for ordinary/deadline/signal jobs,
two for watcher ticks, and two attempts with one completion after interrupted
recovery. The first x86 run, `guest-x86-job-attempt-a`, failed the existing
watcher-state read assertion; that failed receipt remains retained. A focused
guest test subsequently reproduced the VFS destination delete/publish gap
and concurrent map mutation. The [rename regression](../../tests/vfs-rename/README.md)
now passes 8,000 replacements per architecture, concurrent directory listings
and retained-descriptor checks beyond the retirement grace period. The final
kernels also passed the x86 HTTP/account/job gate and AArch64 scheduled Go CI
gate. The watcher fixture checks open before read so a failed open's errno is
preserved in future reports.

The [scheduled native Go CI gate](../../tests/development/README.md) passed
on AArch64 HVF on 13 October 2026 in
`build/development17-20261013/guest-arm-reference-ci-d`. The ordinary account
ran the pinned build CLI twice with expanded attempts, compiled and executed
matching Go projects, and verified that its private CI token stayed out of
build children and public evidence. A third reserved attempt refused an
existing output without changing its sentinel. The controller checked all
22 records, including exact job/plan pins and completion/failure counters.
Host nested CLI cancellation tests retired a compiler and descendant that
ignored TERM under both INT and TERM. These checks qualify the local reference
pipeline; service boot, remote CI, deployment and broader workflows remain open.

On 15 October 2026 a host regression reproduced a FIFO credential blocking
before the job's execution deadline was installed. Nonblocking open now reaches
the existing regular-file/owner/mode check immediately. The public CLI tests
cover credential, stored-plan and stored-state FIFOs without writers, retained
FIFO inodes, failed-attempt accounting, absence of job output and successful
execution after rotating back to a private regular credential. All three host
scheduler test files passed with V `be2eb40`. Static Linux ELF64 builds also
passed for ARM64 and x86-64, with checked machine IDs and source/compiler/binary
pins in `/tmp/vinix-jobs-fifo-8042`. Those host results are complemented by the
native qualification below.

The maintained native fixture now runs the FIFO cases and credential rotation
as UID/GID 1000 on every workflow check. On 15 October 2026 ARM64 HVF and x86-64
TCG both passed the extended account/job/build gate, retaining 14 independently
validated receipts each in `build/development-fifo-20261015/guest-arm` and
`guest-x86`. The controlled ARM64 build with nonblocking open removed failed
at the three-second FIFO deadline in `baseline-arm-b`, after passing the normal
account checks. The fixed builds settled the failed attempt, executed the
rotated credential's second attempt and retained the original FIFO inodes.
Deadline/signal retirement, watcher ownership, interrupted-run recovery and
the two matching build artifacts also passed. The native inputs and recorded
kernel compiler adaptation are detailed in the
[guest workflow instructions](../../tests/development/README.md).

Service export validation on 15 October 2026 passed all six scheduler/importer/
supervisor host test files with V `be2eb40`. The public CLI exported literal
paths containing spaces, quotes and backslashes; the imported disabled service
ran two real watcher ticks after enablement and stopped through the supervisor
model. Expansion/control/oversized paths and changed plans were refused before
output. ARM64 HVF and x86-64 TCG also passed native UID/GID 1000 export and the
full base account/job/build checks, retaining 14 validated receipts plus the
unit text and export verdict in each serial log. Evidence and static tool-stage
pins remain in `build/development-service-20261015/guest-arm`, `guest-x86`,
`tools-arm` and `tools-x86`. The runs reuse the isolated kernels and recorded
compiler adaptation from the FIFO validation above. Native desktop-managed
watcher lifecycle and persistent-home cold boot remain separate acceptance work.
