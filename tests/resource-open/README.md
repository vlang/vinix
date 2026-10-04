# Resource open dispatch regression

Build each kernel in an isolated worktree, then boot this guest with networking
disabled:

```sh
python3 tests/kernel-gaps/run.py --no-network --arch aarch64 --kernel-dir /path/to/arm/kernel \
  --source tests/resource-open/test.c --expect 'RESOURCE OPEN: PASS'
python3 tests/kernel-gaps/run.py --no-network --arch x86_64 --kernel-dir /path/to/x86/kernel \
  --source tests/resource-open/test.c --expect 'RESOURCE OPEN: PASS'
```

The guest checks locked-slave errors, a duplicate slave surviving master close,
mknod forwarding to an open factory and to a fixed device, ordinary files, and
reopening an anonymous pipe through `/proc/self/fd`. It then warms 200 PTY pairs
and measures two further cohorts of 200 pairs with both endpoint close orders.
Each cohort waits 11 seconds for removed VFS nodes to be reclaimed before
requiring exactly zero change in all 18 ARM64 or 14 x86 slab classes, large
pages, and the written-after-free counter.

Before the fix, each measured pair retained two 16-byte `OpenableResource`
dispatch adapters. The generated C allocated these with `memdup` when opening
the master and slave. The concrete stack dispatcher borrows their interface
tag and object only until the callback returns; callbacks keep ownership of
the endpoint `Resource` boxes. With `ALLOC_TRACK=1`, the same guest also prints
live allocation chains.
