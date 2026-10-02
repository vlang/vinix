# Persistent seccomp audit collection

`vinix-security-audit` polls `/proc/security_audit` every 250 ms and appends
selected seccomp decisions to `/var/log/vinix-audit/seccomp.log`. The desktop
image starts its supervisor before applications. It requires root and the
kernel's initial-user-namespace CAP_AUDIT_READ authorization. Logs survive a
reboot when `/var/log` is on the persistent root filesystem; a tmpfs root cannot
provide persistence.

The collector uses bounded memory, accepts only the complete version 1 snapshot
format, refuses symbolic links and writable or non-root-owned ancestors, and
requires a regular root-owned 0600 log with one link. An exclusive advisory lock
prevents concurrent collectors using that file. Each changed batch is appended
and `fsync`ed before the collector advances its position. Idle snapshots do not
write. File and directory errors fail visibly on stderr; the supervisor retries.
These checks protect the log from unprivileged users. Privileged software can
still replace or alter it; this is not a tamper-evident remote audit service.

Each invocation writes a random `session_start` and each boot identity or source
counter reset writes a `boundary`. Snapshots without a kernel boot ID explicitly
use `boot=unknown`. A restarted collector uses a new session and may re-emit the
currently retained records; deduplication keys include boot, session, epoch and
sequence. `session_end` distinguishes a clean stop from a crash. Wall-clock
times are observational and are not trusted timestamps.

A `decision` is emitted once per sequence in a collector session. A later exit
update becomes `completion`. An incomplete event leaving the ring or remaining
at collector shutdown emits `outcome_unavailable`; it could describe a fatal or
non-returning call, not just a missed exit. `loss` names exact sequences never
observed, including events overwritten before collection began. `overwritten`
in a snapshot counts all kernel ring overwrites, including records successfully
collected earlier, and must not be interpreted as collection loss.

Rotate as root by renaming the log, creating a 0600 root-owned replacement and
sending SIGHUP to the collector. The new file begins with a `log_reopen` marker
carrying the existing session and epoch. Restarting instead writes a new session.
The collector checks the entire path again on rotation. Set a retention policy
and monitor available disk space for the deployment; there is no silent deletion
or automatic rotation of security evidence. A log write or `fsync` failure stops
collection, reports the error and leaves a best-effort error marker. An interrupted
write may leave a partial final line; the next session starts on a fresh line.

```sh
tests/security-audit/collector-run.sh
# Guest integration: build each architecture's kernel separately, then run:
python3 tests/kernel-gaps/run.py --source tests/security-audit/collector_vm_test.c \
  --arch aarch64 --kernel-dir /path/to/isolated/kernel \
  --expect 'SECURITY AUDIT COLLECTOR VM PASS' --fail 'SECURITY AUDIT COLLECTOR VM FAIL'
# One authorized snapshot, including a session end:
/usr/sbin/vinix-security-audit --once
```

`--interval-ms` accepts 10 through 60000. `--log` must be an absolute secure path;
`--source` selects a snapshot source for controlled diagnostics and still
requires authorization to read the canonical kernel audit endpoint. The helper
`build-support/security-tools/stage.py --arch aarch64 --staging /path/to/root`
packages a static collector and launcher using the target musl compiler. Both
userland and desktop image builders run this step.

This adds durable collection of the existing selected seccomp events. It does
not implement the Linux audit ABI, login attribution, general security event
coverage, a guaranteed lossless queue, or protection against boot artifact
replacement. The bounded producer continues overwriting when collection cannot
keep up, and lost records are reported explicitly.
