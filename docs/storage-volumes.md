# Logical block volumes and storage counters

Vinix can expose up to 64 linear views of physical AHCI, NVMe and ARM VirtIO
block devices (including their partitions). A view maps a sector-aligned byte
range to `/dev/mapper/vinix0` through `/dev/mapper/vinix63`. Creating, growing or
removing a view changes kernel mappings only; it does not format the device or
move its contents. Kernel mappings last until reboot. Saved volume plans retain
their geometry and disk identity for explicit or configured restore after boot;
multi-disk bundles publish a complete saved configuration in one file.

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
configuration or an empty set is a successful no-op. An optional
`/etc/vinix/volumes.vset` bundle joins the same preflighted set. The opened `/etc`,
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
Saving several individual files does not publish a set atomically; finish
enrollment before boot or explicit restore, or use the bundle below. Allocation
pools use bundle metadata as described below; spanning volumes and RAID remain
separate work.

## Atomic multi-disk bundles

```sh
# Capture all managed views on these explicitly selected physical disks.
vinix-volume save-set /root/volumes.vset /dev/vda /dev/vdb
vinix-volume restore-bundle /root/volumes.vset
# To enable the same bundle before applications start:
vinix-volume save-set /etc/vinix/volumes.vset /dev/vda /dev/vdb
vinix-volume boot-restore
```

`save-set BUNDLE DEVICE [DEVICE ...]` accepts 1–64 whole physical disks. Each
disk needs the same identity and geometry as a single-disk plan. It saves all
managed mappings on those disks, preserving offsets, slots and read-only mode;
a disk with no managed mappings is also valid. Duplicate disk identities,
physical aliases and duplicate global slots fail before publication. All disk
descriptors remain open until every identity has been rechecked. An unreadable
later disk or invalid snapshot preserves the previous bundle.

The complete bundle uses one exclusive mode-0600 temporary file, file fsync,
atomic rename and directory fsync, anchored to the same directory descriptor as
single-plan publication. Readers opening the destination see the previous or
the new complete file. Write, file-flush, close or rename failures preserve the
old destination and remove the temporary. A directory-flush failure after rename
reports failure with the new file already published and durability unconfirmed.
These guarantees depend on the backing filesystem's existing flush/recovery
guarantees; a checksum does not make an unjournaled filesystem crash-safe.

The bounded `VINIXVS1` version-1 format has a 64-byte header containing version,
disk count, total byte count, total mapping count, CRC32 and zero reserved bytes,
followed by complete `VINIXVM1` disk plans in command-line order. Both inner and
outer checksums are validated, together with global identity/slot uniqueness.
At most 64 mappings are stored across all disks, so the largest version-1 bundle
is 6208 bytes. Bundles with allocation pools use version 2 as described below.
CRC32 detects accidental corruption; it does not authenticate a bundle.

`restore-bundle` reads a bounded regular file without following its final
symlink, discovers all physical disks, then uses the existing plan-set preflight
and idempotent restore. A malformed later plan, missing disk or mapping conflict
fails before any create. Matching views retain their generations and descriptors;
unlisted views are never removed. Boot replay loads the legacy `volumes.vmap`,
then `volumes.vset`, then visible `volumes.d/*.vmap` files into one set and applies
the ordinary root-ownership/write-permission rules to each enabled input. Remove
duplicate individual enrollment before enabling a bundle: overlaps are rejected
rather than giving one configuration precedence.

Atomic publication applies to the saved configuration. Saving still requires
serialized administration: the kernel has no global mapping snapshot or
configuration generation. Restoring remains a sequence of independently checked
creates; a quota, I/O or concurrent-reconfiguration failure during application
can leave an already created prefix. Replaying the same bundle resumes from
matching entries. Filesystem mounting, spanning volumes and RAID remain separate
work.

## Planned capacity growth

```sh
# Slot 2 already exists and has unused physical space immediately after it.
vinix-volume save-set /root/capacity.vset /dev/vda /dev/vdb
vinix-volume plan-grow /root/capacity.vset 2 16777216
vinix-volume restore-bundle /root/capacity.vset grow
# Enroll the resulting live geometry for ordinary boot replay.
vinix-volume save-set /etc/vinix/volumes.vset /dev/vda /dev/vdb
```

`plan-grow BUNDLE SLOT LENGTH_BYTES` edits one existing mapping's desired length
and atomically publishes the complete bundle. It reads the saved configuration
without opening a physical device or changing a live mapping. The disk identity,
start offset, slot and read-only mode stay fixed. The new length must be at least
the saved length, sector-aligned, inside the saved disk geometry and disjoint
from every other mapping on that disk. A missing slot, shrink, overflow,
misalignment or overlap preserves the previous file; repeating the same desired
length is valid. The existing checksummed format and publication guarantees apply.

`restore-bundle BUNDLE grow` explicitly permits existing smaller views to grow
in place when their physical identity, start, sector size, slot and read-only
mode match. It discovers every disk and checks all requested slots and extents,
including unlisted views in the extension, before the first grow or create.
Ordinary restoration and boot replay continue to require exact lengths for
existing views. Missing views are created at the saved desired length in either
mode. Boot replay can therefore recreate the grown geometry after reboot.

