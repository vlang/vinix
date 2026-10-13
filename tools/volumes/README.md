# vinix-volume

Native V block-volume management utility. See
[the storage interface and limits](../../docs/storage-volumes.md) for commands,
privileges, ABI, lifetime and geometry rules.

`open-recovery-volume-auto BACKUP RECOVERY_KEYFILE [ro]` directly discovers and
unlocks the backed-up encrypted mapping after credential loss. It authenticates
before disk access, erases recovery credentials before discovery, preserves
saved read-only mode and allows an additional `ro` restriction. It creates no
configuration or raw keyfile. See [direct recovery unlock](../../docs/storage-volumes.md#direct-recovery-key-unlock).

`backup-volume CONFIG PASSPHRASE_FILE RECOVERY_KEYFILE BACKUP` preserves an
authenticated encrypted mapping and its key under an independent recovery key.
`recover-volume BACKUP RECOVERY_KEYFILE NEW_PASSPHRASE_FILE CONFIG` rebuilds an
ordinary sealed configuration after credential/configuration loss. Both are
offline, private and no-overwrite operations, with no disk access or raw keyfile.
See [configuration recovery](../../docs/storage-volumes.md#encrypted-volume-configuration-recovery).

`boot-restore` combines `/etc/vinix/boot-volume.vcrypt` and its
`boot-volume.pass` with named `NAME.vcrypt`/`NAME.pass` pairs in
`/etc/vinix/boot-volumes.d`. All inputs authenticate, saved slot/extent conflicts
are rejected, and every encrypted physical disk is pinned and rechecked before
plain application. Root-owned private inputs are relative to retained trusted
directories; credentials erase before discovery. `boot-unlock` applies only
this optional encrypted set. Missing configurations mean disabled. The set is
bounded to 64 mappings; later application failures can leave earlier mappings.
See [multiple encrypted boot volumes](../../docs/storage-volumes.md#multiple-encrypted-boot-volumes).
See [startup behavior and credential limits](../../docs/storage-volumes.md#opt-in-encrypted-boot-unlock).

`plan-grow-volume DEVICE CONFIG PASSPHRASE_FILE LENGTH_BYTES NEW_CONFIG`
authenticates saved encrypted metadata, checks the same identity/native sectors
on a pinned read-only parent, and publishes a separate configuration adopting
nondecreasing physical capacity and extent length. Key, start, slot and readonly
mode remain exact; credentials/key erase before publication. Apply live growth
or reopen separately. See [growth and limits](../../docs/storage-volumes.md#authenticated-encrypted-volume-growth).

`open-volume-auto CONFIG PASSPHRASE_FILE [ro]` authenticates before discovering
the unique matching physical disk, then imports through its retained descriptor.
It survives device renumbering, accepts physical aliases, rejects matching
clones, enforces saved readonly mode and creates no raw keyfile. See
[automatic discovery and limits](../../docs/storage-volumes.md#automatic-encrypted-volume-discovery).

`rewrap-volume CONFIG OLD_PASSPHRASE_FILE NEW_PASSPHRASE_FILE NEW_CONFIG`
changes credentials without exporting the raw key or opening a disk. It preserves
all authenticated disk/mapping metadata and readonly mode, refreshes salt/nonce,
erases credential buffers before reuse and publishes a separate private file.
Old configurations remain usable with their old credentials. See
[credential changes and limits](../../docs/storage-volumes.md#changing-encrypted-volume-configuration-credentials).

`seal-volume DEVICE SLOT OFFSET_BYTES LENGTH_BYTES KEYFILE PASSPHRASE_FILE
CONFIG [ro]` binds disk identity and mapping geometry to a wrapped key.
`open-volume DEVICE CONFIG PASSPHRASE_FILE [ro]` authenticates before verifying
the pinned disk and importing that mapping; saved readonly mode cannot escalate.
`unseal-volume-key CONFIG PASSPHRASE_FILE KEYFILE` explicitly recovers a private
key offline. Outputs never replace existing entries. See
[authenticated configuration format and limits](../../docs/storage-volumes.md#authenticated-encrypted-volume-configurations).

`rewrap-key ENVELOPE OLD_PASSPHRASE_FILE NEW_PASSPHRASE_FILE NEW_ENVELOPE`
authenticates a sealed volume key and protects the same key with new credential
bytes, fresh salt and nonce, without a plaintext keyfile. It publishes a separate
private envelope without replacing existing entries; retained old envelopes
remain usable. See [credential changes and limits](../../docs/storage-volumes.md#changing-sealed-key-credentials).

`seal-key KEYFILE PASSPHRASE_FILE ENVELOPE` wraps an existing volume key with
salted scrypt. `unseal-key ENVELOPE PASSPHRASE_FILE KEYFILE` authenticates before
restoring a private keyfile. `open-sealed DEVICE SLOT OFFSET_BYTES LENGTH_BYTES
ENVELOPE PASSPHRASE_FILE [ro]` unlocks directly without writing a plaintext key.
The fixed profile uses 32 MiB; credentials are private owned files containing
1–1024 exact bytes. Existing destinations are preserved. See
[sealed-key format, work profile and limits](../../docs/storage-volumes.md#passphrase-sealed-volume-keys).

`vinix-volume backup-key KEYFILE RECOVERY_KEYFILE ENVELOPE` wraps a 64-byte volume
key with a separate random 64-byte recovery key. `recover-key ENVELOPE
RECOVERY_KEYFILE KEYFILE` authenticates the backup before restoring an exact
private keyfile. Both commands preserve existing destinations. Retain the
recovery key separately and save the original volume geometry. See
[key recovery format, publication and limits](../../docs/storage-volumes.md#authenticated-volume-key-recovery).

`vinix-volume monitor DEVICE INTERVAL_SECONDS [SAMPLES]` periodically reports
health warnings, offline/error state and completed I/O byte deltas through one
read-only descriptor. Omit the sample count to run until interrupted. Bounded
sessions retain warnings or failures in their exit code even after recovery;
unavailable health still permits status monitoring. See
[monitoring semantics and exit codes](../../docs/storage-volumes.md#periodic-storage-monitoring).
NVMe/ANS samples include standard thermal/wear fields and all ten hardware
counters with full 128-bit deltas. New media errors fail the session even when
the critical-warning byte remains zero.

`vinix-volume health DEVICE` queries whole AHCI ATA disks without changing
SMART settings. It prints sanitized identity, the drive's threshold status
and vendor-specific raw attributes. Exit 3 means the threshold is exceeded;
4 means ATA status is unavailable. Unsupported backends return an error.
See [the health ABI and limits](../../docs/storage-volumes.md#ata-smart-health).

The same command supports whole PCI NVMe namespaces in development kernels.
It prints controller-wide critical warnings, standard health fields and ten
full 128-bit counters; exit 3 means at least one critical warning is active.
See [NVMe scope and limits](../../docs/storage-volumes.md#nvme-smarthealth).

`vinix-volume discard DEVICE OFFSET_BYTES LENGTH_BYTES` deallocates a range
through supported block backends. The offset and length are decimal bytes.
See the storage documentation for extent protection and interruption behavior.

`vinix-volume save DEVICE PLAN` atomically saves the selected whole disk's
managed views. `vinix-volume restore DEVICE PLAN` verifies disk identity and
geometry, rejects conflicting slots and creates missing mappings. Repeated
restore keeps matching views. Use a persistent filesystem for the plan; disk
discovery uses `vinix-volume discover PLAN`, and `restore-auto PLAN` restores
the unique physical match. Distinct disks with duplicate identity are rejected.

`vinix-volume save-set BUNDLE DEVICE [DEVICE ...]` saves all selected disks in a
single checksummed file, publishing the complete set with one atomic rename.
`restore-bundle BUNDLE` discovers every disk and preflights the whole set before
creating mappings. See [bundle format and durability limits](../../docs/storage-volumes.md#atomic-multi-disk-bundles).

`plan-grow BUNDLE SLOT LENGTH_BYTES` atomically updates desired capacity without
changing a live mapping. `restore-bundle BUNDLE grow` explicitly applies in-place
growth after complete-set preflight, retaining generations and open descriptors.
Ordinary and boot replay retain exact-size matching for existing views. See
[capacity planning and replay](../../docs/storage-volumes.md#planned-capacity-growth).

`show-bundle BUNDLE` displays verified saved identities and mapping geometry
offline. `check-bundle BUNDLE [grow]` opens devices read-only and uses restoration's
complete-set preflight to preview create/keep/grow actions and captured generations.
See [inspection and check limits](../../docs/storage-volumes.md#bundle-inspection-and-preflight).

`plan-add BUNDLE DISK_INDEX SLOT OFFSET_BYTES LENGTH_BYTES [ro]` adds a mapping
offline using the disk's saved index. `plan-remove BUNDLE SLOT` removes its
desired entry. Both atomically publish a validated complete set; live mappings
are changed only by separate runtime commands. See
[offline configuration editing](../../docs/storage-volumes.md#offline-mapping-configuration).

`plan-add-batch BUNDLE IDENTITY SLOT OFFSET_BYTES LENGTH_BYTES MODE [...]`
adds 1–64 explicit mappings across enrolled disks in one atomic publication.
Select MBR/GPT identities from `show-bundle`; modes are `rw` or `ro`.
Matching rows are durable keep retries, even after unrelated disk indices
shift. A later conflict preserves the whole saved set and pool priority.
`plan-preview-add-batch` reports every placement without device probes, writer
locking or publication. Live preflight/replay remains separate. See
[explicit addition batch rules](../../docs/storage-volumes.md#atomic-explicit-mapping-additions).

`plan-grow-batch BUNDLE IDENTITY SLOT LENGTH_BYTES [...]` grows 1–64 explicit
desired mappings in one atomic edit, preserving offsets, modes and pool priority.
Select MBR/GPT identities from `show-bundle`; equal-size requests keep their rows.
Wrong-disk, later overlap/alignment/overflow/shrink or duplicate-slot failures
roll back the complete set. `plan-preview-grow-batch` reports every action without
physical probes, writer locking or publication. Explicit live growth replay stays
separate. See [explicit growth rules](../../docs/storage-volumes.md#atomic-explicit-mapping-growth).

`pool-contract-batch BUNDLE POOL IDENTITY END_BYTES [...]` releases the unused
tails of 1–64 saved pool windows, protecting every desired occupied intersection.
Disk identities survive index compaction. Starts, alignment, mappings and priority
stay exact; equal ends are durable keep retries. `pool-preview-contract-batch`
reports all actions without device probes, writer locking or publication. Live
views remain intact. See [contraction rules](../../docs/storage-volumes.md#atomic-pool-eligibility-contraction).

`pool-resize-batch BUNDLE IDENTITY POOL START_BYTES END_BYTES [...]` atomically
resizes 1–64 existing windows across pools, protecting occupied intersections
at both ends. Final-set validation permits adjacent pools to exchange unused
capacity in either order while retaining alignment and priority. Equal bounds
are durable keep retries. `pool-preview-resize-batch` reports the complete edit
without writer locking or publication. See [cross-pool resizing rules](../../docs/storage-volumes.md#atomic-cross-pool-window-resizing).

`plan-remove-batch BUNDLE SLOT [...]` removes 1–64 distinct desired slots across
disks in one atomic publication. Absent slots are durable `keep` retries;
remaining mappings, enrolled disks and pool priority are preserved.
`plan-preview-remove-batch` reports the complete remove/keep list without
devices, writer locking or publication. Live views survive desired omission.
See [removal batch rules](../../docs/storage-volumes.md#atomic-desired-mapping-removal-batches).

`plan-enroll BUNDLE PLAN` appends a saved single-disk plan without resnapshotting
existing desired mappings. `plan-forget BUNDLE DISK_INDEX` removes an empty
participant while retaining at least one disk. Both edit saved membership;
live views survive omission. See
[disk membership and index rules](../../docs/storage-volumes.md#offline-disk-membership).

`plan-enroll-batch BUNDLE PLAN [...]` atomically imports 1–64 snapshots with
complete read-only `plan-preview-enroll-batch` reports. New disks append;
existing identities are durable keep retries only when their full saved
geometry and ordered mappings match. Pinned read-only sources are rechecked
before publication/reporting; later failures preserve the whole original set.
See [enrollment batch rules](../../docs/storage-volumes.md#atomic-disk-enrollment-batches).

`plan-forget-batch BUNDLE IDENTITY [...]` atomically removes 1–64 empty
participants by the MBR/GPT identities printed by `show-bundle`. Absent identities
are durable keep retries, independent of changing disk indices. Remaining disks
keep their order; pool references follow their compacted indices without changing
priority. `plan-preview-forget-batch` reports every action and survivor index
without publication or writer locking. Populated disks, pool members and removal
of the last disk fail as a whole. See
[identity removal rules](../../docs/storage-volumes.md#atomic-disk-forgetting).

`plan-space BUNDLE DISK_INDEX START_BYTES END_BYTES ALIGNMENT_BYTES` reports
aligned gaps between saved mappings in an explicitly chosen region.
`plan-allocate BUNDLE DISK_INDEX SLOT LENGTH_BYTES START_BYTES END_BYTES
ALIGNMENT_BYTES [ro]` atomically adds the lowest-address fitting mapping.
See [allocation scope and rules](../../docs/storage-volumes.md#bounded-extent-allocation).

`plan-capacity BUNDLE DISK_INDEX DEVICE EXPECTED_BYTES` adopts a larger observed
whole-disk capacity after verifying the unchanged MBR/GPT identifier and sector
size through one retained read-only descriptor. It preserves desired mappings
and uses atomic publication; allocation and live replay remain separate. See
[physical capacity adoption](../../docs/storage-volumes.md#adopting-physical-capacity-growth).

`plan-capacity-batch BUNDLE DISK_INDEX DEVICE EXPECTED_BYTES [...]` adopts
1–64 observed capacities together. It pins every physical disk read-only and
rechecks every identity/geometry after the complete candidate is planned.
A later failure preserves all saved state. `plan-preview-capacity-batch` uses
the same verification without publication or a writer lock. Equal-capacity
retries still complete publication and both flushes. See
[atomic capacity adoption rules](../../docs/storage-volumes.md#atomic-physical-capacity-adoption-batches).

`pool-add-batch BUNDLE POOL_ID DISK_INDEX START_BYTES END_BYTES ALIGNMENT_BYTES
[...]` and `pool-remove-batch BUNDLE POOL_ID DISK_INDEX [...]` atomically change
1–64 pool members together. Matching additions preserve member priority; absent
removals support durable retries. A later failure discards the entire edit.
`pool-preview-add-batch` and `pool-preview-remove-batch` perform complete planning
without a writer lock or publication. See
[membership batch rules](../../docs/storage-volumes.md#atomic-pool-membership-batches).

`pool-order BUNDLE POOL_ID DISK_INDEX [...]` sets an existing pool's allocation
priority with a complete member permutation. Member bounds and desired mappings
are preserved; unrelated pools keep their positions. `pool-preview-order`
reports the complete move/keep list without publication or writer locking.
Unchanged-order retries still complete both flushes. See
[priority rules](../../docs/storage-volumes.md#explicit-pool-allocation-priority).

`pool-add BUNDLE POOL_ID DISK_INDEX START_BYTES END_BYTES ALIGNMENT_BYTES`
enrolls an eligible region in a persistent allocation pool. `pool-space BUNDLE
POOL_ID` reports each member and full-width aggregate capacity. `pool-allocate
BUNDLE POOL_ID SLOT LENGTH_BYTES [ro]` chooses the first fitting member in saved
order and atomically publishes one contiguous mapping with the pool metadata.
`pool-remove BUNDLE POOL_ID DISK_INDEX` removes membership while retaining desired
and live mappings. Pool-bearing bundles use version 2; pool-free bundles retain
version 1. See [pool bounds, persistence and allocation rules](../../docs/storage-volumes.md#persistent-allocation-pools).

`pool-expand BUNDLE POOL_ID DISK_INDEX END_BYTES` extends an existing member's
eligibility without changing its allocation priority. `pool-grow BUNDLE POOL_ID
SLOT LENGTH_BYTES` grows a desired mapping within that member's contiguous
bounds, preserving its disk, start and mode. Both publish offline, including
equal-size durability retries; live growth uses separate explicit replay. See
[pool expansion and growth rules](../../docs/storage-volumes.md#pool-expansion-and-mapping-growth).

`pool-allocate-batch BUNDLE POOL_ID SLOT LENGTH_BYTES MODE [...]` plans 1–64
ordered requests with explicit `rw`/`ro` modes and publishes them together.
Matching existing rows remain fixed, allowing durable retries. A later failure
preserves the entire saved state. `pool-preview-batch` reports the same complete
placements without publication. Live checking/application remain separate. See
[atomic batch rules](../../docs/storage-volumes.md#atomic-pool-allocation-batches).

`pool-grow-batch BUNDLE POOL_ID SLOT LENGTH_BYTES [...]` grows 1–64 existing
desired mappings together, preserving each disk, start and mode. A later
failure preserves the complete saved state. `pool-preview-grow-batch` reports
the same complete candidate without publication. Equal-size requests report
`keep`; retries still complete publication and both flushes. Live growth uses
separate explicit replay. See
[atomic growth batch rules](../../docs/storage-volumes.md#atomic-pool-growth-batches).

`pool-expand-batch BUNDLE POOL_ID DISK_INDEX END_BYTES [...]` extends 1–64
existing members together, preserving starts, alignment and allocation priority.
A later failure preserves the entire saved state. `pool-preview-expand-batch`
reports the complete candidate without publication. Equal ends report `keep`;
retries still complete publication and both flushes. Adopt physical capacity
separately before expanding beyond its saved bounds. See
[atomic expansion batch rules](../../docs/storage-volumes.md#atomic-pool-expansion-batches).

`plan-contract-capacity-batch BUNDLE IDENTITY DEVICE EXPECTED_BYTES [...]`
adopts observed smaller or equal physical capacities for 1–64 enrolled MBR/GPT
identities together. Every desired row and pool window must fit; adjust unused
pool eligibility first. All devices remain pinned read-only through final
identity/geometry rechecks, publication and reporting. A later failure preserves
the complete saved state. `plan-preview-contract-capacity-batch` verifies the
same complete candidate without a writer lock or publication. Equal sizes
report `keep` and still complete both publication flushes. See
[physical contraction rules](../../docs/storage-volumes.md#atomic-physical-capacity-contraction-batches).

`pool-allocate-set-batch BUNDLE POOL SLOT LENGTH_BYTES MODE [...]` allocates
1–64 ordered requests across multiple pools in one atomic saved-state edit.
Each request follows its own pool's member priority and aligned first fit.
Matching rows stay fixed; a later failure discards every earlier placement.
`pool-preview-set-batch` reports the same complete placements without a writer
lock or publication. All-keep retries still complete both publication flushes.
See [multi-pool allocation rules](../../docs/storage-volumes.md#atomic-multi-pool-allocation-batches).

`pool-grow-set-batch BUNDLE POOL SLOT LENGTH_BYTES [...]` grows 1–64 existing
mappings across multiple pools in one atomic saved-state edit. Both old and
requested extents must fit each row's own member; offsets/modes stay fixed.
Later failure discards every earlier growth. `pool-preview-grow-set-batch`
reports the complete candidate without a writer lock or publication. All-keep
retries still complete both publication flushes. See
[multi-pool growth rules](../../docs/storage-volumes.md#atomic-multi-pool-growth-batches).

`hash-bundle BUNDLE MANIFEST DISK_INDEX DEVICE [...]` records SHA-256 for every
desired extent in a separate atomic manifest. Supply every saved disk exactly
once; devices are pinned read-only and their identities/geometry rechecked.
`verify-data MANIFEST DISK_INDEX DEVICE [...]` verifies the complete saved
reference after device reordering. `show-data MANIFEST` inspects the reference
offline. Keep data writes quiescent while hashing/verifying and retain a trusted
manifest separately. See [data checksum manifests](../../docs/storage-volumes.md#data-checksum-manifests)
for consistency, format and corruption detection limits.

`scrub-data MANIFEST REPORT DISK_INDEX DEVICE [...]` checks all saved extents
and atomically records every match/mismatch with expected and actual SHA-256.
The report also fingerprints the trusted reference. Clean scans return 0,
complete scans with changed data return 2, and scan/publication/output failures
return 1. Incomplete scans preserve the previous report. Reference bytes, live
mappings and data remain intact. See
[complete data scrubbing](../../docs/storage-volumes.md#complete-data-scrubbing).

Saved-plan writers acquire a nonblocking exclusive lock on the destination
directory before reading or snapshotting, holding it through atomic publication.
A busy directory returns failure; retry reads the latest complete state. All
destinations in one directory coordinate, and another directory is independent.
Close or process exit releases the lock without a lock file. Read-only queries
and previews remain available. See
[writer locking and live administration limits](../../docs/storage-volumes.md#saved-plan-writer-locking).

Init runs `vinix-volume boot-restore` before applications. It replays the
optional root-owned `/etc/vinix/volumes.vmap`, `/etc/vinix/volumes.vset` bundle and visible `.vmap` files in
`/etc/vinix/volumes.d` as one set. Absence is a no-op, and failure is reported
while boot continues. The configuration directories and enabled files must
not be writable by group or others. One plan per disk and unique global mapper
slots are required. `restore-set DIRECTORY` applies a directory explicitly.
All plans, discovered disks and existing slot/extent conflicts are checked
before any mapping is created. Matching mappings keep their generations.
See the storage documentation for bounds, partial creation failures, serialized
administration, alias behavior and filesystem/mount limits.

The image builders call `build-support/storage-tools/stage.v`, which uses the
repository's V module producer and a static target musl compiler. To install it
into an existing target filesystem:

```sh
V=/path/to/v build-support/run-v-tool.sh build-support/storage-tools/stage.v \
  --arch x86_64 --staging /path/to/userland
```

For ARM, use `--arch aarch64` and `--cc` or `VINIX_MUSL_CC_AARCH64` to select the
cross compiler executable (arguments are not shell-split). Staging verifies the
compiler and output ELF architecture and
replaces only `usr/sbin/vinix-volume` atomically.
