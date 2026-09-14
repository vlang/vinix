# Real-time scheduling

Vinix schedules by policy, not only by turn. A thread can be given
`SCHED_FIFO` or `SCHED_RR` at a priority between 1 and 99, or a
`SCHED_DEADLINE` budget of so much CPU in every period, and the scheduler acts
on it: a thread holding one of those is picked ahead of every thread that does
not, and can take a CPU from one that is already running.

This document says what that does and does not promise, because the difference
is the whole subject.

## What there is

| | |
| --- | --- |
| Policies | `SCHED_OTHER`, `SCHED_BATCH`, `SCHED_IDLE`, `SCHED_FIFO`, `SCHED_RR`, `SCHED_DEADLINE` |
| Real-time priorities | 1 to 99, higher first |
| Syscalls | `sched_setscheduler`, `sched_getscheduler`, `sched_setparam`, `sched_getparam`, `sched_get_priority_min`, `sched_get_priority_max`, `sched_rr_get_interval`, `sched_setattr`, `sched_getattr`, `sched_setaffinity`, `sched_getaffinity`, `sched_yield`, `setpriority`, `getpriority` |
| Reported in | `/proc/<pid>/stat` fields 40 and 41 (`rt_priority`, `policy`) |
| Granularity | Per thread, as on Linux: the `pid` these calls take is a tid, and 0 means the calling thread |
| Inherited | By `fork(2)` and by every thread `clone(2)` creates, and kept across `execve(2)` — so `chrt -f 50 ./program` gives the program the priority |
| Given up | By `SCHED_RESET_ON_FORK`, which hands children an ordinary slot |

The ordering between them, most urgent first: deadline threads with budget
left, then the real-time band by priority, then `SCHED_OTHER` and
`SCHED_BATCH`, then `SCHED_IDLE`. Ties are broken round-robin, except between
deadline threads, where the earlier deadline goes first.

`SCHED_FIFO` and `SCHED_DEADLINE` are not interrupted by an equal: a thread
under either keeps its CPU until it blocks, calls `sched_yield(2)`, runs out of
budget, or something ranked above it becomes runnable. `SCHED_RR` rotates
between equals every 5 ms, which is what `sched_rr_get_interval(2)` reports.

`nice` still scales an ordinary thread's timeslice, and does not touch a
real-time one: what a real-time thread is entitled to is decided by its
priority and by nothing else.

## What it costs everybody else

Two safety nets, both of which can be observed rather than taken on trust —
`tests/realtime` asserts each of them.

**Real-time bandwidth.** At most 950 ms of every second on a CPU goes to
real-time threads, Linux's default. Without a cap, a `SCHED_FIFO` loop at any
priority takes a CPU and never gives it back, and on a single-processor machine
that is the whole machine, including the shell that would have to kill it. A
throttled CPU does not stop running real-time threads; it drops them behind
every ordinary thread instead, so one holding a lock somebody else is waiting on
still gets to finish with it.

**Deadline admission control.** A `SCHED_DEADLINE` request is refused with
`EBUSY` unless the machine can still keep every deadline it has already agreed
to — at most 95% of one CPU between all of them. That refusal is what makes a
deadline a promise rather than another priority.

Both nets demote rather than stop. A thread that has spent this period's budget,
or a CPU that has spent this second's real-time bandwidth, drops behind the
ordinary threads instead of being taken off the machine — so a deadline thread
that has run out still runs when nothing else wants the CPU. Linux stops it
dead; leaving a CPU idle to enforce a budget nobody else is waiting for buys
nothing, and a real-time thread holding a lock is much better off finishing with
it. What the budget guarantees is therefore a ceiling on what the thread takes
*from others*, which is the guarantee the others needed.

## What it does not promise

Vinix is not a hard real-time system and this does not make it one. There is no
guaranteed worst-case latency, no priority inheritance on a contended futex, and
no interrupt thread a driver can be preempted in favour of. Long non-preemptible
sections in the kernel are bounded by nothing but how they are written.

What can be said is what has been measured. `tests/realtime` runs a
cyclictest-shaped loop: a `SCHED_FIFO` 80 thread sleeping to an absolute
deadline 500 times over, one millisecond apart, with every CPU on the machine
kept busy by ordinary threads. On a four-CPU QEMU machine under HVF on an Apple
laptop, across runs:

```
wake-up latency over 500 cycles against 4 busy threads:
  min 0 us, avg 105-590 us, max 5-12 ms
```

The average is the scheduler. The worst case is mostly the host, which is an
ordinary laptop running an ordinary operating system underneath and moves by
milliseconds depending on what else it is doing — which is exactly why nothing
here is a guarantee. Run the test on the machine you care about rather than
trusting these numbers; that is what it is for.

## How a CPU is taken back

Two mechanisms, and neither is an inter-processor interrupt, because this
architecture has no scheduler IPI yet:

- **The timeslice.** While any thread on the machine is scheduled by policy,
  every ordinary thread's timeslice is shortened to a millisecond. Coming
  through the scheduler is what lets a CPU notice a real-time thread waiting for
  it, so that interval is the machine's worst-case dispatch latency under full
  load.
- **The idle poll.** A CPU with nothing to run looks for real-time work every
  25 µs rather than at its 1 kHz idle tick, and brings the clocks up to date
  first — which is what expires the timer a sleeping real-time thread is waiting
  on. On a machine with a CPU to spare, this and not the tick is what bounds how
  long that thread waits.

Both are conditional on a thread somewhere having asked for a policy. A machine
where nobody has keeps the run-queue scan, the timeslices and the unhurried idle
poll it had before any of this existed.

## The part that had to come first

None of the above means anything on a CPU that cannot be interrupted, and until
recently only the boot CPU could be. The GICv3 driver configured the
distributor, its own redistributor frame and its own CPU interface — all of
which the other CPUs also need, and none of which they had. A thread busy in
userspace on any CPU but the first therefore ran until it made a syscall: its
timeslice never expired, an affinity change did not move it, and nothing more
urgent could take the CPU from it.

`gic.initialise_secondary()` gives each CPU its own half of the controller as it
comes up. Two details are worth keeping:

- It has to run *after* `memory.vmm_activate_on_cpu()`. Before that the CPU is
  still translating the higher half through the bootloader's tables, where the
  redistributor is not device memory.
- The MMIO accessors are marked `@[noinline]`. Inlined into a run of accesses at
  fixed offsets from one base — which is exactly what configuring a
  redistributor is — the compiler keeps the base in a register and folds the
  first offset into the store as `str w8, [x9, #0x80]!`. A store that writes its
  base register back leaves a data abort with no instruction syndrome, and a
  hypervisor with nothing to decode the access from; QEMU under HVF asserts and
  takes the machine with it.
