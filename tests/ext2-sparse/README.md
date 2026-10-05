# EXT2 sparse and large-file regression

Run the production block-tree and inode read/write/resize algorithms against
fault-injected backing storage:

```sh
V=/path/to/v sh tests/ext2-sparse/run-host.sh
V=/path/to/v VINIX_HOST_SANITIZE=1 ASAN_OPTIONS=detect_leaks=0 \
  sh tests/ext2-sparse/run-host.sh
V=/path/to/v sh tests/pagecache/run.sh
```

The fixtures exercise 1 KiB and 4 KiB direct/single/double/triple-indirect
boundaries, 64-bit file and physical offsets, holes without block-zero reads,
LARGE_FILE capability write/cache/barrier ordering and failure retry,
same-block truncation, sparse growth, capacity and sector-count overflow,
partial writes with persisted size/accounting, and complete tree reclamation.
Allocation and table-write failures return every detached block; failed reads,
pointer writes and root detach keep the remaining owned storage valid for retry.
The real software-cache fixture separately verifies that a failed single-page
inode/pointer replacement copies no new bytes, including short fills and failed
dirty eviction. AddressSanitizer and UndefinedBehaviorSanitizer cover the tree
fixture; host heap leak detection is disabled because the V test runtime is not
the kernel's allocator. Explicit block counters still assert complete cleanup.

The guest test uses a 64 MiB disk with logical sparse files up to the complete
EXT2 tree limit: 17,247,252,480 bytes with 1 KiB blocks and 4,402,345,721,856 bytes
with 4 KiB blocks. No corresponding multi-terabyte host image is created.
It touches every pointer depth, crosses 4 GiB, verifies zero holes and small
physical block counts, and tests tail/cache coherence with private COW isolation.
QEMU is killed after each explicit synchronization, restarted to verify the
same disk, then restarted again after truncation. Final truncation must return
the entire baseline free-block count; `e2fsck -fn` checks the actual filesystem
after every power cut. Filesystems begin without LARGE_FILE, so its durable
transition is tested too. A 500-cycle grow/write/truncate loop measures retained
slab objects and runtime; traversal depends on allocated tables, not hole length.

```sh
VINIX_VM_RUNNER_ROOT=/path/to/main/vinix VINIX_QEMU_RT_NO_BUILD=1 \
VINIX_KERNEL_DIR=/path/to/saved-arm-build \
VINIX_AARCH64_SYSROOT=/path/to/aarch64/sysroot \
  python3 tests/ext2-sparse/run.py --arch=aarch64
VINIX_VM_RUNNER_ROOT=/path/to/main/vinix \
VINIX_AMD64_KERNEL=/path/to/saved-amd-build/bin/vinix \
  python3 tests/ext2-sparse/run.py --arch=amd64
```

Both saved binaries must match the tested source. The build directory for ARM
needs `bin/vinix`; AMD boots the supplied kernel using the disk-root path.
Use `--blocks=4096` or `--blocks=1024` to select one format.

These changes do not provide journaling or close FS2's general crash-consistency
and permanent I/O-error retry gaps. In particular, a failure while freeing a
detached block or persisting allocation counters can still require filesystem
repair, and the baseline orphan-inode release path still lacks a retry owner.
Clearing common cached bytes on truncation/growth does not invalidate all live
PTEs or provide SIGBUS for complete mapped pages past the new EOF; that remains
a separate VM semantic gap. Supported writable EXT2 block sizes are explicitly
1, 2 and 4 KiB; inode strides must be powers of two from 128 bytes through the
block size. Those alignments guarantee a one-page inode/pointer cache write.
