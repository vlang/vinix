# CPU interval timers, limits, and accounting

`check.c` is a Linux ABI regression guest for both supported 64-bit architectures.
It verifies `ITIMER_VIRTUAL` and `ITIMER_PROF` delivery, remaining values,
periodic expiration, disarming, sleep exclusion, a worker consuming a shared
process timer while its setter sleeps, and non-inheritance across fork. It also
checks SIMD preservation across asynchronous delivery while sibling threads
compete, bad selectors/timevals/pointers, separate user/system time in `getrusage`
and `times`, inherited CPU limits, repeated `SIGXCPU`, and a multithreaded
process killed at its summed hard CPU limit. Its computation loops deliberately
make no system calls while waiting for signals.
AArch64 also checks that native custom handlers stay at syscall boundaries while
fatal signals leave through an owned kernel stack.

After building an isolated AArch64 kernel with `LIMINE_MP=1` for SMP coverage, run:

```sh
python3 tests/kernel-cpu/run.py --repo=/path/to/vinix --kernel=/path/to/worktree/kernel --log=/tmp/cpu-regression.log
```

The repository argument supplies the existing QEMU firmware, small shell
initramfs, and AArch64 musl sysroot. Boot images and package state are temporary;
the runner stops its entire QEMU process group on completion or timeout. It
requires `CPU-CHECK DONE failures=0`, and rejects incomplete output.

The host arithmetic test extracts the production V functions and exercises
boundary equality, periodic phase/overruns, deadline saturation, microsecond
rounding, separate virtual/prof CPU bases, unlimited/zero limits, soft signal
rate, and hard-limit precedence:

```sh
V=/path/to/v python3 tests/kernel-cpu/logic.py
```

CPU timers are inline process state and add no per-tick allocation or retained
thread pointer. A fork starts with disarmed timers and fresh CPU counters while
inheriting its CPU limits. Exec preserves the process's timers and accrued CPU
budget. Signals are process directed; ordinary signals coalesce. Limit checks
run on scheduler ticks and user/kernel boundaries, so expiration is subject to
the scheduler's sampling delay. Zero CPU limits use Linux's one-second minimum.

User/system accounting includes time spent servicing the current process's
system calls, faults, and interrupt handling. AArch64 measures against its
architectural counter, independent of adjusted wall clocks; x86 reads its HPET
counter (or the existing calibrated TSC fallback). CPU-mode timestamps are
separate from the scheduler/cgroup tick clock: a PIT interrupt must not charge
the entire tick to system time and leave pure computation uncharged as user
time. Peak RSS, faults, I/O counts, and context-switch
counters are outside this change.

The existing `ITIMER_REAL` implementation's thread ownership and 32-entry
limit are separate from the new process-wide CPU timers.
