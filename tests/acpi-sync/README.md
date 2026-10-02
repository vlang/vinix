# Native ACPI synchronization

The production uACPI mutex/event callbacks use `kernel/acpisync`: nonrecursive
mutexes with checked ownership, counted events, reset, and zero/finite/infinite
waits. Event wakeups only prompt a permit check, so one signal permits one
successful wait even when the kernel event wakes several threads. Timer expiry
does not report a successful signal. Finite waits measure the hardware counter
and include the last partial IRQ tick; timeout zero never allocates or sleeps.

Before the scheduler exists, ACPI waits and sleeps poll the initialized HPET/TSC
clock and identify the only boot thread with a nonzero ID. Once the scheduler is
running, thread IDs distinguish concurrent AML owners and blocking waits sleep.
`Stall` measures the hardware counter rather than assuming a port read lasts a
microsecond.

Destruction requires the caller to quiesce every potential entrant. It refuses
a mutex that still has an owner and an event/mutex with live waiters/listeners.
This guard does not authorize destruction concurrently with a new invocation.
A refused destruction leaves the object allocated. A finite wait keeps its gate
waiter reference through event listener detachment and timer disarm/free; the
timer lock excludes concurrent expiry while removing the timer.

Run these tests with separate kernel worktrees and dependency links for each
architecture. Specify the same V binary for the generator and `VEXE`; the runner
sets both, forces the objects affected by optional test defines to rebuild,
saves the build log, and boots the existing isolated QEMU harness:

```sh
python3 tests/acpi-sync/run.py \
  --kernel-dir /path/to/arm-worktree/kernel --arch aarch64 \
  --v /path/to/v --state-dir /tmp/acpi-sync-arm
python3 tests/acpi-sync/run.py \
  --kernel-dir /path/to/x86-worktree/kernel --arch x86_64 \
  --v /path/to/v --state-dir /tmp/acpi-sync-x86
```

The optional in-kernel C tests call the actual production V functions. They
check bootstrap polling before scheduler initialization, timeout durations,
counter consumption and reset, wrong-owner releases, four concurrent mutex
owners executing 4,000 critical sections, one signal for four event waiters,
delayed finite and infinite waits, and refused destruction of active objects.
After warming timer/allocator capacities, 200 repeated create/wait/sleep/free
cycles compare every live slab class through a nonallocating observer.

Validated with V 0.5.2 `0dc6a69` (binary SHA256
`a1e6bba12b5dd50825df94610c8d71f75a2dcab24d15fd20fee2329abf56cf7d`)
on aarch64 QEMU and x86_64 QEMU. The tests require both the ACPI verdict and a
successful userspace init to verify that the machine still boots afterwards.

This fixes ACPI synchronization prerequisites for HW1. Device suspend/resume
ordering, CPU/interrupt restoration, S3 wake, runtime power dependencies, general
driver detach/rebind, and hibernation image/boot contracts remain separate work.
Deferred ACPI work and SCI interrupt installation also need real implementations
before firmware notifications and sleep events can be claimed to work.
