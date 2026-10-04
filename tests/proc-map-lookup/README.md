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
  --source tests/proc-map-lookup/test.c --arch aarch64 --kernel-dir kernel \
  --timeout 1800 --expect 'VINIX PROC MAP LOOKUP: PASS'
```

Repeat with `--arch x86_64` and its kernel directory. Also run the unchanged
`tests/proc-thread-lock/test.c` and `tests/kernel-retention/test.c` regressions.
