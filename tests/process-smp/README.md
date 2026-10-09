# SMP process lifecycle acceptance

Build each kernel in an isolated worktree with the untracked dependencies
linked from the main checkout, as described in AGENTS.md. Enable `ALLOC_TRACK=1`
to print surviving allocation chains. AArch64 needs `LIMINE_MP=1`. Build and
boot both architectures; the runner does not rebuild the kernel.

```sh
python3 tests/process-smp/run.py --arch aarch64 --kernel-dir /work/arm/kernel --state-dir /tmp/process-arm
python3 tests/process-smp/run.py --arch x86_64 --kernel-dir /work/x86/kernel --state-dir /tmp/process-x86
```

The runner defaults to four CPUs and 4096 MiB of RAM, uses a static musl fixture
as init and requires `PROCESS-SMP PASS`. It disables networking and keeps
disposable boot artifacts and transcripts in its state directory. Use a fresh
directory for each run. AArch64 uses `VINIX_AARCH64_SYSROOT` (default
`build-aarch64-userland/sysroot`); x86_64 uses `CC_AMD64` (default
`x86_64-linux-musl-gcc`). Forty simultaneous timer owners exercise capacity
beyond the former 32-entry table. x86_64 threads each reserve two 2 MiB kernel
stacks, so this capacity test requires more RAM than the small paging fixtures.

The guest checks:

- `CLONE_VM` visibility through private mappings, shared break updates, new
  mappings and unmap; child exec/exit preserves the parent's map; private futex
  keys work across separate processes sharing that map. Unsupported sharing
  requests fail rather than silently changing ownership.
- Forty delayed vfork exits and forty execs release the parent only after the
  child writes shared state. Thirty killed creators leave their children able
  to use the shared map. The libc vfork wrapper is also exercised.
- Sixty cancellations across pipe read, nanosleep and condition-variable wait
  execute cleanup handlers and restore mutex ownership. Sixty robust-mutex
  owner deaths and joins exercise robust futex and clear-child-TID cleanup.
- Twenty batches of eight futex waiters survive fork/COW and wake correctly;
  timed futex waits report timeout. Sixty alternating thread/process signal waits
  preserve directed delivery. Forty signals queued before a sibling exists
  remain claimable by its later wait. Private signals cannot be consumed through
  another thread's sigwait/signalfd or advertised by its poll/epoll scan. Checks
  also cover simultaneous shared/private pending bits, failed siginfo writes,
  an inherited descriptor's blocking read, fork's empty pending pool and exec's
  preserved pool. Twenty vfork/exec handoffs send a signal for a newly created
  worker to consume.
- Real interval timers survive arming-thread exit and exec, remain absent in a
  fork child, preserve disarmed intervals and support forty concurrent owners.
  Four busy yielding siblings test one-shot deadlines and periodic phase.
- Two batches of 200 empty poll waits and two batches of 200 process-signal
  send/signalfd poll/read cycles compare every live slab class. After
  warmup, three cohorts of 100 fork/exec/exit cycles compare every slab class
  against a diagnostics control and require bounded physical-page retention.
  Retirement waits exceed the reader grace period. `PERF-SITE process-smp`
  lines identify retained allocations on a tracking kernel.

Run the remaining matrix on both kernels:

| Guest | Command following `python3` | Required result |
| --- | --- | --- |
| Job control, wait selection/restart, stop/continue and live-thread teardown | `tests/process-smp/run.py --arch ARCH --kernel-dir KERNEL --source tests/kernel-job-control/check.c --expect 'JOB-CHECK DONE failures=0' --state-dir STATE` | `JOB-CHECK DONE failures=0` |
| Returning detached threads raced against kill/exit_group | Same job command plus `--define JOB_TEARDOWN_ONLY=1 --define JOB_DETACHED_CHURN=1 --define JOB_TEARDOWN_PROCESSES=60 --define JOB_TEARDOWN_BATCHES=6` | `JOB-CHECK DONE failures=0` |
| Task/kernel-memory quotas, concurrent admission, pressure notifications, swap, OOM/fault/exit races and recovery | `tests/resource-groups/run.py --arch ARCH --kernel-dir KERNEL --smp 4 --state-dir STATE` | `CGROUP PASS` |
| Anonymous pageout/refault, COW and shared aliases under physical pressure | `tests/paging/run.py --arch ARCH --kernel-dir KERNEL --memory 256 --pressure --state-dir STATE` | `PAGING encrypted-disk-swapoff PASS` and `PAGING PASS` |

Also run `tests/posix-timer/run.py` on AArch64 and amd64, and the AArch64 desktop
performance scenarios `ops,churn,cache` and `idle,apps,drag` with
`VINIX_KERNEL_DIR=KERNEL`. Run `tests/kernel-allocs/run.sh`, compare failures to
the same-compiler baseline and do not expand the allocation allowance file.
The broader filesystem retention audit remains a separate roadmap item.

The [implementation and ABI limits](../../docs/process-smp.md) describe the
supported sharing combinations and lifetime rules.
