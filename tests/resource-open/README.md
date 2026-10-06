# Resource open dispatch regression

Build each kernel in an isolated worktree, then boot this guest with networking
disabled:

```sh
python3 tests/kernel-gaps/run.py --no-network --arch aarch64 --kernel-dir /path/to/arm/kernel \
  --source tests/resource-open/resourcefixture/core.v --expect 'RESOURCE OPEN: PASS'
python3 tests/kernel-gaps/run.py --no-network --arch x86_64 --kernel-dir /path/to/x86/kernel \
  --source tests/resource-open/resourcefixture/core.v --expect 'RESOURCE OPEN: PASS'
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

The independent fixture is V. Its native declaration header uses the actual
musl `termios`, `stat` and `dev_t` types; it contains no fixture implementation.
The generated object imports no allocator. The 53 original diagnostic sites
(52 on each architecture) and their predicates and line numbers remain intact.

For a strict SDK build and a paired run against the immutable original C
fixture, use a fresh build directory and short guest-state path:

```sh
python3 tests/resource-open/run.py --arch aarch64 \
  --kernel-dir /path/to/arm/kernel --state-dir /path/to/resource-build \
  --guest-state-dir /tmp/resource-arm
```

Use `--arch x86_64` for the other architecture, or `--build-only` for the SDK
checks. The reference comes from Git revision
`22c5d6ee193d107102888f359bfade8e34b592d2` into the build directory. The runner
preserves the original 180-second guest budget, checks every retention row,
and records source, kernel and program hashes in `validation.json`.

Both native original/V pairs passed: each of the two measured windows retained
zero objects in every class, zero large pages and zero written-after-free
events. Every numerical row matched the original. This fixture requires Vinix
device and `/proc` semantics, so desktop-host sanitizer execution is not a
substitute for these native checks.
