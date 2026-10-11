# Physical capacity adoption qualification

Run the native V `plan_run.v` host suite and both architecture guest suites as
documented in [the storage-volume harness](README.md). This qualifies
`plan-capacity BUNDLE DISK_INDEX DEVICE EXPECTED_BYTES`; no new ioctl or kernel
test hook is introduced.

The command accepts only a valid complete bundle and a whole disk whose
observed capacity equals the explicit expected size. The saved MBR/GPT
identifier and sector size must remain unchanged, capacity cannot shrink, and
another enrolled participant must not carry the same identifier even at a
different geometry. Two probes use the same retained read-only descriptor.
Only the chosen saved byte count changes, preserving all desired mappings and
pending edits. Runtime mapping changes use separate complete-set replay.

Host ASan/UBSan coverage includes:

- MBR and checksummed GPT identity, 512/4096-byte sectors, writable/read-only
  whole disks, unsorted desired rows/modes and unchanged other participants.
- Exact expected size, shrinking/unaligned/changed geometry, absent indices,
  empty/invalid sets, ambiguous identifiers across different geometries,
  full 64-disk/64-slot bundles and the last sector-aligned u64 capacity.
- One device open/close, EINTR identity-read retries, short/error reads, failed
  status/open, unsupported/offline/partition/mapper targets, changed identifiers,
  changed observed capacity and changed kernel disk identity on the second probe.
- Unchanged bundle bytes on rejection, invalid checksum, final bundle symlinks,
  nonregular or missing bundle inputs and malformed CLI arguments before I/O.
- Real file publication with interrupted/short writes and injected write,
  file-fsync, temporary-close, rename and directory-fsync failures. Before
  rename the old bundle survives; afterward the complete new bundle can be
  visible with a failure result. Temporary files and device descriptors drain.
- Repeated equal-size adoption still performs publication and both flushes.
  It preserves desired bytes and reports write/output errors instead of silently
  skipping durability. Buffered stdout failure is detected after publication.
- Complete generated ARM64/x86 utility C contains no heap-allocation or V
  runtime dependency. Existing format, restore, publisher and init-policy tests
  remain enabled.

The QEMU fixtures run the existing functional and 200-warmup/200-measured
retention checks with an additional unchanged-capacity command per cycle.
Every slab class and the large-page total must stay flat or decrease.
After ordinary saved-bundle restore succeeds on a second boot with reordered
disks, the V controller extends only its disposable raw backing file from
16 MiB to 24 MiB. It does not inject a bundle or phase marker into the guest.

The third boot requires production init to reject the stale physical geometry
and create no prefix. The application checks allocation beyond the saved size
fails, and refuses the wrong device, unexpected size, shrink, unaligned size,
absent index, regular-file target and final device symlink without changing the
bundle. A physical mknod alias is accepted. Adoption creates no live mapping;
ordinary replay restores the five saved mappings and their previous durable data.

The application then enrolls a tail pool, previews/publishes eligibility to the
adopted capacity in an expansion batch and retries its equal end. It allocates
a writable tail view at byte 16777216, applies
it separately, and writes its first page. It plans growth from 4096 to 8192
bytes, confirms ordinary replay refuses the size mismatch, and explicitly
applies growth through a retained descriptor. The descriptor writes and flushes
the new page; its generation and an old held descriptor/data remain intact.
Desired growth now uses `pool-grow`, bounded by the expanded tail member.
After growth, a batch retains the writable tail row and adds a read-only neighbor
whose raw page is flushed first. A growth batch then keeps the writable row and
grows the neighbor to 8192 bytes. Its held read-only descriptor reads the flushed
extension page after explicit replay. The application persists the complete seven-
mapping bundle and its reboot marker. On the fourth boot, production init must
restore all seven mappings before the application starts; old data/modes, both
tail pages and both neighbor pages, correct physical disk identities and repeated
adoption/boot replay are verified.
The original two pool records and the newly expanded tail pool survive adoption
and reboot; the fourth boot requires their exact eligible capacity reports.
See [expansion batch qualification](pool-expand-batch.md) for complete rollback
before capacity adoption and the saved eligibility preview/retry.

Real guest coverage uses MBR disks with 512-byte logical sectors on VirtIO
(ARM64) and AHCI (x86). GPT, 4096-byte sectors, probe races and publication
faults have host-model coverage. This does not qualify controller rescanning,
hot removal, GPT backup relocation, partition/filesystem resizing, spanning
volumes, RAID or full-disk encryption.
