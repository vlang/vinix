# Concurrent procfs map lookup and listing regression

Two lookup threads read stable process entries while a third lists `/proc`,
the process directory, its `task` and its `fd` directory. Four cohorts of
12 live children force root-map growth, child-map lazy population and later
pruning. Each child stays alive behind a pipe until both a lookup and a full
directory snapshot have observed it. This exercises copied map values while
other CPUs add, compact and remove entries, including process magic links.

After growth and inspector threads finish, 200 repetitions of the stable
lookup/listing path must leave all 18 ARM or 14 x86 size classes, slab pages,
large pages and the write-after-free counter exactly unchanged. Dynamic-tree
growth itself is outside that window: current procfs pruning retains nodes.

Run the requested production kernel with the shared isolated-guest harness:

```sh
VINIX_QEMU_SMP=4 python3 tests/kernel-gaps/run.py --no-network \
  --source tests/proc-map-lookup/mapfixture/core.v --arch aarch64 --kernel-dir kernel \
  --timeout 1800 --expect 'VINIX PROC MAP LOOKUP: PASS'
```

Repeat with `--arch x86_64` and its kernel directory. Also run the
[thread-lock](../proc-thread-lock/README.md) and
[kernel-retention](../kernel-retention/README.md) regressions.

The independent V fixture preserves the original 221-line C oracle, including
all 25 failure diagnostics, the three inspectors, four 12-child cohorts,
600-second alarm, seven-second grace and exact retention checks. The native
binding contains SDK declarations and width constraints only. Generated C is
a build artifact; the original oracle is recovered from immutable Git revision
`47db8e1ce160c2829ad9df9fde6e1f1345d1f80c` outside the checkout for comparison.

Build and run both versions against the same kernel with the paired runner:

```sh
VINIX_QEMU_SMP=4 python3 tests/proc-map-lookup/run.py --arch aarch64 \
  --kernel-dir /absolute/isolated/kernel \
  --state-dir /absolute/new/evidence --guest-state-dir /tmp/proc-map-arm
```

Use `--arch x86_64` with its own kernel and fresh directories for the other
architecture. `--build-only` checks the actual musl SDK objects and static
executables without launching QEMU. The runner attaches the same serial
constructor to both versions, verifies their four cohorts and progress, and
compares every retained-class and large/UAF row. The complete workload requires
Vinix procfs behavior; a Darwin host compile is not a substitute for it.

Both original/V native controls passed on ARM with four CPUs and x86 with
two CPUs, using identical validated production kernels per architecture.
Every one of the 18 ARM and 14 x86 class live-object and page deltas was zero;
large-page and UAF deltas were zero as well. Original/V retention rows matched
exactly. Strict SDK compilation, static linking, the generated-object allocator
audit and independent lifetime review also passed.