Before each grow, the utility opens that mapping and checks the generation and
old length captured by preflight. It uses that same descriptor for the grow
ioctl and verifies the resulting length and generation afterward. A replaced
slot or changed geometry fails without resizing the replacement. Successful
growth retains the volume's generation and open descriptors, and read-only
volumes keep their read-only mode. Replaying an already applied growth is a
no-op for those views. This extends raw block capacity within existing physical
disk geometry; filesystem resizing remains separate work.

Administration must remain serialized. The kernel rechecks privilege,
mounted/swap protection, parent bounds, overlaps and policy-resource limits when
each change is applied. A later failure can leave completed grows and creates
in place; replay resumes from matching entries. The saved desired lengths remain
published even if runtime application fails. An explicit growth replay is needed
to resume a live view that is still smaller than its saved plan.

## Bundle inspection and preflight

```sh
vinix-volume show-bundle /root/capacity.vset
vinix-volume check-bundle /root/capacity.vset
# Preview a plan that explicitly allows existing smaller views to grow:
vinix-volume check-bundle /root/capacity.vset grow
vinix-volume restore-bundle /root/capacity.vset grow
```

`show-bundle BUNDLE` validates the complete checksummed configuration and prints
each disk's size, sector size and MBR signature or canonical GPT GUID, followed
by its mapping slots, offsets, desired lengths and read-only modes. Disk numbers
in this report are indices in the bundle's saved order. Inspection works offline
and opens only the saved file. It accepts the same bounded regular-file format
and rejects final symlinks and corruption without changing the file.

`check-bundle BUNDLE [grow]` discovers the saved physical disks and runs the same
complete-set preflight as restoration, opening devices read-only. It checks disk
identity/geometry, requested slots and existing extents, including unlisted views
in a planned extension. Every retained disk identity is rechecked after the last
disk's preflight. A malformed file, missing or ambiguous disk, wrong existing
mapping or extent conflict returns failure. Action rows are printed only after
the entire set passes.

Each row reports `action=create`, `action=keep` or `action=grow`, the slot and
offset, current and desired lengths, read-only mode and captured generation.
Missing views report zero current length and generation. A final line counts
each action. Growth requires the explicit `grow` token, with the same matching
rules as explicit growth replay; the default check requires existing lengths
to match exactly. Checking creates or grows no mappings and preserves the bundle.
Both report commands return failure if printing or flushing their output fails.

A successful check describes current discovery and geometry. It does not reserve
extents or test mutation-time management privileges, mounted/swap protection or
resource limits. Administration must remain serialized, and applying the plan
still performs the kernel's ordinary checks and generation/length revalidation.
Read access suffices for a check even when the bundle describes writable views.

See [inspection and preflight qualification](../tests/storage-volumes/check-bundle.md).

## Offline mapping configuration

```sh
# Save identities first; disks with no managed views are valid participants.
vinix-volume save-set /root/layout.vset /dev/sd0 /dev/sd1
vinix-volume show-bundle /root/layout.vset
# Add slot 12 on saved disk index 1, at an absolute physical byte offset:
vinix-volume plan-add /root/layout.vset 1 12 4194304 1048576 ro
vinix-volume check-bundle /root/layout.vset
vinix-volume restore-bundle /root/layout.vset
# Stop replaying slot 12 without changing a live mapping:
vinix-volume plan-remove /root/layout.vset 12
```

`plan-add BUNDLE DISK_INDEX SLOT OFFSET_BYTES LENGTH_BYTES [ro]` adds one desired
mapping to an enrolled disk without opening a device or changing a live view.
The disk index is its zero-based saved order, as printed by `show-bundle`;
it is independent of runtime device names. The offset is absolute within the
saved physical disk. Length must be nonzero. Offset and length must align to
the saved sector size, fit its saved capacity without overflow and avoid all
other planned extents on that disk. Slots 0 through 63 are globally unique
across the bundle. An already planned slot is an error even if its geometry
matches. The optional literal `ro` sets read-only mode; omission allows writes.

`plan-remove BUNDLE SLOT` removes an existing desired entry, preserving the
remaining order, disk identities, geometry and modes. A missing slot is an
error. A disk remains enrolled after removing its last entry, and subsequent
checking/replay still requires that disk's identity. A removed slot can be
assigned to a different enrolled disk in the saved configuration.

Both commands decode and validate the complete bounded checksummed bundle
before editing. They publish the entire new set through the shared atomic
publisher with mode 0600, retaining the existing file on validation or
pre-publication I/O failure. As with capacity planning, directory-flush failure
after rename returns an error with the new file visible and its durability
unconfirmed. Reporting failure also returns an error after publication; inspect
the file before retrying. Final symlinks and corrupt/nonregular files are
rejected. Administration remains serialized to avoid concurrent edit overwrite.

