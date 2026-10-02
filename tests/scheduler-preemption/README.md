# Scheduler enqueue preemption

Ordinary enqueue now requests a scheduling interrupt on one eligible idle CPU
or a CPU executing lower-ranked work. Each CPU publishes only its effective
rank and deadline while holding its own thread's scheduling lock. Enqueue does
not borrow a remote thread pointer. The destination's existing policy scan
rechecks affinity, cgroups, deadline budgets and RT bandwidth before switching;
a stale snapshot can cause an unnecessary interrupt but cannot grant priority.
Pending requests coalesce until the destination enters its scheduler.

The implementation supports the existing scheduling ranks: SCHED_DEADLINE,
FIFO/RR priorities, ordinary work and SCHED_IDLE. Earlier absolute deadlines
can interrupt later deadlines. Equal FIFO priority does not request enqueue
preemption. Nice weights retain their existing timeslice behavior. Static
snapshots cover logical CPU IDs below 256; higher IDs retain timer dispatch.
There is no allocation or new lifetime on the enqueue/interrupt path.

x86 uses its existing scheduler APIC vector. ARM GICv3 uses Group 1 SGI 1,
encoded with the complete MPIDR affinity path. Without the optional GIC range
selector, Aff0 IDs above 15 retain timer dispatch. Idle GIC CPUs acknowledge
SGIs immediately after WFI wakes. Apple AIC retains SEV plus the existing
timer/poll fallback; a validated targeted Apple scheduler IPI is still needed.
Compatibility preemption guards and bounded timer fallback remain active.

Run the production policy selection checks:

```sh
VEXE=/path/to/v V=/path/to/v python3 tests/scheduler-preemption/policy.py
```

The host test extracts the production target-selection functions and models
CPU snapshots. It checks affinity, eligible idle preference, offline CPUs,
equal FIFO/normal priorities, SCHED_IDLE, earlier deadlines, coalescing and
retry after an unavailable controller. Mock atomics test the decision logic;
real multicore guests exercise actual atomic publication and interrupt delivery.

Build each architecture in a separate worktree, then run:

```sh
python3 tests/kernel-gaps/run.py \
  --source tests/scheduler-preemption/guest.c --arch aarch64 \
  --kernel-dir /path/to/arm/kernel \
  --expect 'SCHED-PREEMPT PASS' --fail 'SCHED-PREEMPT FAIL'
python3 tests/kernel-gaps/run.py \
  --source tests/scheduler-preemption/guest.c --arch x86_64 \
  --kernel-dir /path/to/x86/kernel \
  --expect 'SCHED-PREEMPT PASS' --fail 'SCHED-PREEMPT FAIL'
```

The guest pins a FIFO priority-1 pure-computation thread and a FIFO priority-50
futex waiter to CPU 1, while CPU 0 coordinates 64 wakes. Its direct counter
read avoids making syscalls in the busy thread. It requires actual sleeping
wakes and a median below 3 ms, separating enqueue dispatch from the incumbent's
5 ms timer. Every sample's tail remains reported: this is a latency regression
test under a virtual machine, not a hard realtime guarantee. Raw
`sched_setscheduler` is used because the available cross-musl POSIX wrapper
returns ENOSYS before issuing a syscall.

On the same x86 QEMU TCG guest, the pre-change median was 4.026 ms and p95
8.299 ms; enqueue preemption reduced these to 0.153 ms and 0.982 ms. All 64
wakes found the waiter sleeping. One post-change sample took 13.423 ms under
host scheduling, so tail latency still depends on the host and interrupt guards.

The final 32-bit pending-state version also passed both architectures with
concurrent guests: ARM QEMU/HVF median 26.041 microseconds, p95 4.309 ms,
64 sleeping wakes; x86 QEMU/TCG median 165.996 microseconds, p95 12.316 ms,
61 sleeping wakes. These tails reinforce the host-dependent limitation.
The full CPU timer/limit regression passed on x86 and ARM after the hardware
CPU-clock correction, including pure-userspace timers and native ARM signal
guard cases. Generated C for publication, selection and pending consumption
contains no allocator calls.

This closes the generic APIC/GIC portion of PERF6. CPU-local heap locking,
per-CPU run queues, coordinated QoS, heterogeneous placement, PI futexes,
deadline idle timers/coalescing and native Apple targeted IPIs remain separate
work (PERF1–5/7 and the remaining platform portion of PERF6).
