# Offline mapping configuration qualification

Run the maintained V controller using fresh work directories:

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --host --work /tmp/vinix-plan-edit-host
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/arm/kernel/bin/vinix \
  --work /tmp/vinix-plan-edit-arm
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/x86/kernel/bin/vinix \
  --work /tmp/vinix-plan-edit-x86
```

`plan_edit_test.v` runs under ASan/UBSan alongside existing plan/bundle/check
entries. It adds writable/read-only entries to enrolled disks, including an
empty disk; removes middle and last rows; verifies order, identities, modes
and global slot ownership; reuses a freed slot on another disk; and roundtrips
an entirely empty two-disk bundle. A full 64-disk/64-slot set remains encodable
at 6208 bytes after remove/reuse. A full per-disk array refuses an extra row.
Invalid disk/slot/version/mode, duplicate global slots, overlap, zero length,
unaligned geometry, disk-end and integer overflow leave every field unchanged.
Real file tests require decoded checksums, unchanged previous contents on
failed edits, no final-symlink replacement, corrupt-file refusal and no leftover
temporary files. CLI syntax failures happen before file access.

The shared publisher fixture invokes both add/remove commands across EINTR,
short writes, write/file-flush/close/rename and directory-flush faults. Failures
before rename preserve the old file. Directory-flush failure returns nonzero
with the new complete checksummed file already visible. Every path closes the
publisher descriptors and removes unpublished temporaries. Both complete
architecture utilities pass the generated allocation/runtime audit; existing
preflight/application and init sanitizer regressions remain enabled.

The guest adds two desired mappings without live creation, captures the
verified offline listing and a create/create/keep preview, and checks invalid
additions preserve the saved bundle. Later-disk slot conflicts and unlisted
extent conflicts prevent any creation prefix. Explicit replay then creates
read-only/writable views while preserving preexisting raw data. A live read-only
descriptor remains usable after removing its desired entry and replaying the
remaining set. Reenrolling it preserves generations. `PLAN EDIT PASSED:` is
required before acceptance.

Each repeated cycle saves, plans and verifies unchanged capacity, previews and
publishes scratch allocation/growth batches, checks and previews/removes both scratch
entries, previews/enrolls two empty offline disks and forgets both,
explicitly restores and runs boot replay.
The scratch mappings must never become live. After 200 warmup and 200 measured cycles,
all slab classes and large allocation pages must stay flat. The 1800-second
boot allowance covers 16400 utility processes on x86 TCG, including physical
capacity verification, pool membership/query and allocation/growth/expansion batch
previews/publications. A reordered
second boot uses production init and the actual disk-resident five-mapping bundle,
requiring both new mappings, their data and read-only mode alongside previously
grown extents. Replay remains idempotent.

These commands edit saved linear configuration only. Empty enrolled disks
remain participants; removal omits replay without deleting a live view or
erasing/releasing its extent. Live checks, runtime protections and serialized
administration remain necessary. See
[the editing contract](../../docs/storage-volumes.md#offline-mapping-configuration).