Removing a desired entry does not remove a live view, invalidate its open
descriptors, erase data or release its physical extent. Replay preserves
unlisted views. Use the separate live `remove` command when removal is intended;
the kernel applies its ordinary mounted/swap/lifetime protections. Reassigning
an omitted slot or extent can therefore fail live preflight until the old view
is explicitly removed. Use `check-bundle` before application: offline validation
checks saved extents, while live preflight also detects unlisted mappings.

This completes add/remove editing of saved linear mappings; RAID,
filesystem resize and encryption remain separate work. See
[offline edit qualification](../tests/storage-volumes/edit-bundle.md).

## Offline disk membership

```sh
# Capture another whole disk, then append its saved plan to the existing bundle.
# This example assumes disk 2 has no managed views and the bundle has two disks.
vinix-volume save /dev/sd2 /root/disk2.vmap
vinix-volume plan-enroll /root/layout.vset /root/disk2.vmap
vinix-volume show-bundle /root/layout.vset
vinix-volume check-bundle /root/layout.vset
vinix-volume restore-bundle /root/layout.vset
# An empty participant can stop taking part in subsequent replay:
vinix-volume plan-forget /root/layout.vset 2
```

`plan-enroll BUNDLE PLAN` imports one complete checksummed single-disk `.vmap`
plan into an existing bundle. It appends the disk's saved identity, geometry
and all desired rows in their existing order. Empty disk plans are valid.
Existing desired mappings, including pending capacity changes and mappings not
yet created, remain intact. This avoids rebuilding the whole bundle from live
views with `save-set`. No device is opened during enrollment: physical presence
and identity are checked by the later `check-bundle` or restoration command.
An unavailable but enrolled empty disk also blocks that later replay.

Both inputs must be bounded regular files with valid versions and checksums;
final symlinks are rejected. Repeated disk keys, duplicate global slots,
invalid imported geometry and the 64-disk/64-mapping limits fail before
publication. The source plan remains unchanged and its readable descriptor
stays open alongside the bundle descriptor through publication. Enrollment uses
the existing atomic publisher and the same durability/error rules as mapping
edits. A bundle cannot import itself as a single-disk plan.

`plan-forget BUNDLE DISK_INDEX` removes an empty enrolled disk. First remove each
of its desired mappings with `plan-remove` if any remain. A populated disk, a
missing index or removal of the last enrolled disk fails without changing the
file. The remaining identities, geometry, modes and global slot ownership
survive. Disk order is stable, but indices after the removed disk decrease by
one; inspect `show-bundle` before subsequent indexed edits. Enrollment appends
and keeps all existing indices unchanged.

Omitting a disk stops requiring its identity during subsequent replay. Its
live mappings, data and open descriptors remain usable, and replay keeps those
unlisted mappings. Their physical extents still obey the ordinary runtime
protections. Reenrollment imports the saved desired rows and resumes complete
preflight; matching live views keep their generations. Administration remains
serialized and live application remains a separate operation. A disk with pool
membership must first have that membership removed before it can be forgotten;
remaining pool disk indices follow the compacted saved order. Spanning volumes
and RAID are still separate work. See
[disk membership qualification](../tests/storage-volumes/disk-bundle.md).

## Bounded extent allocation

```sh
# Choose a region reserved for managed raw volumes on saved disk index 0.
vinix-volume plan-space /root/layout.vset 0 8388608 16777216 1048576
vinix-volume plan-allocate /root/layout.vset 0 20 2097152 8388608 16777216 1048576
vinix-volume check-bundle /root/layout.vset
vinix-volume restore-bundle /root/layout.vset
```

`plan-space BUNDLE DISK_INDEX START_BYTES END_BYTES ALIGNMENT_BYTES` reports
the gaps between saved desired mappings within an explicit allocation region.
The end is exclusive. Both boundaries must fit the saved disk and align to its
logical sector; alignment must be a power of two at least as large as that
sector. Gap starts round upward to the requested alignment. Lengths cover the
remaining sector-aligned portion, so alignment constrains placement rather than
size. Gaps appear in physical offset order even when saved rows are unsorted;
the saved row order and bundle bytes stay unchanged. Read-only desired mappings
occupy space too. The summary reports the count, sum and largest eligible gap;
alignment prefixes are excluded, and a region with no eligible gap succeeds
with zero totals. Rounding remains bounded near the unsigned 64-bit limit.

`plan-allocate BUNDLE DISK_INDEX SLOT LENGTH_BYTES START_BYTES END_BYTES
ALIGNMENT_BYTES [ro]` appends one mapping in the lowest-address gap that fits its
nonzero sector-aligned length. It never combines fragmented gaps or spans disks.
The slot must be globally free, and the complete desired set must remain valid.
All existing identities, row order, lengths and modes survive. Invalid ranges,
slots, modes and sizes, full mapping tables or insufficient contiguous space
fail without publishing. The selected offset, length and mode are printed after
the shared atomic publisher completes. Publication has the same permissions,
flush ordering and error rules as `plan-add`, including a visible new bundle
with a failure result if directory fsync fails after rename.

