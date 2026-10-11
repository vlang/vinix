# Security events: the kernel's record of decisions, kept

The kernel records what it decided about who may do what
([`kernel/security/events.v`](../../kernel/security/events.v)), and
`vinix-security-events` keeps that record on disk. This is beside the
[seccomp record](../security-audit/README.md), which holds system calls a
filter asked to have recorded; the two share a boot identity and nothing
else.

## What is recorded

| Kind | When | `arg`, `label` |
| --- | --- | --- |
| `policy` | Every [privileged operation](../../docs/security.md), allowed or refused: mount, unmount, host and domain name, clock, restart and power off, securelevel, giving the seat. | The selector, e.g. `system/hostname/set`. |
| `mac` | A mandatory domain refused an object. | Domain, object type and access packed in `arg`; `object` or `block-device`. |
| `seat` | A device of the seat refused to a process that does not hold it; the seat given to a login session. | The device's name; or the session and `seat-given`. |
| `login` | A login session began. | The uid that logged in. |
| `identity` | A change of user or group ids refused. | `setid`. |
| `signal` | A signal to someone else's process refused (not signal 0). | The target's pid; `kill`. |
| `network` | A bind to a port below 1024 refused. | The port; `bind`. |
| `file` | A hard link to a file the caller could neither own nor read and write refused. | The file owner's uid; `link`. |
| `service` | What a trusted service reports of its own decisions. The authentication service reports every one. | The reporting service's pid; the service's text, e.g. `auth:verify_sam:denied`. |

Every record carries the process and thread, the real and effective uid,
and the **login**: the uid that logged in and the number of the login
session ([`docs/accounts.md`](../../docs/accounts.md#logins-the-kernel-knows)).
The login is set once and survives every change of ids, so a refusal can be
traced to the person who logged in whatever the process had become by then.
A process of the system has no login. A `service` record is about the
process the service names -- its caller -- with that process' ids and login
at the time of the report, not the service's.

What is not recorded: ordinary permission failures on files (`EACCES` from
mode bits would drown everything else), pledge and unveil violations,
capability checks other than the ones above, and anything a confined domain
was allowed.

## The kernel's side

`/proc/security_events` is a snapshot of the newest 256 records, numbered
from 1 since boot, with a header saying how many there have been and how
many were overwritten. Reading it needs root, `CAP_AUDIT_READ`, the initial
user namespace and no mandatory confinement -- the rule of
`/proc/security_audit`. Producers never allocate and never wait for a
reader.

A service reports by writing one line, `<pid> <0|1> <label>`, as root with
`CAP_AUDIT_WRITE`, outside any login and any confinement. A label is at most
40 printable characters; anything else in it becomes `_`.

## The collector

    vinix-security-events            # until stopped
    vinix-security-events --once     # one pass

Four times a second it reads the snapshot and appends what is new to
`/var/log/vinix-audit/events.log`, one line a record, and syncs the file
before it counts a record as kept:

    event boot=<id> seq=412 ns=<since boot> collected=<unix time> kind=network result=denied pid=311 tid=311 uid=1001 euid=1001 login=1001 session=4 arg=80 label=bind
    loss boot=<id> first=6 last=149 count=144 collected=<unix time>
    boundary boot=<id> previous=<id> collected=<unix time>

- A record is written once. A collector that restarts reads the end of its
  own log and goes on from there; a line that was never finished (a kill, a
  power cut) is not counted, and what is appended starts on a new line.
- A **gap** -- records the kernel overwrote before they were read -- is
  written as a `loss` line with the exact numbers. A log never implies that
  nothing happened where something was missed.
- `collected` is the collector's clock when it read the record: not when
  it happened (`ns` is, on the kernel's monotonic clock) and not a time to
  trust more than the machine's.
- The directory must be root's and writable by nobody else, the log a
  regular file with one name, root's, mode 0600. Anything else is refused,
  not written into.

### Retention

`/etc/vinix/audit.conf`, root's:

    max_bytes = 4194304     # set the log aside when it has grown past this
    keep_files = 8          # how many set-aside logs to keep
    max_age_days = 90       # delete set-aside logs older than this; 0: never

Those are the defaults. A log is set aside as `events.log.1` at the pass
after the one that outgrew it, the others moving up a number; what is past
`keep_files` or older than `max_age_days` is deleted. Deleting evidence is a
decision, and these three numbers are the only place it is made.

## Limits

- Root can change or delete the log. This is a local record, not a
  tamper-evident one: there is no chaining, no signing and no copy elsewhere.
- Between two passes the kernel keeps 256 records. A burst larger than that
  is partly lost, and said to be.
- Nothing starts the collector at boot yet: a system that wants the record
  starts `vinix-security-events` beside `vinix-authd`.
- The log's lines are this tool's own format, not Linux's audit format;
  `ausearch` and its like do not read it.

## Tests

`eventcore/core_test.v` covers the snapshot parser (with malformed and
random input), what counts as new, gaps, reboots, resuming from a log and
the settings. `iotest/io_test.v` runs the built collector against snapshots
in a file: once-only writing, setting aside and deleting, half a line, and
what it refuses. The `audit` scenario of
[`tests/accounts`](../../tests/accounts/README.md) boots a kernel and checks
the real stream and the real collector.
