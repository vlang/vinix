# Mission 2: ext4 read-only mounts

The ext4 reader shares `kernel/fs/ext2`'s block cache and inode/block I/O.
`init()` registers `probe_volume`; `mount -t ext4` selects its ext4 mode.
The existing `sysdisk` import brings this module into x86 builds and
`aarch64/virtio_blk` imports it for ARM. No second probe or driver is installed.

Supported: clean Linux-created ext filesystems with 1, 2 or 4 KiB blocks,
128-byte or larger power-of-two inodes up to the block size, 32-byte group
descriptors or exactly 64-byte descriptors with `64bit`, `flex_bg`, ordinary
`metadata_csum` and `metadata_csum_seed`, legacy indirect blocks, and extent
trees through depth 5. Holes and unwritten extents return zeroes. Indexed
directories are scanned linearly through their leaf blocks; the HTree index
payload is skipped as unused directory-record space. Regular files,
directories, short inline symlinks and block/extent-backed symlinks up to
4095 bytes are populated eagerly before the mount is published.

**Metadata checksums are accepted but not verified**, including superblock,
group, inode, directory and extent-block checksums. This is a minimal reader
for trusted clean images, not an integrity verifier. Format definitions follow
the Linux kernel's [superblock](https://www.kernel.org/doc/html/latest/filesystems/ext4/super.html),
[inode](https://www.kernel.org/doc/html/latest/filesystems/ext4/inodes.html),
and [extent tree](https://www.kernel.org/doc/html/latest/filesystems/ext4/ifork.html)
documentation.

The reader rejects recovery-required or non-clean state, pending old-style
orphans or `orphan_present`, unknown incompatible features, `meta_bg`, MMP,
`bigalloc`, inline data, encryption, verity, EA inodes, casefolding and
non-Linux inode layouts. Volumes/high physical addresses beyond the existing
u32 block interface are rejected. High UID/GID, high sector counts, huge-file
units, high xattr addresses, extended timestamp epochs, special inode types
(devices, FIFOs, sockets), deleted/zero-link inodes, and oversized files are
also refused rather than truncated or interpreted as ordinary file data.
Timestamp reporting currently uses whole seconds; inline inode xattrs/ACLs
are not exposed by the inherited ext2 xattr reader.

Every real VFS node has `read_only = true`; resources implement
`ReadOnlyResource`. Mutation callbacks fail with `EROFS`, and the raw write
path refuses writes before changing the cache. No JBD2 journal is opened or
replayed for ext4. A requested writable mount remains read-only, including
aliases/remounts and shared-writable mapping admission through VFS.

Mount construction uses a queue bounded to 65,536 real nodes and an aggregate
64 MiB directory-data budget. One block and reusable inode slots occupy the
stack; directory nesting does not grow it. Repeated directory inode numbers
(including cycles/hard-linked directories), duplicate names, out-of-block
records, invalid names and inconsistent entry types reject the mount. Extent
headers/counts/depth, ordering, ancestor key ranges and physical ranges are
checked on each traversed path. Unvisited extent subtrees are not scrubbed.
Device/volume byte bounds use subtraction before reads; the superblock bounds
all block/group/inode multiplications before use.

Each private node owns its name, symlink target and one Resource/interface
box. On failure the node queue is destroyed in reverse order and its maps,
strings and resources are freed; the mount instance/interface box is freed
after its lock is released. The registered template retains the shared cache,
superblock, root-inode scratch and lock, preserving the existing block-device
reservation contract even after a failed mount. Successful mounts follow the
existing VFS mount-tree lifetime. The new Resource allocation is marked
`@[freed]` at its owner; no allocation allowance was added. The normal
two-architecture allocation gate must pass the parent review.

## Local tests

Locate the compiler with the repository helper (set `V` if it is not on PATH):

```sh
. build-support/find-v.sh
"$V" run tests/ext-mount/run-host.v --synthetic
VINIX_HOST_SANITIZE=1 ASAN_OPTIONS=detect_leaks=0 \
  "$V" run tests/ext-mount/run-host.v --synthetic
"$V" run tests/ext-mount/run-host.v
```

The synthetic mode needs no e2fsprogs. It executes production geometry,
inode-layout, directory-record, inode I/O and extent functions plus the
existing ext2 sparse tests. It also compiles the production `read_tree.v`
against VFS/device doubles (only the time-module import is redirected), checks
a 1,024-directory chain, cycles, duplicate names, bad symlinks, and injected
read failures with zero surviving private resources. Device I/O and VFS
publication are doubles; this does not replace a boot test. The full mode
also creates actual mke2fs ext2/ext4 images at 1 and 4 KiB with fragmented
extents, sparse ranges, both symlink forms and multiple descriptor groups.
`MKE2FS=/absolute/path/mke2fs` overrides the image generator.

## Parent integration gate

With existing kernel dependencies and the project's kernel-capable compiler:

```sh
. build-support/find-v.sh
make -C kernel ARCH=aarch64 V="$V" \
  CC=/opt/homebrew/opt/llvm/bin/clang \
  AR=/opt/homebrew/opt/llvm/bin/llvm-ar \
  LD_AARCH64=/opt/homebrew/opt/lld/bin/ld.lld
tests/kernel-allocs/run.sh
```

Use equivalent Linux tool paths when appropriate. Build the x86 kernel in
this worktree after saving the ARM kernel separately; do not reuse objects
between architectures. Review every new lifetime and generated C before
accepting the allocation gate.

The existing V guest fixture and QEMU controller perform real mounts, reads,
private mmap, write/create denial, remount protection and ext4 image hash
comparison. With e2fsprogs, the guest cross toolchain and boot assets installed:

```sh
sh build-support/run-v-tool.sh tests/native-disk-tools/external-main.v \
  --arch aarch64 --kernel-dir "$PWD/kernel" --state-dir /tmp/ext4-arm-gate
sh build-support/run-v-tool.sh tests/native-disk-tools/external-main.v \
  --arch amd64 --kernel-dir "$PWD/kernel" --state-dir /tmp/ext4-x86-gate
```

Run each command against its matching prebuilt kernel, with fresh state
directories. The ARM controller attaches whole ext volumes with VirtIO;
x86 uses MBR/GPT partitions on AHCI. Require `EXT MOUNT PASS`, a byte-identical
ext4 disk after shutdown, and no panic/I/O failures. This controller is the
exact QEMU entrypoint; it constructs firmware/initramfs/device arguments.

For an additional disposable image, run from the repository root:

```sh
mkfs.ext4 -q -F -b 4096 -O extent,64bit,flex_bg,metadata_csum \
  /tmp/ext4-read.img 65536
debugfs -w -R 'write docs/ext4-read.md /marker' /tmp/ext4-read.img
debugfs -w -R 'symlink /short-link marker' /tmp/ext4-read.img
debugfs -w -R 'symlink /long-link this/is/a/long/symlink/target/with/more/than/sixty/bytes/to/exercise/extents' /tmp/ext4-read.img
debugfs -w -R 'write /dev/null /unwritten' /tmp/ext4-read.img
debugfs -w -R 'fallocate /unwritten 0 7' /tmp/ext4-read.img
debugfs -w -R 'set_inode_field /unwritten size 32768' /tmp/ext4-read.img
debugfs -R 'stats' /tmp/ext4-read.img
debugfs -R 'stat /unwritten' /tmp/ext4-read.img
e2fsck -fn /tmp/ext4-read.img
```

Attach it to a bootable ARM guest as an extra drive:
`-drive if=none,format=raw,file=/tmp/ext4-read.img,id=ext4test
-device virtio-blk-device,drive=ext4test`.
Use its actual `/dev/vd*` name; for example, if it appears as `/dev/vdb`:

```sh
mkdir -p /mnt/ext4
mount -t ext4 -o ro /dev/vdb /mnt/ext4
cat /mnt/ext4/marker
readlink /mnt/ext4/short-link
readlink /mnt/ext4/long-link
od -An -tx1 /mnt/ext4/unwritten
touch /mnt/ext4/denied
umount /mnt/ext4
```

Compare marker bytes with this document; require all unwritten bytes to be
zero and `touch` to fail with `EROFS`. Compare the image hash before/after.
Repeat full host tests for 32-byte descriptors (`-O ^64bit`) and use disposable
copies with `debugfs -w -R 'set_super_value feature_incompat 0x2c6' ...` to
require rejection of `needs_recovery` (0x4). Test each other unsupported feature
separately. Never run recovery or mutation tests against a real data disk.
