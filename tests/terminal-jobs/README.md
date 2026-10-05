# Terminal job control

The guest establishes a PTY session and tests background read/write/terminal
control permissions, blocked and ignored dispositions, TOSTOP, default stops
and foreground restart, Ctrl-C/Ctrl-Z group signals, and group/session
validation including successful exec. It checks one controlling terminal
per session and `/dev/tty` across detach and replacement. Repeated rejected
reads and controlling-terminal opens measure the guest slab before and after
1,000 calls. The SA_RESTART fixture delays input until after its handler
returns, requiring the restarted call to block again without a stale signal wake.
Stopped groups are resumed when setpgid or setsid orphans them. Session-leader
exit sends HUP/CONT to the foreground group, clears remaining members' terminal
identities and allows another session to claim the same terminal. Scalar group
and session holds cover terminal state and delayed signal delivery, preventing
PID reuse from redirecting them.

Both architecture guests pass. Controlling-terminal open loops stay flat:
ARM 1,552→1,552 KiB; x86 1,140→1,140 KiB. Before the optional-interface
dispatch fix, the ARM loop retained 16 KiB per 1,000 opens. Generated C now
uses one concrete stack slot with no interface `memdup`. Rejected reads stay
flat on ARM and retain one fixed 4 KiB warmup page on x86. The repository-wide
allocation allowance check still has the previously documented baseline failures.

The follow-up builds exposed V promoting synchronous 512-byte I/O locals to
heap allocations: 1,000 rejected reads retained 544 KiB on ARM and 584 KiB on
x86. Explicit caller-stack buffers remove those allocations. Both architecture
guests now pass the hangup and orphan-mutation cases. Terminal opens remain
flat (ARM 1,424→1,424 KiB; x86 1,004→1,004 KiB); rejected-read measurements
retain bounded measurement overhead (16 KiB ARM and 8 KiB x86), whose procfs
formatter sites have a separate repair workstream.

Dynamic terminal opens now retain their endpoint under the lookup/state lock,
and descriptor creation adopts that reference. A full descriptor table tests
100 failed opens and verifies every slave-open count rolls back. A mknod alias
also forwards the owned reference. Three threads race `/dev/tty` opens against
100 master closes, then use and close each returned descriptor. Allocation
tracking exposed a slave-close callback waking an already freed pair; a closer
hold now keeps the pair alive through wakeup and recursive pathname removal.
Both tracked architecture guests pass all 100 races with zero errors. After
six actual seconds of grace (including interrupted sleeps), slab usage falls
from 2,336 to 2,320 KiB on ARM and 1,188 to 1,164 KiB on x86. These builds
include the separate procfs, stat/poll scratch, and unpublished-thread fixes.
The generic VFS borrowed-node lifetime and retained mknod backing pointer
remain separate work; this result covers the controlling-terminal handoff.

Run `python3 tests/terminal-jobs/run.py`, or add `--arch=amd64`. Isolated
kernels and cached VM tooling use the same environment variables as
`tests/stack-policy/run.py`. The test requires four virtual CPUs.
