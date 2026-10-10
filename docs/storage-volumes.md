# Logical block volumes and storage counters

Vinix can expose up to 64 linear views of physical AHCI, NVMe and ARM VirtIO
block devices (including their partitions). A view maps a sector-aligned byte
range to `/dev/mapper/vinix0` through `/dev/mapper/vinix63`. Creating, growing or
removing a view changes kernel mappings only; it does not format the device or
move its contents. Kernel mappings last until reboot. Saved volume plans retain
their geometry and disk identity for explicit restore after boot.

The native V utility is installed as `/usr/sbin/vinix-volume` by both userland
and desktop image builders. Commands require a trusted MAC domain,
`CAP_SYS_ADMIN`, and the initial user namespace for management; status requires
ordinary read access to the device.

```sh
# Example only: choose an unused physical extent before creating a writable view.
vinix-volume status /dev/vda
vinix-volume create /dev/vda 0 1048576 8388608
vinix-volume status /dev/mapper/vinix0
vinix-volume grow /dev/mapper/vinix0 16777216
vinix-volume remove /dev/mapper/vinix0
# A read-only view:
vinix-volume create /dev/vda 1 33554432 8388608 ro
```

Lengths and offsets are decimal bytes. Creation requires an aligned nonempty
range contained in the parent device, a free slot, and no overlap with another
managed view. Writable creation opens the parent read/write; a read-only view
can use a readable parent. Nested logical views and shrinking are unsupported.
Growing retains the start offset and can happen with raw descriptors open.
This is block capacity growth, not online filesystem resizing. The existing
filesystem registration does not dynamically discover or mount filesystems in
new views; this increment provides the block management layer.

Reconfiguration reserves the physical extent before changing geometry. It
rejects mounted/protected extents, swap, pending mounts, and active raw writes;
new overlapping writes/mounts/swap cannot enter during the change. Writable
operations and mount/swap admission recheck geometry after reserving it. This
closes the gap between sampling an old length and entering after a grow.
Protection follows the actual parent disk identity, including aliases and
whole-disk overlaps, rather than user-supplied device numbers. Filesystem
protection deliberately survives unmount while detached caches can still write.

Managed nodes and the mapper directory cannot be renamed, unlinked, hardlinked,
or used as mount targets/bind sources. Volume-backed mknod aliases can be
removed normally, but cannot acquire permanent mount pins. Path collisions
fail without replacing the existing node. Removing a volume detaches its node
and marks existing descriptors offline; subsequent I/O fails with `ENODEV`.
A reused slot gets a new generation, and old descriptors cannot remove its
replacement. Object, interface, parent and node ownership drain through the
normal VFS grace period. Metadata is charged to the creating process, including
retired objects, and dynamic policy rows are recycled with a fixed bound.

## Saved volume plans

```sh
# Use a whole physical disk with a nonzero MBR signature or GPT disk GUID.
# Store the plan on a persistent filesystem available before restoration.
vinix-volume save /dev/vda /root/volumes.vmap
vinix-volume restore /dev/vda /root/volumes.vmap
```

`save` records every managed mapping on the selected physical disk, including
views created through its partitions. The plan stores absolute physical byte
offsets, lengths, slots and read-only flags. It verifies the disk size, logical
sector size and either a nonzero MBR disk signature or the GUID from a
CRC-checked primary GPT header. A protective MBR cannot substitute for an
unreadable GPT header. Supported sector sizes are powers of two from 512 through
4096 bytes. Saving never stamps or changes partition-table identity.

`restore` requires an explicit whole physical device path and verifies its
identity and geometry before creating mappings. Runtime disk numbers and paths
are absent from the saved format. All records are checked for corruption,
bounds, alignment, duplicate slots and overlapping extents. Every occupied
requested slot must already match the selected disk, offset, length and
read-only mode; a conflict fails before creating any missing mapping. Matching
views retain their generation and open descriptors, making repeated restore
idempotent. Creates retain the kernel's ordinary management privileges, extent
protection and resource limits.

Plans use a bounded little-endian format: a 64-byte `VINIXVM1` version-1 header
with geometry, identity, record count, CRC32 and zero reserved bytes, followed
by up to 64 32-byte version-1 create records. CRC32 detects accidental
corruption; it does not authenticate a plan. MBR signatures and GPT GUIDs also
cannot distinguish cloned disks with duplicated identity. Choose the physical
device explicitly and retain backups of both the plan and its data.

Publication creates an exclusive mode-0600 temporary file in the destination
directory, writes and fsyncs it, renames it over the previous plan and fsyncs
the directory. Directory operations share one opened directory descriptor.
Failure before rename preserves the previous plan. A directory flush failure
after rename reports that publication occurred without confirmed durability.
Loading requires a bounded regular file and rejects a final symlink. These
flushes use the filesystem and device's existing guarantees; ext2 has no journal.

Save and restore are intended for serialized administration. Their status scans
do not lock out other management processes. Kernel creation rechecks each new
extent, but a later quota, I/O or concurrent-change failure can leave a created
prefix. Restore reports the error and keeps those mappings; applying the plan
again resumes from matching entries. It never removes unlisted mappings.
Automatic disk discovery, boot-service integration and filesystem mounting are
still separate work. A plan stored inside a managed view must be made available
before that view can be restored.

## Status ABI

`tools/volumes/volumecli/volume.h` defines the native little-endian ABI shared by
both supported 64-bit architectures. Private ioctls are:

| Request | Value | Argument |
| --- | --- | --- |
| Create on a parent FD | `0x56560001` | 32-byte request, version 1, slot, offset, length, flags |
| Grow on a volume FD | `0x56560002` | Request with version 1 and new length; other fields zero |
| Remove on a volume FD | `0x56560003` | No payload |
| Query block status | `0x56560004` | 128-byte output, version 1 |

Create flags accept only bit 0 (read-only). Status has 16 `uint64_t` words:
version, bytes, logical sector size, flags, reads, writes, read bytes, write
bytes, flushes, errors, last errno, physical disk identity, physical start, slot,
generation, and reserved zero. Non-volume slot is `UINT64_MAX`. Status flags are
read-only (1), offline (2), flush supported (4), logical view (8), and counters
shared with a parent (16).

Counters describe completed backend operations/bytes and successful flushes.
Backend I/O failures increment errors and save the latest errno, including
invalid requests rejected inside a physical driver. Volume validation,
permissions and bad userspace pointers rejected before dispatch leave the
volume counters unchanged. These are request failure counters, not a hardware
diagnostic classification. A partition reports parent counters with flag 16;
a logical view tracks its own forwarded operations and inherits parent
offline/flush/discard capability. Large syscalls can comprise several backend
operations. Health here means I/O error
and availability reporting; SMART wear, temperature, predictive failure and
real-hardware qualification remain future work. Unsupported backends return
`ENOTTY`. Geometry also supports `BLKGETSIZE64`, `BLKGETSIZE`, `BLKSSZGET`, and
`BLKROGET` without allowing destructive ioctl passthrough.

## TRIM/discard

`vinix-volume discard DEVICE OFFSET_BYTES LENGTH_BYTES` submits Linux
`BLKDISCARD` (`0x1277`), whose argument is two `uint64_t` byte values: offset
and length. Status flag 32 advertises backend discard support. Length must be
nonzero; both values must align to the logical sector size, and the full range
must fit inside the opened device. No rounding expands the requested range.

Discard requires a writable descriptor, a trusted MAC domain, `CAP_SYS_ADMIN`
and the initial user namespace. It rejects read-only/offline devices and
unsupported backends. Aliases retain the backing device's capability and
physical identity. Partitions and managed volumes translate only their own
bounds. Mounted/protected filesystems, pending mounts, swap, concurrent raw
writes and geometry changes exclude discard at every securelevel. Securelevel
two also prohibits discard through descriptors opened earlier.

The ioctl reserves the opened device's whole physical extent across batches of
whole logical sectors, up to 64 KiB or one larger sector. Locks are released
between batches; scheduling, signals, exec
cancellation and raised securelevels are checked there. A failure or
interruption may leave an already completed prefix discarded. Errors propagate
to the caller and backend error counters; successful discard does not inflate
read/write byte counters. Discard is a deallocation hint, not secure erasure,
and makes no promise about the contents returned by later reads. It does not
flush data or trigger filesystem free-space trimming; use it only for ranges
whose data can be discarded.

AHCI uses non-queued ATA DSM/TRIM only when IDENTIFY advertises it. NVMe uses
Dataset Management with Deallocate when ONCS bit 2 advertises it. VirtIO
negotiates DISCARD and honors the reported maximum sectors and segment count.
All commands use exact ranges; protocol limits split requests rather than
truncate them. AHCI/VirtIO reuse their permanent DMA buffers. NVMe uses one
fallible range page and frees it after completion or proven controller disable,
retaining it when a failed reset leaves DMA ownership uncertain. NVMe remains
disabled by the existing production-kernel initialization policy.

Protocol references: [VirtIO 1.2 block requests](https://docs.oasis-open.org/virtio/virtio/v1.2/virtio-v1.2.html),
[NVMe NVM command set](https://nvmexpress.org/wp-content/uploads/NVM-Express-NVM-Command-Set-Specification-1.0e-2024.07.29-Ratified.pdf),
and Linux's [ATA capability definitions](https://github.com/torvalds/linux/blob/master/include/linux/ata.h)
and [DSM command construction](https://github.com/torvalds/linux/blob/master/drivers/ata/libata-scsi.c).

## Qualification and remaining roadmap work

`tests/storage-volumes` checks the production code on the host and ordinary
kernels on disposable ARM VirtIO and AMD64 AHCI disks. It covers bounds,
read-only policy, aliases, stale FDs/generation reuse, namespace collisions,
mount restrictions, invalid userspace pointers, CLI execution, concurrent
open/remove, discard through aliases/partitions, physical guard sectors,
active-swap exclusion and retained heap after distinct-extent management
cycles. `tests/block-storage` injects
controller completion/flush errors; `tests/mounted-disk-policy` checks
mount/write/swap interleavings.

The native V saved-plan controller also runs host ASan/UBSan checks and two
ordinary-kernel boots on each architecture. Plans stay on a disposable ext2
system disk across an abrupt QEMU stop; the second boot restores mappings and
checks persisted data and read-only policy without a host-supplied plan. The
first boot rejects corrupt files, a different disk and conflicting slots,
checks repeated and partial restore, and measures retained heap across 200
save/restore cycles after warming the same paths.

NVMe discard is qualified with the production command/completion code and
mocked MMIO on the host, including 200 successful operations and failed-reset
DMA ownership. An attempted NVMe development guest panicked during device
initialization before reaching userspace. Native NVMe boot qualification and
its production initialization policy remain open; host results do not establish
real-controller or guest readiness.

The encompassing roadmap item stays open: automatic persistent volume discovery,
storage pools/RAID, full-disk encryption and recovery, online filesystem resize,
filesystem-aware trimming and controller-specific health data are not
implemented by this increment. The anonymous pager's encrypted swap remains a
separate feature.