Both commands operate offline on the existing bounded checksummed bundle;
they open no devices and reject a final symlink or nonregular input. The
allocation region is an explicit administrative choice: these gaps describe
saved desired mappings, not filesystem free space. Reserve partition-table,
filesystem, swap and other data extents when choosing the region. Unlisted live
mappings and protected extents may occupy an offline gap. `check-bundle` detects
live mapping conflicts, and live application retains kernel extent protection
and the ordinary partial-failure rules. Planning does not format, discard,
reserve live storage or alter live descriptors. Administration must remain
serialized; subsequent planning sees the newly saved row. Persistent allocation
pools extend this selection across disk regions below. Spanning volumes and RAID
remain separate work. See
[extent allocation qualification](../tests/storage-volumes/space-bundle.md).

## Adopting physical capacity growth

```sh
# Disk index 0 still identifies this whole disk after its backing capacity grows.
vinix-volume plan-capacity /root/layout.vset 0 /dev/vda 25165824
vinix-volume plan-space /root/layout.vset 0 16777216 25165824 4096
vinix-volume plan-allocate /root/layout.vset 0 20 8192 16777216 25165824 4096
vinix-volume check-bundle /root/layout.vset
vinix-volume restore-bundle /root/layout.vset
```

Saved plans normally match the exact physical capacity. If a virtual backing
disk or physical namespace becomes larger, discovery and ordinary/boot replay
continue to reject the old geometry. `plan-capacity BUNDLE DISK_INDEX DEVICE
EXPECTED_BYTES` explicitly adopts a larger **already observed** capacity for
one enrolled disk. It opens the named whole disk read-only, verifies its valid
MBR signature or checksummed primary GPT GUID, and requires the saved identifier
and logical sector size to match. The observed byte count must equal the
explicit expected value, be sector-aligned, and be at least the saved size.
Shrinks, changed identifiers/sectors, partition/volume targets, offline devices
and another enrolled disk with the same identifier fail without publication.
The disk index follows `show-bundle` order; a reordered device path cannot
silently update a different identifier.

The same descriptor remains open through a second identity/geometry probe and
atomic publication. A changed kernel disk identity, persistent identifier or
capacity between probes aborts. Only that disk's saved capacity changes; all
desired rows, their order, pending unapplied edits, modes and other participants
survive. No mapper mutation, disk write, resnapshot, partition-table update or
filesystem resize occurs. Planning and separate complete-set replay preserve
matching live generations and open descriptors. The newly adopted tail can be
allocated with the existing explicit bounded-region commands, and a tail
mapping can subsequently grow with `plan-grow` and explicit `grow` replay.

The command publishes through the shared write/fsync/rename/directory-fsync
protocol. Repeating an adopted size still verifies the disk and republishes
the same desired bytes, completing the durability protocol even after a prior
directory-flush failure. Its result prints `previous_bytes`, `bytes` and
`changed=0` or `1`. A directory-flush or output failure can return an error
after the complete updated bundle is visible; inspect it and retry. Final
bundle/device symlinks are refused. Administration must remain serialized.

This command does not initiate controller capacity rescanning: the kernel must
already expose the larger geometry, which may require reattachment or reboot
on the selected backend. GPT backup-header relocation, partition resizing,
filesystem growth and RAID remain separate work. Choosing an allocation
region must account for all partition, filesystem, swap and other data or
metadata extents. Disk identifiers retain the existing uniqueness requirement;
cloned signatures/GUIDs do not establish physical provenance. See
[physical capacity qualification](../tests/storage-volumes/capacity-bundle.md).

## Persistent allocation pools

```sh
# Save each disk's identity first, then enroll explicitly eligible regions.
vinix-volume save-set /root/layout.vset /dev/vda /dev/vdb
vinix-volume pool-add /root/layout.vset 3 0 8388608 16777216 4096
vinix-volume pool-add /root/layout.vset 3 1 8388608 16777216 4096
vinix-volume pool-space /root/layout.vset 3
vinix-volume pool-allocate /root/layout.vset 3 20 2097152 ro
vinix-volume show-bundle /root/layout.vset
vinix-volume check-bundle /root/layout.vset
vinix-volume restore-bundle /root/layout.vset
# Remove disk 1 from pool 3 while retaining its desired and live mappings.
vinix-volume pool-remove /root/layout.vset 3 1
```

`pool-add BUNDLE POOL_ID DISK_INDEX START_BYTES END_BYTES ALIGNMENT_BYTES`
adds an eligible region on an enrolled disk. Pool IDs are decimal 0–63, local
to this saved bundle; disk indices follow `show-bundle` order. There are at most
64 region records in total and one region per pool/disk pair. Regions on the
same disk must be disjoint, including regions belonging to different pools;
adjacent regions are valid. Region-bearing disks cannot share an MBR/GPT
identifier, even with different saved capacities. Bounds, exclusive ends,
sector alignment and power-of-two placement alignment follow `plan-space`.

