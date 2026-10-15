# Regular-file version backups

`vinix-volume` can save full and incremental versions of a regular file, verify
their complete content and restore an earlier version into a new file:

```sh
vinix-volume backup-file notes.txt notes-full.vbackup
vinix-volume backup-file-delta notes-full.vbackup notes.txt notes-next.vbackup
vinix-volume restore-file notes-full.vbackup notes-original.txt
vinix-volume restore-file-delta notes-full.vbackup notes-next.vbackup notes-next.txt
```

Each archive represents one file of at most 64 MiB. A full archive stores all
64 KiB chunks, including the exact final partial chunk. A delta compares against
a verified full archive and stores only differing chunks. Empty files, growth,
shrinkage and metadata-only changes are supported. Deltas require their original
full base; the complete base archive SHA-256 binds its content and metadata.
Deltas cannot serve as bases; take a new full backup to start another generation.
Sparse input is read as bytes, and restored files are ordinary files.

The archive records content, permission bits `0777`, UID, GID and modification
time. Restoration sets mode and ownership and requests the recorded modification
time before publishing the destination. The target filesystem may round that
time to its supported precision. Restoration fails if the caller cannot restore
the saved ownership or mode/time. Special mode bits are refused. Timestamp
precision is limited by the source and target
filesystems. ACLs, xattrs, access/birth times, hardlink relationships, sparse
allocation and directory trees are outside this first file-version primitive.

## Consistency and publication

Quiesce all source writers, including shared writable mappings, during capture.
Keep archives and their base unchanged while creating a delta or restoring.
The original descriptors and their parent directories remain pinned until the
command finishes. Reads check regular-file type, size, ownership/mode and
modification/change timestamps again after scanning. These checks detect
ordinary mutations; they do not provide an atomic filesystem snapshot or a
cross-file consistency boundary, especially on filesystems with coarse times.

Use trusted destination directories. A nonblocking directory writer lock
coordinates cooperating publishers. Output is built in an exclusive temporary
file in that directory. Full body and content hashes are verified before
publication; restoration reconstructs and hashes the complete result, including
chunks read from the base. Archive files are set to `0600`; restored files receive
the recorded metadata. File contents/metadata are flushed, then `linkat` publishes
without replacing any existing name, including a symlink or input alias. The
temporary name is removed and the directory is flushed before success.

Exit 0 means complete validation, publication and output reporting succeeded.
Input, corruption, base mismatch, ownership, I/O and publication failures return
1; syntax errors return 2. A failed directory barrier, temporary unlink or stdout
operation can leave a complete destination already published. Inspect it before
retrying with a new name. Existing destinations are preserved. Cleanup attempts
to remove an unpublished temporary on failure; interruption or persistent unlink
failure can leave a private temporary, which is never treated as a completed
archive. Crash durability requires a crash-safe filesystem and working
file/directory flushes.

SHA-256 detects accidental damage and binds the chosen base. Archives are
unencrypted and unauthenticated; keep them protected and trust their provenance.
This implements file-version capture/restore and a changed-chunk backup
primitive. Filesystem-wide snapshots, reflinks and arbitrary incremental chains
remain roadmap work.

## Archive version 1

`VINIXBK1` is a canonical little-endian format. Its 256-byte header contains:

| Offset | Field |
| --- | --- |
| 0 | Eight-byte magic `VINIXBK1` |
| 8 | Version `u32=1`, kind `u32` (0 full, 1 delta) |
| 16 | Chunk size `u32=65536`, four reserved zero bytes |
| 24 | File size `u64` |
| 32 | Mode, UID and GID (`u32` each), four reserved zero bytes |
| 48 | Signed modification seconds `i64`, nanoseconds `u64` |
| 64 | Complete reconstructed content SHA-256 (32 bytes) |
| 96 | Complete full-base archive SHA-256, or 32 zero bytes for full |
| 128 | Stored record count `u64` |
| 136 | Complete record-stream SHA-256 (32 bytes) |
| 168 | 56 reserved zero bytes |
| 224 | SHA-256 of header bytes 0..223 (32 bytes) |

Each record has a chunk index `u64`, payload length `u32`, four reserved zero
bytes, then exactly that many payload bytes. Indices strictly increase. Full
archives include every chunk; delta omissions must be covered by same-length
chunks in the full base. All recorded lengths must match the target file's
chunk geometry. Empty streams use the SHA-256 of empty input. Partial records,
nonzero reserved bytes, excessive counts/lengths and trailing bytes refuse.

See [qualification](../tests/storage-volumes/file-backup.md).
