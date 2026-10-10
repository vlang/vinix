# Logical block volumes and storage counters

Vinix can expose up to 64 linear views of physical AHCI, NVMe and ARM VirtIO
block devices (including their partitions). A view maps a sector-aligned byte
range to `/dev/mapper/vinix0` through `/dev/mapper/vinix63`. Creating, growing or
removing a view changes kernel mappings only; it does not format the device or
move its contents. Kernel mappings last until reboot. Saved volume plans retain
their geometry and disk identity for explicit or configured restore after boot.

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
read-only mode; a conflict fails before creating any missing mapping. Unlisted
managed views overlapping a requested extent also fail preflight. Matching
views retain their generation and open descriptors, making repeated restore
idempotent. Creates retain the kernel's ordinary management privileges, extent
protection and resource limits.

Plans use a bounded little-endian format: a 64-byte `VINIXVM1` version-1 header
with geometry, identity, record count, CRC32 and zero reserved bytes, followed
by up to 64 32-byte version-1 create records. CRC32 detects accidental
corruption; it does not authenticate a plan. MBR signatures and GPT GUIDs can
be duplicated by cloning. Explicit restore still relies on the selected
device; automatic discovery rejects multiple physical matches. Retain backups
of both the plan and its data.

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
Filesystem mounting remains separate work. A plan stored inside a managed view
must be made available before that view can be restored.

## Discovery and boot restore

```sh
vinix-volume discover /root/volumes.vmap
vinix-volume restore-auto /root/volumes.vmap
# Opt in to restore before the desktop or interactive shell starts:
mkdir -p /etc/vinix
chown root:root /etc/vinix
chmod 755 /etc/vinix
vinix-volume save /dev/vda /etc/vinix/volumes.vmap
vinix-volume boot-restore
```

`discover` validates a plan and scans the top level of `/dev` for its physical
disk, printing the matched path without changing mappings. `restore-auto` uses
the same scan, then applies the ordinary restore checks through the selected
open device descriptor. The disk can acquire a different device name or runtime
number on the next boot. The scan considers block nodes only, skips symlinks,
partitions, logical views and unsupported status backends, and counts at most
4096 directory entries. Invalid table identities cannot match. An unreadable
supported candidate with matching geometry fails the scan because uniqueness
cannot be established. Multiple nodes aliasing one physical disk are accepted;
matching identities on distinct physical disks fail before creating any view.

The packaged ARM desktop init and both architectures' Alpine init scripts, plus
the AMD64 desktop init, run `boot-restore` once before starting applications or
the interactive shell. It loads `/etc/vinix/volumes.vmap` when present, together
with visible `.vmap` files in `/etc/vinix/volumes.d` as one plan set. Missing
configuration or an empty set is a successful no-op. The opened `/etc`,
`/etc/vinix`, enabled plans directory and every enabled file must be owned by
root and not writable by group or others; none of those path components may be
a symlink. Plans must also satisfy the regular-file and checksum rules.
Directory-relative operations pin the configuration and device directories;
all discovered disk descriptors remain open through restore.

A failed boot restore prints its reason and init continues to the desktop or
recovery shell. It does not format, unlock or mount volumes, retry hotplug, or
remove existing mappings. Delete an enabled plan or give it a hidden name or a
different extension to disable its replay. Boot replay does not provide the
root filesystem needed to load its own configuration.

## Multi-disk plan sets

As an alternative to the single default file, enable one plan per disk in a
directory. Do not also leave the same disk's plan enabled as `volumes.vmap`.

```sh
mkdir -p /etc/vinix/volumes.d
chown root:root /etc/vinix /etc/vinix/volumes.d
chmod 755 /etc/vinix /etc/vinix/volumes.d
vinix-volume save /dev/vda /etc/vinix/volumes.d/main.vmap
vinix-volume save /dev/vdb /etc/vinix/volumes.d/data.vmap
vinix-volume restore-set /etc/vinix/volumes.d
vinix-volume boot-restore
```

`restore-set DIRECTORY` reads visible files ending in `.vmap`, without recursion.
Other names, including publication temporaries and backup files, are ignored.
An enabled symlink, directory, device or other nonregular file fails the set.
Explicit restoration uses normal file read permissions; boot replay adds the
ownership and write-permission checks above.

Sets contain at most 64 disk plans and 64 mappings in total. Each directory scan
visits at most 4096 non-dot entries. Files are loaded in bytewise filename order;
the legacy default file comes first during boot. Duplicate disk keys or global
mapper slots fail validation. All plans are decoded before disk discovery, and
all physical disks and existing mapping slots/extents are checked before the
first create. An absent or ambiguous disk, a malformed or untrusted later plan,
or a later mapping conflict cannot leave a restored prefix. Existing matching
views keep their generations and open descriptors. Physical identities are
rechecked through the retained disk descriptors after the final preflight.

