# Kernel resource exhaustion

Build both kernels in isolated worktrees, linking this checkout's untracked
kernel dependencies as described in AGENTS.md. Run the accounting and lazy-root
rollback host tests:

```sh
V=/path/to/v tests/kernel-resources/run-host.sh
```

The host suite exercises concurrent reserve/grow/shrink/release, owner limits,
global limits, fixed account exhaustion, stale generations, surviving creator
accounts and denied lazy-root allocation followed by retry and disposal.

Boot the native-page guest on each architecture:

```sh
python3 tests/kernel-resources/run.py --arch aarch64 --kernel-dir /path/to/arm/kernel --state-dir /tmp/resources-arm
python3 tests/kernel-resources/run.py --arch x86_64 --kernel-dir /path/to/x86/kernel --state-dir /tmp/resources-x86
```

Each state directory must be new. Images contain only disposable fixture files;
networking is disabled. The guest exhausts descriptors, mappings, files, sockets,
empty packet records, SysV semaphore/shared-memory registries, tmpfs attributes,
inotify instances, threads and processes. It checks message-queue removal,
epoll add/delete reuse, protection-split failure, shared-memory removal while
attached, failed ELF load cleanup, and that another workload can run afterwards.
It checks EOF-terminated scripts, bounded interpreter recursion, FIFO unlink
during blocking opens, dynamic PTY aliases, and PTY opens racing master close.
Overlay quota failures preserve source names and existing whiteouts, including
a late ACL failure; after releasing quota, creation and rename succeed.
A lazy shared mapping first faults after its creator has exited; a queued file
passed through SCM_RIGHTS is received and read after its creator has exited.

Accounting checks wait for the grace period and periodic reap. Released file,
descriptor, socket, IPC, mapping, process and scratch reservations must return;
the existing per-CPU dead-stack slots are allowed bounded retention.

Also run the existing private-page/pager/mapped-writeback host suites with
ASan/UBSan; the paging, resource-open and mapped-writeback QEMU regressions;
`tests/desktop-perf/run.py --scenarios=ops,churn,cache`; both architecture builds;
`tests/kernel-allocs/run.sh`; and desktop `idle,apps,drag` scenarios. Existing
allocation allowance failures and unrelated retention must be compared with
baseline rather than silently accepted into the allowance file.