`pool-space BUNDLE POOL_ID` reports each member's eligible gap count, bytes and
largest gap, followed by their aggregate. Alignment prefixes and saved desired
mappings, including read-only mappings, are excluded. The total byte count uses
full 128-bit decimal arithmetic, so large multi-disk totals cannot wrap at
64 bits. An enrolled pool with no gaps reports zero capacity; an absent pool
fails. Queries validate the full bundle and preserve its bytes.

`pool-allocate BUNDLE POOL_ID SLOT LENGTH_BYTES [ro]` chooses the first member
in saved membership order with a fitting sector-aligned contiguous gap, then
the lowest eligible physical offset in that member. A length incompatible with
a member's logical sector size skips that member. The slot must be globally
free. Each result remains one ordinary linear mapping on one physical disk;
aggregate free capacity cannot satisfy a request larger than every individual
gap. The selected disk, offset, length and mode are reported after publication.
All other mappings, identities and pool regions survive unchanged.

`pool-remove BUNDLE POOL_ID DISK_INDEX` removes only the eligible region.
Previously allocated desired rows and live views remain, including their modes,
generations and open descriptors. Removing then adding a member places it last
in allocation order. Forgetting a disk requires no desired mappings or pool
membership; following disk indices are adjusted together. Pool membership does
not tag or restrict ordinary `plan-add`, `plan-grow` or explicit-region edits.
`plan-capacity` preserves the regions; extending eligibility into an adopted
tail uses explicit `pool-expand` below. `save-set` captures a fresh live
mapping snapshot and emits a pool-free bundle, replacing prior desired edits
and pool configuration. Use bundle edits to retain that configuration.

Pool regions and mappings share one checksummed atomic publication. Pool-bearing
files use a 64-byte `VINIXVS2` version-2 header: the existing counts and CRC remain
at their version-1 offsets, region count is a little-endian u32 at byte 28, and
bytes 32–63 are zero. Complete version-1 disk plans are followed by up to 64
40-byte records: pool u32, saved disk index u32, start u64, exclusive end u64,
alignment u64 and eight zero reserved bytes. The maximum file is 8768 bytes.
Version 2 requires at least one region. Pool-free output retains the exact
version-1 format; removing the last region restores it. Older utilities reject
the version-2 magic. `show-bundle` displays all region records; ordinary restore
and boot replay validate them alongside mappings and retain the saved file.

These commands operate offline on bounded regular files, reject final symlinks,
and open no devices. Membership edits and allocations use the existing
write/fsync/close/rename/directory-fsync protocol, publishing metadata and desired
rows together. Failure before rename preserves the previous complete file;
directory-fsync or output failure can report an error after the complete new
file is visible. Administration must remain serialized.

Choose regions that account for partition tables, filesystem data, swap and
other extents. Reported capacity describes saved desired mappings rather than
filesystem free space or a live reservation. Separate complete-set preflight
detects unlisted live conflicts, and application retains kernel extent
protection. Spanning, striping, RAID, filesystem resizing and encryption remain
separate work. See [pool qualification](../tests/storage-volumes/pool-bundle.md).

## Pool expansion and mapping growth

```sh
# Pool 3 already includes saved disk 0, and slot 20 fits inside that member.
# Adopt the larger observed disk first when extending past its saved capacity.
vinix-volume plan-capacity /root/layout.vset 0 /dev/vda 25165824
vinix-volume pool-expand /root/layout.vset 3 0 25165824
vinix-volume pool-grow /root/layout.vset 3 20 4194304
vinix-volume pool-space /root/layout.vset 3
vinix-volume check-bundle /root/layout.vset grow
vinix-volume restore-bundle /root/layout.vset grow
```

`pool-expand BUNDLE POOL_ID DISK_INDEX END_BYTES` increases an existing member's
exclusive end while retaining its start, alignment and allocation priority.
The new end must be at least the saved end, sector-aligned, within the enrolled
disk's saved capacity and disjoint from every other pool region on that disk.
Adjacent regions are valid. Absent members, shrink, overflow, misalignment,
overlap and an unadopted physical tail fail without publication. Existing desired
mappings, including rows inside the added eligibility, remain unchanged and
occupy their usual space. Expansion works even when the region table is full.
It does not add a member, move data or change live mapping capacity.

`pool-grow BUNDLE POOL_ID SLOT LENGTH_BYTES` increases an existing mapping's
desired length in place. Its old and requested extents must both fit entirely
inside this pool's member region on the mapping's current disk. The length must
be nonzero, at least the saved length and sector-aligned, with no overlap with
any other desired mapping. Start, disk identity, slot, read-only mode, row order,
membership order and all other desired state stay fixed. Placement alignment
governs new allocations; growth keeps the existing start. A manually added
mapping wholly inside the selected member can also grow. A mapping outside or
straddling the region fails even for an unchanged-length request. Free capacity
in other gaps or disks cannot bridge the mapping's contiguous extension, and
growth does not relocate it or consume a different member.

Both commands validate the complete saved set and atomically publish the
existing version-2 format without opening devices. Repeating an equal end or
length still writes, fsyncs, renames and fsyncs the directory, completing the
durability protocol after a prior directory-flush failure. Publication and
buffered output errors return failure; after rename, the complete new desired
file may already be visible. Inspection and retry use that new desired state.
Each command publishes separately, so a later failed growth retains an earlier
successful physical-capacity adoption or region expansion.

