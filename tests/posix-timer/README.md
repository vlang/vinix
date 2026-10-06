# POSIX timer signal acceptance

Musl implements SIGEV_THREAD with a helper that blocks signal 32 and waits for
it using an untimed rt_sigtimedwait. The kernel queued the timer signal, but the
common event wait classified that blocked signal as a spurious wake and slept
again. The callback never ran. A timed raw wait consumed the signal only after
its timeout event returned control to rt_sigtimedwait.

The signal wait now passes an explicit interruption mask containing both its
requested signals and the ordinary unblocked signals. The common event code
uses that mask before sleeping and when classifying a wake, so the same fix
covers signals arriving before waiter attachment. An unrelated blocked signal
stays pending. Sigsuspend and AMD64 pause retain their existing interruption
mask by requesting no additional signals.

The independent guest is maintained in `timerfixture/core.v` and compiled
through the native libc ABI. Its original assertions and timing bounds remain
unchanged.

The guest covers:

- Twenty musl SIGEV_THREAD one-shot timers with the original core test's 20 ms
  deadline, exact single-callback assertion, and 100 attempts spaced 10 ms
  apart; deleting before expiry must retire the helper without a callback.
- Raw signal-32 SIGEV_THREAD_ID delivery to another pthread, with timed and
  untimed waits, SI_TIMER/value verification, and an elapsed-time bound of
  one second for the two-second timeout case.
- SIGEV_SIGNAL delivery, pending notification restoration after siginfo EFAULT,
  immediate EAGAIN after consumption, and periodic overrun metadata.
- An ordinary signal-32 wake and an unrelated blocked SIGUSR1 that must remain
  pending while a 40 ms timer wait times out.
- Forked timer ownership and refusal to target a thread of another process.

Build both architectures from an isolated worktree whose untracked kernel
inputs are linked from the prepared main checkout. Preserve each kernel and its
matching generated C before cleaning to switch architectures.

```sh
make -C kernel ARCH=aarch64 LIMINE_MP=1 ALLOC_TRACK=1 V=/path/to/v CC=clang
python3 tests/posix-timer/check-generated.py kernel/obj/blob.c
VINIX_VM_RUNNER_ROOT=/path/to/prepared/vinix \
VINIX_AARCH64_SYSROOT=/path/to/vinix/build-aarch64-userland/sysroot \
VINIX_KERNEL_DIR=/path/to/saved-arm-kernel VINIX_QEMU_RT_NO_BUILD=1 \
python3 tests/posix-timer/run.py --arch=aarch64

make -C kernel clean
make -C kernel ARCH=x86_64 LIMINE_MP=1 ALLOC_TRACK=1 V=/path/to/v CC=clang \
  LD_X86_64=/path/to/ld.lld
python3 tests/posix-timer/check-generated.py kernel/obj/blob.c
VINIX_VM_RUNNER_ROOT=/path/to/prepared/vinix \
VINIX_AMD64_KERNEL=/path/to/saved-amd64-kernel/bin/vinix \
python3 tests/posix-timer/run.py --arch=amd64
```

The pointer slot and array header stay on the caller's stack throughout the
synchronous wait. The existing timeout Timer is disarmed and freed after the
common await has detached its listeners. Untimed waits retain no event pointer.
The generated-C checker verifies that the slot is explicit caller storage and
that the wait/list wrappers introduce no heap allocation.

Baseline saved ARM and AMD64 kernels before this fix both fail the first musl
callback assertion with a zero remaining timer value. A separate raw timed
ARM baseline wait receives its 20 ms timer signal after 2.000114 seconds, at
the timeout. The corrected focused guests pass every case: raw timed and untimed waits take about 20–23 ms on ARM
and 20 ms on AMD64. Both allocation-tracked kernels build and pass the emitted-C
ownership check. `tests/kernel-allocs/run.sh` fails against the existing allowance
table with the same 416 distinct sites / 158 excess groups in the unchanged
`64bf1aa3` baseline and this patch; no allowance was changed. The full ARM core
test at source `64bf1aa3` passes its original SIGEV_THREAD assertion and all other
checks, then passes persistence verification after reboot. No assertions or timing bounds were weakened.

This change does not alter POSIX timer metadata locking, notification queue
semantics, timer owner lifetime, or clock discipline. Those broader mechanisms
are outside this wait-wakeup fix.
