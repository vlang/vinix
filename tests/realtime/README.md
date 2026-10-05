# AArch64 real-time scheduling regression

This test boots a freshly built Vinix kernel on a four-CPU QEMU machine and
checks that a scheduling policy is something the scheduler acts on, not
something the syscalls merely remember.

The guest side runs as PID 1 and checks:

- `sched_setscheduler(2)`, `sched_getscheduler(2)`, `sched_setparam(2)`,
  `sched_getparam(2)`, `sched_get_priority_min/max(2)` and
  `sched_rr_get_interval(2)` carry policy and priority to and from a thread,
  refuse a priority a policy cannot have, and answer `ESRCH` for a thread that
  is not there. Only `SCHED_RR` reports a round-robin quantum.
- `SCHED_RESET_ON_FORK` is reported back in the policy and hands a forked child
  an ordinary `SCHED_OTHER` slot instead of its parent's real-time one.
- `/proc/self/stat` reports the policy and real-time priority in fields 41 and
  40, which is where `ps -c` and `top` read them from.
- With one CPU between them, a `SCHED_FIFO` thread takes it from a
  `SCHED_OTHER` one, a higher real-time priority takes it from a lower one, and
  `SCHED_IDLE` gets it only when the ordinary thread does not want it.
- `sched_setattr(2)` admits a `SCHED_DEADLINE` thread only when the machine can
  still keep every deadline it has already agreed to, and rejects parameters
  that do not fit inside each other. An admitted 2 ms in every 10 ms really is
  held to a fifth of its CPU: the ordinary thread it shares that CPU with comes
  out *ahead* of it, which no priority-based policy would allow.
- A runaway `SCHED_FIFO` 99 loop does not take a CPU away from everything else
  for good. The real-time bandwidth cap leaves the ordinary thread sharing that
  CPU the remaining 5%, which is what a shell would need to kill it.
- A `SCHED_FIFO` 80 thread sleeping to an absolute deadline over and over wakes
  up on time while every CPU on the machine is busy. The test prints the min,
  average and worst lateness over 500 cycles; the assertion is deliberately
  loose, because the number worth having here is the measurement rather than
  the threshold. See `docs/realtime.md` for what it has been.

The checks that share a CPU are the ones that mean anything, and all of them
depend on preemption: a thread busy in userspace has to be taken off a CPU by
the timer, with no syscall of its own to hand it over. Until the kernel gave
each CPU its own half of the interrupt controller, only CPU 0 could do that.

Build the AArch64 userland once to provide the musl test sysroot, then run:

```sh
./build-userland-aarch64.sh
tests/realtime/run.sh
```

Set `VINIX_QEMU_RT_NO_BUILD=1` to reuse `kernel/bin/vinix`, or
`VINIX_QEMU_TIMEOUT` to change the default 300-second deadline. The boot and
EXT2 images are isolated in temporary directories and removed after the run.

The lap counts are printed whether or not the check passes, along with the CPU
each thread was on, the affinity mask it was carrying and the policy it was
running under. A surprising split is nearly always a thread that never reached
the CPU it was sent to, and that is not visible from the counts alone.