Apply growth separately with `check-bundle BUNDLE grow` and `restore-bundle
BUNDLE grow`. Ordinary replay still rejects existing smaller live mappings.
Complete-set preflight catches unlisted live extension conflicts before any
action, and explicit replay retains generations and open descriptors, including
read-only ones. Kernel extent protection and the existing partial-application
rules continue to apply. Boot replay recreates the saved grown geometry and
preserves pool metadata. Regions remain an administrative choice accounting for
partition tables, filesystems, swap and other data; expansion does not reserve
live extents. Administration must remain serialized. See
[pool growth qualification](../tests/storage-volumes/pool-growth.md).

## Atomic pool allocation batches

```sh
# Every request has a slot, decimal byte length and explicit rw/ro mode.
vinix-volume pool-preview-batch /root/layout.vset 3 20 4194304 rw 21 1048576 ro
vinix-volume pool-allocate-batch /root/layout.vset 3 20 4194304 rw 21 1048576 ro
vinix-volume check-bundle /root/layout.vset
vinix-volume restore-bundle /root/layout.vset
```

`pool-allocate-batch BUNDLE POOL_ID SLOT LENGTH_BYTES MODE [...]` plans 1–64
requests into one pool and atomically publishes the complete bundle once.
Requests run in argument order, each using saved member order and the lowest
aligned contiguous gap. Earlier placements consume capacity for later requests.
Each mapping stays on one disk. Request ordering can affect feasibility; the
allocator does not reorder or backtrack to find a different packing.

Slots must be distinct and below 64; lengths must be nonzero unsigned decimal
bytes and fit a member's logical sector size. Modes are exactly `rw` or `ro`.
Existing desired mappings and all pool metadata remain unchanged. A later
invalid request, absent pool, occupied incompatible slot, fragmented gap or
capacity failure preserves the entire previous bundle, with no placement
report. The implementation builds a bounded private candidate before publication.

A slot already present in the desired bundle is retained only when its length
and mode match and its complete extent fits this pool's current region on its
current disk. This includes a manually added row; pools do not tag ownership.
Matching rows keep their disk, start and ordering, even if an earlier gap has
become free. An incompatible existing row fails the whole batch; allocation
does not grow, relocate or change its mode. New and matching rows may share a
batch. Retrying a complete batch republishes and flushes even when every row
matches, completing durability after a prior directory-fsync failure.

`pool-preview-batch` accepts the same arguments and uses the same candidate
planner. It prints all placements only after every request succeeds, without
writing the bundle or entering the publisher. Reports include request index,
disk index, slot, `action=allocate` or `action=keep`, offset, length and mode.
Preview failure preserves the file and emits no placement rows. Buffered output
errors return failure for both commands. After a publication succeeds, an output
failure can leave the complete new file visible; inspect it or retry the same
requests. Publisher failures retain the existing before/after-rename guarantees.

Both commands open only the saved bundle. They do not inspect live devices,
reserve live extents, or apply mappings. Run complete-set `check-bundle` and
explicit replay separately; an unlisted live conflict on a later disk prevents
every action during preflight. Administration must remain serialized: a preview
does not pin the saved state against another editor, and live application keeps
the existing partial-application rules. Batch metadata uses the unchanged
version-2 format and existing boot restore. Spanning, RAID, encryption and
filesystem resizing remain open. See
[batch qualification](../tests/storage-volumes/pool-batch.md).

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
operations. AHCI, Apple ANS and the development PCI NVMe driver provide the health queries below.
Vendor-specific wear and temperature interpretation, predictive monitoring and
real-hardware qualification remain future work. Unsupported status backends return
`ENOTTY`. Geometry also supports `BLKGETSIZE64`, `BLKGETSIZE`, `BLKSSZGET`, and
`BLKROGET` without allowing destructive ioctl passthrough.

## Periodic storage monitoring

```sh
# Poll once a minute until interrupted.
vinix-volume monitor /dev/sd0 60
# Collect ten samples for a script, with one second between samples.
vinix-volume monitor /dev/sd0 1 10
```

`monitor` opens one read-only descriptor and combines block status with the
existing ATA/NVMe/ANS health query. The interval is an integer from 1 to 86400
seconds, measured after each completed sample. An optional positive sample count
ends the session; the final sample has no following sleep. Every sample prints
one flushed line, so output is immediately available through pipes.

Lines report the physical disk ID, healthy/warning/media-errors/unavailable,
query-failed or offline state, warning bits, query errno, cumulative backend errors and last
errno, new errors, completed read/write bytes and their deltas. ATA warnings
mean the device's threshold status is exceeded; NVMe/ANS preserve all critical
warning bits, including unknown bits. Partitions and volumes can be monitored
through their status capability while health remains unavailable. Shared parent
counters retain the backend's physical meaning described above.

### NVMe and ANS telemetry

