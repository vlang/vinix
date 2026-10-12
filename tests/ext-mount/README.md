# External ext2 and ext4 mounts

The VFS probes the selected block device on its first mount; the volume no
longer has to be selected as a boot disk. Repeated mounts reuse that device's
cache. The source extent is reserved before probing or native journal replay.
Once a probe retains its cache, the extent stays protected even if a damaged
root prevents the mount from completing.

```
mount -t ext2 /dev/sd0-2 /mnt
mount -t ext4 -o ro /dev/sd0-2 /mnt
```

Ext4 currently mounts read-only, including when the caller requests read-write.
The reader supports extents, 64-byte group descriptors, flex_bg, and ordinary
metadata_csum images. Volumes must be clean: JBD2 replay and orphan recovery
remain Linux's responsibility. Unknown incompatible features, inline data,
encryption, casefold, meta_bg, bigalloc and volumes above 2^32 blocks are
rejected. Metadata checksums are not yet verified. Simultaneous mounts of one
device under different type names are rejected to avoid creating competing caches.

The layouts follow the Linux kernel's [superblock](https://www.kernel.org/doc/html/latest/filesystems/ext4/super.html),
[group descriptor](https://www.kernel.org/doc/html/latest/filesystems/ext4/group_descr.html)
and [extent tree](https://www.kernel.org/doc/html/latest/filesystems/ext4/ifork.html)
documentation. Existing native ext2 journal volumes retain their own format.

Host tests include the existing sparse ext2 suite, malformed extent trees,
feature/geometry rejection, and Linux-created ext2/ext4 images with 1 KiB and
4 KiB blocks, external extent-tree nodes, holes, symlinks and descriptor groups
beyond group zero. Requires V and e2fsprogs (`MKE2FS` overrides its path).

```
v run tests/ext-mount/run-host.v
VINIX_HOST_SANITIZE=1 ASAN_OPTIONS=detect_leaks=0 v run tests/ext-mount/run-host.v
```

GPT partition lengths include the final LBA, so a filesystem that fills its
partition passes the same geometry check as a whole-device filesystem.

The guest fixture mounts an MBR ext2 partition and a GPT ext4 partition through
AHCI on x86, and whole volumes through VirtIO on ARM. It checks ext2 writes and
repeat mounts; ext4 reads, private mmap, write denial and remount protection.
It also checks that a failed root mount cannot expose its retained cache to
raw writes through an earlier descriptor at securelevel 1.
After QEMU exits, e2fsck and debugfs
verify the ext2 write independently, and the ext4 disk must be byte-for-byte
unchanged. Build a kernel from isolated sources first, then run:

```
sh build-support/run-v-tool.sh tests/native-disk-tools/external-main.v \
  --arch amd64 --kernel-dir /path/to/x86/kernel --state-dir /tmp/ext-mount-x86
sh build-support/run-v-tool.sh tests/native-disk-tools/external-main.v \
  --arch aarch64 --kernel-dir /path/to/arm/kernel --state-dir /tmp/ext-mount-arm
```

Use fresh state directories. All disk images are disposable; the runner uses
the supplied prebuilt kernel and leaves the working checkout's build untouched.
