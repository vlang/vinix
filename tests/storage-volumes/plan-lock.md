# Saved-plan writer-lock qualification

Run the native V controller in [README.md](README.md) with `--host`, then both
guest architectures. Production kernel code and saved formats are unchanged.

The host suite holds an exclusive directory lock and requires every saved-state
writer to fail without changing bytes or creating files: mapping add/remove (including removal batches) and
growth, disk enrollment/removal (including enrollment batches), physical-capacity adoption, pool membership,
allocation, expansion/growth, batches, bounded extent allocation, direct plan
publication and live snapshots. Batch previews, pool queries and extent queries
must succeed while that lock is held. Directory aliases share exclusion; a
destination in another directory succeeds independently. Source and directory
descriptors must have `CLOEXEC`.

A retained editor publishes a replacement while an independent child retries
the same bundle. Closing the publisher's duplicate must leave the editor's lock
held. After release, a fresh retry must preserve the first edit alongside its
own change. Renaming the locked directory and replacing its original path must
publish only in the pinned original directory. A pipe barrier proves a child
owns its lock before contention is tested; `SIGKILL` and reaping must release
it without stale lock-file cleanup.

Failure tests close partial acquisition state after missing or final-symlink
sources and reject publication through read-only handles. Reused state must
reset its filename and descriptors; invalid basenames and path bounds fail.
The shared publisher fault suite reopens the directory inode independently at
rename and directory fsync, proving exclusion remains active even when those
operations fail. Existing interrupted/short writes and write, file-fsync, close,
rename and directory-fsync faults retain their before/after publication rules
and cleanup. Retries, including unchanged desired state, complete both flushes.
Host tests run under ASan/UBSan.

The guest fixture uses a parent-owned `CLOEXEC` directory lock while separately
executed packaged utilities reopen the inode. Writer families must fail,
read-only queries/previews remain usable, directory aliases conflict and a
different directory accepts publication. Exact bundle bytes and live mappings
remain unchanged. After release, sequential edits retain both changes, and
cleanup restores exact baseline bytes. A separate pipe-synchronized child owns
a lock until killed; the next writer succeeds after reaping.
`PLAN LOCK PASSED:` is required before the first boot is accepted.

Each architecture also runs the existing 200 warmup and 200 measured cycles:
**16000 utility processes**, with every saved mutation acquiring/releasing its
lock. All slab classes and large-allocation page totals must stay flat or
decrease. The unchanged four-boot fixture verifies reordered discovery,
physical-capacity adoption and seven durable mappings with old/tail bytes,
read-only modes and three pool regions. Both production and guest generated C
must contain no heap or V runtime dependencies.

These tests qualify cooperating writers on one directory inode, including
VirtIO/ARM64 and AHCI/x86 guests on ext2. They do not coordinate external/older
writers or separately saved configurations for the same extents. A preview
does not reserve saved state, and live administration still requires
serialization. RAID, spanning, encryption and filesystem resizing remain open.
