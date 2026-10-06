# Stat buffer retention

This native guest checks fstat and newfstatat output fields, AT_EMPTY_PATH,
EBADF, ENOENT, bad input pointers and bad output pointers. After warming the
same calls, each of three windows performs 300 iterations of eight raw system
calls. Every live heap class and its slab pages, the large-page count and
written-after-free counter must remain unchanged. Class-count guards cover all 18 ARM and 14 x86
classes. A monotonic 6.1-second grace cannot be shortened by an interrupted
sleep. Allocation-site output is included when the kernel has ALLOC_TRACK=1.

Build each kernel in an isolated worktree, then run from the repository root:

```sh
python3 tests/kernel-gaps/run.py --arch aarch64 --no-network \
  --source tests/stat-buffer/guestfixture/core.v --kernel-dir /path/to/arm/kernel \
  --expect 'XNU STAT PASS' --expect 'XNU STAT SEMANTICS PASS' \
  --fail 'XNU STAT FAIL' --timeout 180
python3 tests/kernel-gaps/run.py --arch x86_64 --no-network \
  --source tests/stat-buffer/guestfixture/core.v --kernel-dir /path/to/x86/kernel \
  --expect 'XNU STAT PASS' --expect 'XNU STAT SEMANTICS PASS' \
  --fail 'XNU STAT FAIL' --timeout 360
```

The initial defect retained one 192-byte heap object per call on both
architectures, including failures. An ARM `curl --version` cohort retained 3900
objects per 300 executions, all attributed to syscall_linux_fstat. The wrapper
scratch now uses the existing caller-stack macro and remains borrowed only
through synchronous filesystem filling and checked output conversion.

The independent fixture is maintained in V. Its declaration-only native ABI
header preserves the SDK's stat/timespec layouts and the original long and
long-long scanf/printf types. All 32 original check sites, diagnostic lines,
30 warmup iterations, three 300-iteration cohorts and grace periods remain.
Original C and V runs passed on both architectures with identical measurement
and verdict lines. Fixed buffers and synchronous stack borrows introduce no
allocator imports; the original target descriptor retains its process lifetime.
