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
