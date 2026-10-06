# Process inspection and thread attachment lock regression

Two inspector threads repeatedly read `/proc/<pid>/stat`, `status`, the main
thread's `comm`, and an explicit process CPU clock while their process creates
and joins 128 threads. They then inspect 32 children through their explicit
PIDs. Each child waits on a pipe until an inspector has read its `stat` and
`status`, then execs while inspection continues. The test checks inspection
data and requires concurrent progress; the runner's timeout also catches a
kernel-wide deadlock.

This reproduces a desktop freeze caused by inconsistent lock order: process
inspection took the process-table lock before the thread-list lock, while
thread attachment took them in reverse order. Both must take the table lock
first, including TID allocation and PID namespace numbering.

Build the requested kernel, then boot an isolated guest with:

```sh
VINIX_QEMU_SMP=4 python3 tests/kernel-gaps/run.py \
  --source tests/proc-thread-lock/lockfixture/core.v --arch aarch64 \
  --kernel-dir kernel --expect 'VINIX PROC THREAD LOCK: PASS'
```

Repeat with `--arch x86_64` and the x86-64 kernel directory. The shared runner
uses two CPUs for x86-64, which is enough to exercise the opposing lock paths.

The independent V fixture keeps all 14 original failure diagnostics, 128
sibling-thread joins, 32 gated child execs, architecture-specific yielding,
atomic publication orders and the 120-second alarm. Its binding contains
native SDK declarations and width constraints only; generated C is an artifact.

For a paired comparison, the runner recovers the original 174-line C fixture
from Git revision `8ca75d10e8b804cf26705ba9c04614965da81690` outside the checkout,
builds strict native musl SDK C/V executables, and uses the same kernel, serial
constructor and original 180-second outer budget for both:

```sh
VINIX_QEMU_SMP=4 python3 tests/proc-thread-lock/run.py --arch aarch64 \
  --kernel-dir /absolute/isolated/kernel \
  --state-dir /absolute/new/evidence --guest-state-dir /tmp/proc-lock-arm
```

Use `--arch x86_64` with its kernel and fresh directories for the other
architecture. `--build-only` stops after strict SDK compilation and static
linking. The full workload requires Vinix process clocks and procfs semantics.

All four original/V native controls passed with the same validated production
kernel per architecture: four ARM CPUs and two x86 CPUs. Both versions exceeded
the original 100-snapshot and 10-clock progress minima while completing all
thread joins and gated child execs. Strict SDK/static-link checks, the generated
object allocator audit and independent lifetime/ABI review also passed.
