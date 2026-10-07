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

The native guest is maintained in `sparsefixture/core.v`. Its declaration-only
header uses the real libc filesystem layouts and constrains native descriptor,
offset and formatting widths. A one-byte volatile view preserves the mapped
tail stores and reads; optimized ARM code retains both stores and both loads.
The fixed buffers stay on the stack, and the three-byte pattern and 16-byte
crossing pattern remain readonly permanent data. Optimized ARM/x86 objects
import no allocators.

The independent reference is the 185-line `tests/ext2-sparse/guest.c` at
`bb26e71deb05913c617fdf3c47483041064f3fd7`, blob
`07e6dc32d39cb1890036af93257d5e144a89e945`. The port preserves all 54 physical
check sites (53 on ARM), their original diagnostic line numbers, the 16-class
heap bank, 32 warmups, 500 measured cycles, six-second settling intervals and
original memory/runtime limits. `VINIX_V_COMPILER` selects the compiler.
`--state-dir` retains a fresh disk and inputs; `--prebuilt-init` runs a frozen
independent control without replacing the maintained V source.

Strict ARM LLVM and genuine x86 musl GCC C/V builds passed. Each of the four
native controls passed all six phases with both block sizes and the original
300-second allowance per boot; the maintained ARM runner passed separately.
All 30 power-cut phases passed their original disk and `e2fsck` checks. Measured
retention was 1,248 bytes for ARM C, 1,040 bytes for the strict ARM V control
and 64 bytes for both x86 controls. The maintained ARM control retained 1,248
and 1,040 bytes across its two block sizes. All results meet the unchanged
fixture limits; the measured loops also met the original 60-second bound.
ABI/lifetime peer review and exact inputs/logs are recorded under
`~/.cache/vinix-c-to-v/firstparty-only-20261006-011023/ext2-sparse-fixture/`.
These fixture runs reuse recorded allocation-instrumented kernels and do not
claim a new production-kernel build or host syscall sanitizer run. A cached
section-extraction rewrite was caught by the executable hash guard before
x86 V execution; the exact SDK binaries were reproduced from the recorded
commands. The maintained runner's compiler profile has different executable
instructions and was tested separately.

These changes do not provide journaling or close FS2's general crash-consistency
and permanent I/O-error retry gaps. In particular, a failure while freeing a
detached block or persisting allocation counters can still require filesystem
repair, and the baseline orphan-inode release path still lacks a retry owner.
Clearing common cached bytes on truncation/growth does not invalidate all live
PTEs or provide SIGBUS for complete mapped pages past the new EOF; that remains
a separate VM semantic gap. Supported writable EXT2 block sizes are explicitly
1, 2 and 4 KiB; inode strides must be powers of two from 128 bytes through the
block size. Those alignments guarantee a one-page inode/pointer cache write.
