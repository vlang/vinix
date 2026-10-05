# Shared EXT2 mapping writeback

`V=/path/to/v tests/mapped-writeback/run-host.sh` executes the production
mapping and intrusive registry code with a faulting inode/allocator fixture.
It checks failed/short final unmap, unlinked resource retention and retry,
continuation past a failing resource, bounded batches, new registrations,
and 1000 map/unmap lifetimes. `tests/pagecache/run.sh` separately exercises
the actual backing cache and global hooks, barriers and failure propagation.

Build the kernel, then run `python3 tests/mapped-writeback/run.py --arch
aarch64` or `--arch amd64`. The runner kills QEMU immediately after each
completion marker, with both descriptor and mapping still live. `debugfs`
then verifies every byte in the actual disk image. Global sync, syncfs and
two successive background passes are checked without msync, unmap, close or
orderly shutdown. The churn case measures `/proc/slabinfo` before and after
500 shared map/unlink/close/unmap operations, concurrent global sync and the
VFS grace period. A seeded 1200-entry directory exercises inode-scratch stack
reuse while mounting the volume. AMD64 boots from its seeded AHCI disk root;
AArch64 mounts its VirtIO volume at `/root`.

For worktrees, set `VINIX_VM_RUNNER_ROOT` to the original repository and
`VINIX_KERNEL_DIR` to this worktree's kernel directory for AArch64, or
`VINIX_AMD64_KERNEL` to its built kernel for AMD64. Set
`VINIX_AARCH64_SYSROOT` to the existing musl sysroot and
`VINIX_QEMU_RT_NO_BUILD=1` to reuse the ARM build. `--steps=sync,churn` selects
a subset. Images and firmware state are private temporary files.
The `private` step additionally checks clean EXT2 page sharing and copy-on-write;
see [its ownership and test coverage](../private-pages/README.md).

Shared pages are conservatively copied on every sync/background pass; common
VM hardware dirty-bit tracking and avoidance of unchanged mapped writes
remain open. Closing a descriptor with a live mapping does not guarantee
fsync: the mapping and registry retain the resource until unmap or writeback.
Global flushes now invoke each registered device's optional hardware barrier;
drivers without that capability guarantee Resource write completion only.
Failed mapped-page writeback retains its page and inode for the next pass.
The separate pre-existing final inode-deallocation error path still restores
an unowned reference; retrying failed inode/block reclamation remains open.

The measured path also exposed existing promoted EXT2 inode/block-group
scratch allocations and attribute capability boxes, plus new global barriers
amplifying sync capability boxes. Scratch storage now uses the kernel's caller
stack-slot macro and optional interfaces dispatch through stack values. Cache
I/O copies caller buffers before returning; asynchronous writeback uses its
own cache/run/bounce buffers. The old successful-directory-read double free
was removed. Deferred VFS nodes and names are measured after a deterministic
post-grace unlink triggers reaping; their temporary retention is not a leak.