Successful NVMe/ANS samples append `telemetry=nvme scope=controller`, temperature
in kelvin (zero is reported as unavailable), spare/threshold percentages and
percentage used, which can exceed 100. All ten standard counters and their
`_delta` fields retain the full unsigned 128-bit value as 32 hexadecimal digits.
Data units stay in the device's reported units rather than being converted to
bytes; these controller totals are separate from namespace/backend I/O counters.

The first successful NVMe/ANS sample establishes `health_baseline=1` and zero
hardware deltas. Historical media errors do not fail it. New media errors set
`health=media-errors` and make the session return 1 even if no critical-warning
bit is set. Growth of the error-log entry counter is reported but does not by
itself imply a media failure. No extra warning thresholds or prediction are
inferred from temperature, spare or wear fields.

A decrease in any of the ten hardware counters sets `health_counters_reset=1`
and starts a fresh hardware baseline with zero deltas. This baseline is independent
of the driver I/O counters. Failed/unavailable queries print `telemetry=unavailable`
without presenting stale measurements; the next successful NVMe/ANS query covers
the gap since the last successful query. A successful ATA report clears the
NVMe baseline. ATA vendor attributes remain available through `health` without
guessing their units. Partitions and linear volumes also print unavailable
telemetry. No hardware counter baseline is persisted across utility invocations.

### Sampling and exit status

The first sample establishes the backend counter baseline, so historical errors do not
fail a fresh session. A decreasing counter sets `counters_reset=1` and starts a
fresh baseline with zero deltas. Device ID, start offset, mapper slot and
generation must remain stable across the session and each health query; an
identity change stops monitoring. Capacity growth can retain the same identity.
Health and status are separate snapshots; status is refreshed after health so
a query's error/offline transition is reported immediately. An offline snapshot
skips the health command and keeps reporting status.

Bounded sessions retain their most serious observation even after recovery:
exit 1 for query/output/status failures, offline state or newly observed backend
or media errors; otherwise exit 3 for any device health warning, 4 for unavailable health,
or 0 for healthy samples. Invalid arguments return 2 before opening the device.
Invalid reports and identity changes stop immediately with exit 1. Monitoring
uses the ordinary read/ioctl access gates and requires no management privilege.
The report and counter snapshots use fixed caller-stack storage throughout the
loop. Warnings come from device reports; vendor-specific interpretation and
failure prediction remain open. See [monitor qualification](../tests/storage-monitor/README.md).

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

## NVMe SMART/Health

```sh
vinix-volume health /dev/nvme0n0
```

Whole native PCI NVMe namespaces support the same read-only health ioctl and
descriptor/MAC policy. The driver retains its existing development-build
activation policy (`PROD=false`); production probing and physical-controller
qualification remain separate work. VirtIO, partitions and linear
views remain unsupported. The query accepts no admin command passthrough.

Protocol 2 uses the existing 1088-byte version-one ABI: its identity payload is
the first 512 bytes of a fresh 4096-byte Identify Controller response, and its
data payload is the complete 512-byte SMART/Health Information log (LID 2).
The log is controller-wide (`NSID=0xffffffff`), including when opened through a
particular namespace; the runtime disk ID still identifies the opened namespace.
Multiple namespaces on the same controller therefore report the same health
scope. The query sets RAE to retain pending asynchronous notifications. It
changes no features, warning thresholds, self-tests or namespace data.

Flags 1/2/4/8 indicate that the mandatory log is supported, usable, returned
and has valid warning status. Flag 16 means the critical-warning byte is nonzero,
including warning bits unknown to this utility. A command failure returns an
error without publishing a partial report. NVMe has no ATA data checksum or
completion transfer-length field; successful command completion is the trust
boundary for the device's returned payload. The identity and log are two
successive commands, rather than an atomic controller snapshot.

Each query uses one zeroed, private, page-aligned DMA page and the existing
controller lock, completion checks and timeout policy. The page is freed after
both completed commands or an ordinary completion error. After a timeout it is
freed only if controller disable confirms DMA has stopped; otherwise that one
submitted page remains quarantined and later queries submit nothing. There is
no per-query kernel heap allocation. Health queries leave completed block I/O
counters unchanged; backend failures increment the namespace's error metric.

The utility prints sanitized model, serial and firmware, the raw critical-warning
byte, temperature in kelvin (zero means unavailable), available spare and its
threshold as percentages, and the device's percentage-used estimate. That
estimate may exceed 100. Ten standard counters are printed as full 128-bit
hexadecimal values, without truncation or conversion of data units to bytes.
Exit status is 0 with no critical warnings, 3 when any are active, 1 for a query
or report error and 2 for invalid usage. No warnings is a current device report,
not a prediction or a durability guarantee.

