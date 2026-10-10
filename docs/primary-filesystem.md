# Journaled primary filesystem

Blank disks installed by Vinix now use VJFS, a private journaled format built
on the EXT2 block, inode and directory layouts. Its superblock signature is
`0x4a56`, distinct from EXT2's `0xef53`. Foreign EXT2/EXT3 drivers must not
mount it and bypass recovery. Existing EXT2 volumes keep their existing format
and writeback behavior; they are not silently converted.

The formatter reserves a 4 MiB journal at the aligned end of the backing
device, outside the filesystem block allocator. It writes and barriers all
initial metadata and the journal configuration before publishing the primary
superblock signature. Reformatting invalidates the old primary signature and
barriers it before discarding any old commit marker. An interrupted format
does not advertise a usable new filesystem; formatting is not an atomic way
to preserve an existing volume.

## Transactions and recovery

A shared volume lock serializes mutations. Writes stage complete 4 KiB home
page images in a bounded overlay; reads within the transaction see those
images. The home device and clean block cache remain unchanged until commit.
The journal records file data together with allocation bitmaps, group counts,
inodes, directory entries, xattrs and the primary superblock.

Each commit follows this order:

1. Write payload images and descriptors; flush the device.
2. Write the checksummed commit marker; flush the device.
3. Write all home images; flush the device.
4. Update resident clean cache pages, clear the marker and flush the device.

Mount discovers the journal from the fixed device tail and replays it before
reading home metadata, including the primary superblock. Configuration,
descriptor bank, marker and every payload have CRC32C checksums. Recovery
validates the whole transaction, destination bounds and duplicate destinations
before writing any home page. Replay is idempotent if power fails again.
A valid marker with damaged payload or descriptors causes mount to fail.
A dirty journal requires a writable backing device for recovery.

A torn marker publication precedes every home write; a torn marker clearing
follows the durable home barrier. Under the ordering above, an invalid marker
therefore leaves a consistent home image and can be cleared before journal
reuse. CRC32C detects accidental damage; it is not authentication or protection
against arbitrary media corruption, forged metadata or a malicious device.

## Observable behavior

Namespace operations commit before publishing their live VFS changes.
Create, hardlink, unlink, chmod, rename, replacement and rename exchange keep
their directory entries, link counts, inode ownership and allocation metadata
together. Cross-directory moves include parent link counts and `..` changes.
A successful ordinary write returns after its data and metadata commit.

Unlinked open files remain allocated zero-link inodes until their last owner
releases them. After a crash, mount reclaims these persistent orphans, including
removed directories and replaced files. Cleanup commits bounded batches only
after detaching a pointer, releasing its allocation bit and updating the inode
sector count together. A large file can therefore finish cleanup across
several transactions and repeated crashes.

Shrinking a linked file first commits its new EOF, zeroed tail and a persistent
pending-truncate marker in the inode's VJFS-only `oss1` field. Live shared cache
pages publish that EOF immediately. Bounded cleanup then removes blocks beyond
EOF and clears the marker. Recovery, future writes and growth finish pending
cleanup before reusing those blocks. Extension exposes zeros rather than old
truncated bytes. A cleanup error can leave the smaller EOF committed even when
`ftruncate` reports failure.

`msync(MS_SYNC)`, `fsync`, `syncfs` and global sync collect shared mapping dirty
evidence and commit snapshots through the same journal. Private COW changes
remain private. Failed mapped writes retain dirty evidence for retry. These
calls do not promise one atomic transaction across all pages or across multiple
files; a concurrent writer can dirty a page again after a snapshot.

A device write or flush failure during commit poisons the volume. Subsequent
data reads, writes, mapping admission and sync report an error; the journal
cannot be reused until mount-time recovery. Existing mapped pages already in
RAM may still be read. Allocation, capacity or staging failures before commit
abort the overlay without poisoning a healthy volume. Failed final orphan
cleanup releases the dead Resource's RAM while its allocated inode retains
persistent ownership for recovery.

## Bounds and device requirements

The journal holds at most 512 home pages (2 MiB of payload) per transaction.
Ordinary journaled writes cap one call at 1 MiB and may return a short count;
callers must loop. An operation exceeding the transaction capacity returns an
error and cannot commit a partial staged mutation. Large teardown and linked
truncation use recoverable batches. The formatter uses 4 KiB blocks and
128-byte inodes; existing raw EXT2 support remains separate.

Crash guarantees require exact completed writes and a working device flush
that makes preceding writes durable and orders later writes behind them.
Sector writes may tear within the current phase, but cannot cross a completed
flush. A controller that ignores flush, loses previously acknowledged durable
writes or corrupts unrelated sectors violates this model. The implementation
does not add redundancy, snapshots, full-disk encryption, online resize or a
general filesystem repair tool. Installation/update consistency above the
individual filesystem transaction remains a separate roadmap item.

The format's journal version is 1, little endian. Tail pages contain:

| Relative offset | Contents |
| --- | --- |
| 0 | Configuration: version, geometry, home volume bytes, UUID, CRC32C |
| 4096 | Commit marker: sequence, count, descriptor CRC32C, marker CRC32C |
| 8192 | 8192-byte descriptor bank: home offsets and payload CRC32C |
| 16384 | Up to 512 complete 4096-byte home images |

The production source is [journal.v](../kernel/fs/journal/journal.v) with the
[filesystem integration](../kernel/fs/ext2/journal.v).
See the [acceptance tests](../tests/fs-journal/README.md) for the crash model,
native controller coverage and inspection export procedure.
