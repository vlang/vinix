# Resource group acceptance

Build both kernels in isolated worktrees with the untracked kernel dependencies
linked from the checkout, as described in AGENTS.md. Run the host controller and
creator-budget tests:

```sh
V=/path/to/v tests/resource-groups/run-host.sh
```

The tests race 24 admission workers, check parent/child ceilings, migration
rollback and common-parent accounting, retired task-stack reservations, surviving
creator objects, pressure recovery, swap lifetime, rate arithmetic and overflow.

Boot the native fixture with a new state directory for each run:

```sh
python3 tests/resource-groups/run.py --arch aarch64 --kernel-dir /path/to/arm/kernel --state-dir /tmp/groups-arm
python3 tests/resource-groups/run.py --arch x86_64 --kernel-dir /path/to/x86/kernel --state-dir /tmp/groups-x86
```

The runner defaults to four CPUs (`--smp` overrides it), creates its own
disposable disk, enables encrypted swap and disables networking. The fixture
requires `CGROUP PASS` after concurrent thread/fork
admission, leader and worker exec at the PID ceiling, kernel-memory exhaustion
and retry, pageout/refault/PROT_NONE/unmap accounting, shared/private fork and
swap limits, memory-high delays, OOM recovery, memory migration rejection,
CPU user/system accounting, hierarchical disk pacing and limit removal,
independent/duplicated pressure subscriptions, poll/epoll wakeups, subscription
exhaustion, hierarchy removal/reuse and malformed limits.

Forty fresh OOM controllers also race 64 first-touch page faults against an
immediate `exit_group(77)`. Each victim must report SIGKILL and an `oom_kill`
event. This reproduces an ARM return-path bug: successful faults renewed the
quantum without checking pending signals, letting a victim reach exit before
its queued kill ran. Failures print the raw wait status for diagnosis.

After warming controller reads/writes and pressure opens, it repeats 200 batches
and waits beyond the reader grace period. `CGROUP SLAB` reports live-object
deltas for every heap size class. Both architecture acceptance runs kept every
class flat. Native pages are 16 KiB on AArch64 and 4 KiB on x86_64.

Also run the pager/private-page and mapped-writeback host suites, the pagecache
host suite, native paging and mapped-writeback regressions, both production
kernel builds, and desktop performance `ops,churn,cache` and `idle,apps,drag`.
`tests/kernel-allocs/run.sh` still fails inherited allocation allowance groups;
compare them with baseline without expanding the allowance file. This change
removes repeated cgroup text-builder heap promotion. Native device drivers other
than QEMU VirtIO/ATA require hardware validation.

The separate ANS media golden host suite currently fails before executing tests:
standalone V generation promotes storage-core temporaries to undeclared
`memdup` calls. The unchanged ANS source reproduces that compiler failure. The
production kernel builds validate the updated namespace-aware disk callback ABI.

The [interface and limits](../../docs/resource-groups.md) distinguish workload
quota recovery from retained mount-lifetime controller metadata.
