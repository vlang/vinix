# Seccomp security audit regression

Build the kernel, then boot `test.c` as PID 1 on aarch64 and amd64. A successful
run prints `SECURITY AUDIT PASS`. The test verifies LOG allows the call and
records its actual return, ERRNO records the denial, fatal actions remain
visible, credential/capability/user-namespace reader restrictions, stable
small reads while new events arrive, overflow counters, and retained slab
bytes after 10,000 producing calls and 1,000 collector opens.

```sh
make -C kernel CC=clang V=/path/to/v ARCH=aarch64 LIMINE_MP=1
python3 tests/kernel-gaps/run.py --source tests/security-audit/test.c \
  --arch aarch64 --kernel-dir kernel --expect 'SECURITY AUDIT PASS' \
  --fail 'SECURITY AUDIT FAIL'
```

Use an independently built x86_64 kernel and `--arch x86_64` for the second ABI.

`/proc/security_audit` is a non-destructive per-open text snapshot, readable
only by effective UID 0 with CAP_AUDIT_READ in the initial user namespace.
Authorization is checked on every read, including inherited descriptors.
Seek to zero to refresh the snapshot. The first line gives format version,
capacity, total records, retained records, and records overwritten by newer
events. The next line names the decimal fields. PID/TID are kernel IDs;
identity fields record real/effective UID/GID at the decision. IP is the
syscall instruction address reported by the architecture's entry hook.

The kernel retains the newest 128 selected seccomp actions without allocating
on the producer path. ALLOW is not recorded; LOG and denial/termination
actions are recorded. `completed=1` means the exit hook recorded the actual
kernel return and errno. Fatal calls, calls that do not return (such as exit
or successful exec), and a still-running call have `completed=0`; their result
and errno fields are not a completed outcome. Results are unsigned kernel
ABI values. A sequence that was overwritten cannot update a newer record.

This is initial structured security auditing, not a Linux audit netlink ABI,
a persistent collector, login/session attribution, or coverage of every
security decision. Collection does not block producers; overload overwrites
old records and increments the dropped counter.
