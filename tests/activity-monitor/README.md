# Activity Monitor process controls

The standalone guest checks process-wide suspend/resume with three busy threads
and one blocked sibling, blocked SIGCONT, repeated stop/continue notifications
from wait4 and waitid, killing a stopped process, nice, graceful SIGTERM cleanup,
and unprivileged signal/priority errors. Concurrent waiters verify that one reaps
and the other receives ECHILD; a 40-child test checks that every child can wake a
blocking wait. Every target is a child created by the test.

Build the desired kernel architecture first, then boot its regression:

```sh
python3 tests/activity-monitor/run.py --repo /Users/alex/code/vinix --kernel /tmp/worktree/kernel --arch aarch64
python3 tests/activity-monitor/run.py --repo /Users/alex/code/vinix --kernel /tmp/worktree/kernel --arch x86_64
```

`--repo` supplies the existing boot dependencies and userland sysroot; `--kernel`
supplies the already built isolated kernel. The desktop's owned-child action
tests are in `desktop/tools/tests/activity_controls_test.v`.

`metrics.c` checks advancing machine and per-core CPU counters, regular-file and
positioned logical I/O accounting, and INET UDP loopback payload counters.
`/proc/stat` uses USER_HZ=100. `/proc/activity_io` reports completed physical disk
bytes and INET payload bytes, including loopback and excluding Unix sockets and
protocol overhead. `/proc/<pid>/io` uses rchar/wchar for logical regular-file
bytes, read_bytes/write_bytes for physical I/O attributed to the submitting
thread, and net_recv_bytes/net_send_bytes for payload. Background writeback is
not assigned to the original writer. Physical completion accounting covers
AHCI, NVMe, ATA, VirtIO and Apple ANS storage.

The allocation allowlist records two Apple SMC device objects and two Resource
registrations: the existing battery and the new battery-power device. They are
created once and retained by their global pointers and devtmpfs for the kernel's
lifetime; repeated reads do not create devices. The installed V compiler also
reports allocation categories missing from the repository's older allowlist and
its x86 warning-only source scan has pre-existing import/interface errors. A
baseline comparison must distinguish those from new allocation sites rather
than accepting all warnings. The complete ARM scan introduces only the owned
battery-power object and registration; the new polling Text builders remain on
the stack. The guest regression measures every monitored procfs path directly.