These are preflight guarantees for serialized administration, not an atomic
multi-disk transaction. There is no global configuration generation or management
lock. Kernel creation still checks privilege, mounted/swap protection, quota and
current geometry. A failure during creation or concurrent reconfiguration can
leave previously created mappings in place, including an earlier disk's complete
plan. Replay resumes from matching mappings and never removes unlisted views.
Saving several files does not publish a set atomically; finish enrollment before
boot or explicit restore. Pools, spanning volumes and RAID remain separate work.

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
operations. AHCI also provides the SMART query below. NVMe/ANS health logs,
vendor-specific wear and temperature interpretation, predictive monitoring and
real-hardware qualification remain future work. Unsupported status backends return
`ENOTTY`. Geometry also supports `BLKGETSIZE64`, `BLKGETSIZE`, `BLKSSZGET`, and
`BLKROGET` without allowing destructive ioctl passthrough.

## ATA SMART health

```sh
vinix-volume health /dev/sd0
```

Whole AHCI ATA disks expose a read-only SMART query through ioctl `0x56560005`.
It requires a readable descriptor and ordinary MAC read/ioctl access; it does
not require volume-management privileges. Partitions, logical views and other
backends return `ENOTTY`; write-only and `O_PATH` descriptors return `EBADF`.
Mounted disks can be queried. This interface accepts no command passthrough.

Each query refreshes IDENTIFY, validates its command-set support/enabled words,
then reads SMART data and RETURN STATUS when SMART is available and enabled.
It never enables SMART, starts self-tests, changes attributes or reads sectors
from the disk's data area. A disabled/unsupported ATA device returns its identity
with unavailable health bits. Invalid IDENTIFY capability words also leave the
corresponding bit unavailable. Short transfers, bad SMART checksums, missing or
invalid status FIS replies and driver failures return an error without copying
a partial report. The port uses its existing permanent DMA buffer under its
normal lock and timeout/quarantine policy; report copying occurs after unlock.

The output ABI is 1088 bytes: eight little-endian `uint64_t` words (version 1,
protocol 1 for ATA, flags, runtime physical disk ID and four reserved zero words),
then the 512-byte IDENTIFY response and 512-byte SMART READ DATA response. Flags
are support available (1), enabled (2), SMART data valid (4), threshold status
valid (8) and threshold exceeded (16). Unavailable SMART data is zeroed. Headers
and payload offsets are checked when compiling the packaged utility on both
architectures. There is no cached health state or per-query kernel allocation.

The command prints model, serial and firmware with control bytes sanitized,
the drive's threshold status, and up to 30 raw attributes with ID, flags,
current/worst values and six raw bytes rendered as hexadecimal. Raw layouts,
units and attribute IDs are vendor specific; the utility does not label them
as temperatures, wear percentages or sector counts. A not-exceeded threshold
is the drive's current assessment, not a prediction or a durability guarantee.
Exit status is 0 for a valid not-exceeded status, 3 for exceeded, 4 when the
ATA threshold status is unavailable, 1 for an error and 2 for invalid usage.
SMART queries do not change completed data-read/write/flush counters; failed
backend queries increment the existing error counter. Bad output pointers and
descriptor-policy failures do not increment hardware errors.

Protocol layout references are the
[SMART data definitions maintained by smartmontools](https://github.com/smartmontools/smartmontools/blob/main/include/smartmon/ata.h),
[AHCI received-FIS and transfer-count specification](https://www.intel.com/content/dam/www/public/us/en/documents/technical-specifications/serial-ata-ahci-spec-rev1-3-1.pdf)
and [QEMU's ATA SMART implementation](https://github.com/qemu/qemu/blob/master/hw/ide/core.c).
See [native host and guest qualification](../tests/storage-health/README.md).

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
first boot exercises init recovery from an invalid configured plan, rejects
corrupt files, untrusted configuration, a different disk, duplicated identity
and conflicting slots, checks physical aliases and repeated/partial restore,
then qualifies a two-disk set. Duplicate disks/slots, a missing later disk,
untrusted directory entries, later slot conflicts and unlisted overlaps leave
earlier disks untouched. Directory-only and legacy-plus-directory replay are
both checked. The fixture measures retained heap across 200 save/boot-restore
cycles after warming the same paths. Before the second boot the physical devices
are reordered. Production init restores both configured disks before the test
application starts. Host init policy checks cover missing utility, synchronous
reaping, nonzero utility exits, fork failure and failed exec under ASan/UBSan.
Host plan-set checks also exercise 64 plans, all global slots, deterministic
ordering, ignored filenames and enumeration limits.

NVMe discard is qualified with the production command/completion code and
mocked MMIO on the host, including 200 successful operations and failed-reset
DMA ownership. An attempted NVMe development guest panicked during device
initialization before reaching userspace. Native NVMe boot qualification and
its production initialization policy remain open; host results do not establish
real-controller or guest readiness.

The encompassing roadmap item stays open: storage pools/RAID, full-disk
encryption and recovery, online filesystem resize,
filesystem-aware trimming, NVMe/ANS health logs and predictive health monitoring are not
implemented by this increment. The anonymous pager's encrypted swap remains a
separate feature.