Protocol references are the
[NVM Express Base Specification](https://nvmexpress.org/wp-content/uploads/NVM-Express-Base-Specification-2.0e-2024.07.29-Ratified.pdf),
[libnvme SMART/Health and identity definitions](https://github.com/linux-nvme/libnvme/blob/master/src/nvme/types.h)
and [QEMU's NVMe controller implementation](https://github.com/qemu/qemu/blob/master/hw/nvme/ctrl.c).
See [native health qualification](../tests/storage-health/README.md).

## Apple ANS SMART/Health

```sh
vinix-volume health /dev/ans0n1
```

Whole namespaces published by the opt-in base-M1 ANS2 driver support protocol 2
and the same controller-wide identity, SMART log, warning flags and utility
output described above. Namespace names use the actual namespace ID. ANS GPT
partitions and logical views return `ENOTTY`. The query requires readable access
and passes through the same descriptor/MAC checks and output-only usercopy.

The ANS operation lock covers both fresh admin commands and both payload copies,
serializing them with namespace I/O and shutdown. Identify uses 4096 bytes of the
existing permanently pinned DMA bounce buffer; Get Log Page uses 512 bytes.
Each transfer is cleared and synchronized before submission, then synchronized
for CPU access after a validated completion. The lowest submission layer permits
only SMART/Health LID 2, controller-wide NSID, RAE=1, exactly 128 dwords, zero
offset/extensions and the driver's fixed bounce address. No passthrough or
write-policy change is exposed.

Ordinary command completion errors return `EIO` without publishing a partial
report and allow a later query to retry. Timeouts, firmware failures and invalid
completions retain the existing failed-controller policy: DMA stays pinned and
later health calls neither clear it nor submit. Stopping/stopped controllers
also reject calls before touching DMA. Reports, command bytes and interface
dispatch use the caller's stack; queries allocate no heap or physical pages and
do not charge completed disk transfers. Failed backend health requests increment
the namespace's block error counter once; successful queries leave I/O counters
unchanged.

The driver still requires explicit ANS boot opt-in and its existing clean
handoff/platform checks. Host transport faults and an isolated ARM kernel model
qualify command encoding, cache ownership, dispatch and 200-query retention;
they do not qualify health-log accuracy or firmware support on a physical M1.
See [ANS boot and hardware acceptance](apple-ans-rw-root.md) and
[native health qualification](../tests/storage-health/README.md). The ANS NVMMU
layout follows the [Linux Apple NVMe driver](https://github.com/torvalds/linux/blob/master/drivers/nvme/host/apple.c).

## Apple ANS block status

```sh
vinix-volume status /dev/ans0n1
vinix-volume status /dev/ans0n1p1
```

Published ANS namespaces and GPT partitions expose the version-one, 128-byte
block status ABI. Capacity and start offset describe the opened view. `disk_id`
identifies its physical namespace; partitions set flag 16 and share that
namespace's counters. Namespace IDs remain distinct, including after shutdown.
The whole namespace stays read-only. Only the boot-selected writable Linux-data
partition clears the read-only flag while the controller is ready and its write
policy remains valid. Failed or stopping/stopped controllers report offline and
read-only; status remains readable without submitting a command or touching DMA.

ANS counters measure successfully completed physical commands and bytes,
including native root/data filesystem traffic. A rounded read counts all sectors
transferred; a partial write counts its boundary reads, written sectors and
implicit flush. A resource sync flushes every namespace, charging each successful
flush to that namespace. Completed prefixes remain counted when a later command
fails. These are physical command counts, rather than counts of userspace calls.
Failed block read/write/sync and supported health requests increment `errors`
once on the requesting namespace and retain their errno in `last_error`.
Validation failures count; zero-byte/EOF success and successful metadata queries
do not. Native filesystem internal failures are not additional block requests.

Snapshots and updates share the ANS operation lock. Eight fixed counter records
require no allocation on repeated paths and preserve the exported transport
layout used by existing controller fixtures. Status metadata does not enable ANS
linear volumes, raw writes, discard or controller reconstruction. ANS volume
management still needs qualification of native filesystem extent protection.

The [V transport tests and ARM kernel fixture](../tests/storage-health/README.md)
cover shared geometry/counters, read-modify-write, completed prefixes, failures,
offline state and 200 allocation-flat I/O/error cycles. QEMU exercises the
software model; physical base-M1 controller and firmware qualification remains
required as described in [ANS acceptance](apple-ans-rw-root.md).

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

NVMe discard and health are qualified with production command/completion code
and mocked MMIO on the host, including 200 successful operations and failed-reset
DMA ownership. NVMe now maps high 64-bit BAR registers and the required doorbells
uncached instead of assuming they are in the initial direct map. Its polled
completion queues leave interrupts disabled. The development-only activation
policy, physical-controller and power-loss qualification remain open. The
development guest also checks healthy/warning NVMe responses and retained heap
across 200 plan cycles, including 200 successful and 200 bad-pointer queries
per namespace after warmup. This measurement exposed heap-promoted read command
temporaries; read and flush commands now stay on the caller's stack while their
DMA payloads retain the existing completion/reset ownership rules.

The encompassing roadmap item stays open: spanning volumes/RAID, full-disk
encryption and recovery, online filesystem resize,
filesystem-aware trimming and predictive health monitoring are not
implemented by this increment. The anonymous pager's encrypted swap remains a
separate feature.
