# Directory and procfs allocation regressions

Build the kernel in an isolated worktree with the pinned V compiler, then run:

```sh
VINIX_V_COMPILER=/path/to/v python3 tests/kernel-retention/run.py \
  --arch aarch64 --kernel-dir /path/to/kernel --state-dir /tmp/retention-arm-build \
  --guest-state-dir /tmp/retention-arm-guest
VINIX_V_COMPILER=/path/to/v CC_AMD64=x86_64-linux-musl-gcc \
  python3 tests/kernel-retention/run.py --arch x86_64 --kernel-dir /path/to/x86/kernel \
  --state-dir /tmp/retention-x86-build --guest-state-dir /tmp/retention-x86-guest
```

The runner builds the maintained V fixture and its immutable original C control
from Git, checks strict musl compilation and allocator imports, then boots each
in a fresh guest. It records source, executable and kernel hashes, serial hashes,
and exact C/V measurement rows. `--build-only` prepares both executables without
starting QEMU. The original shared harness's 180-second outer budget is retained;
the fixture has no internal deadline.

The guest creates 128 tmpfs entries and verifies complete, duplicate-free
enumeration through small `getdents64` buffers. A buffer too small for the first
entry must return `EINVAL` and leave that entry available for the next call.
After warming the paths, 200 listings and 200 rounds of six procfs reads must
retain zero objects in every slab class and zero large pages. The observer must
read all 18 ARM64 or 14 x86 classes before accepting a measurement.
The isolated boot disables its NIC so a DHCP lease and resolver text cannot
appear asynchronously in the measured heap.

With `ALLOC_TRACK=1`, the same test prints live allocation chains. The actual
ARM64 baseline retained 26,400 objects of 1,536 bytes in `getdents64` and 2,400
objects of 48 bytes across process stat/status, dynamic `/proc/self` targets,
uptime, maps and machine-stat text. The generated C confirmed temporary records
and text builders promoted to the heap. Explicit synchronous stack scratch
storage and consuming the owned text buffer remove those allocations without
adding frees or changing returned text. Both architecture guests pass with
every measured class exactly flat.

This covers these repeated paths. The broader ext2 and process-churn retention
measurements remain separate investigations.
