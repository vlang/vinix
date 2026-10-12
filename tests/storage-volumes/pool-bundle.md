# Persistent allocation-pool qualification

Run the native V controller commands in [README.md](README.md). Host checks
use ASan/UBSan; both architectures' complete production utility and guest C
are audited for implicit heap allocation and V runtime dependencies.

The host suite covers:

- Pool/disk ID bounds, absent members, duplicate pairs, overlapping regions
  across pools, sector/range/alignment errors, ambiguous persistent identifiers,
  the 64-region bound and unchanged state on failure.
- Stable membership order, removal retaining desired mappings, refusal to forget
  a member disk, and compaction of later disk indices when an empty disk is
  forgotten. Imported version-2 bundle indices rebase after existing plans.
- Aggregate aligned gap capacity and first fit against an independent sector
  oracle: all 256 two-disk fragmentation patterns at eight request lengths,
  including read-only occupied rows, clipped regions and different alignments.
  A 4096-byte-sector member is skipped for a 512-byte request.
- Globally owned slots, zero/invalid lengths and modes, missing pools, no single
  fitting gap, unchanged failure outputs and readonly/writable result modes.
- Totals beyond u64, including 64 large members totaling
  `1180591620717411237888` bytes; decimal formatting through the full u128 limit.
- Exact pool-free version-1 bytes, version-2 roundtrip, every truncated prefix
  and bit corruption, checksummed malformed headers/records/reserved fields,
  the exact 8768-byte maximum with output canaries, and return to version 1
  after the final region is removed.
- Bounded regular-file inputs, final symlink/nonregular/corrupt/missing input
  rejection, unchanged query bytes and strict command argument parsing.
- Add/remove/allocate through the shared syscall-boundary publisher fixture:
  EINTR and three-byte short writes succeed; write, file-fsync, close and rename
  failures preserve the old file; directory-fsync failure returns an error with
  the complete new metadata and mappings visible. Descriptors and temporary
  files drain on every path.

The first guest boot requires `PLAN POOLS PASSED:`. Two eligible regions have
4096 and 12288 bytes free. A request of 16384 bytes must fail despite sufficient
aggregate capacity. An 8192-byte readonly request must skip the first member
and select the second physical disk; a subsequent 4096-byte request follows
the saved first member. Neither planning command implicitly creates a view.

An unlisted live conflict on the selected later disk must reject all preview
actions and replay without disturbing previous generations. Removing it allows
explicit creation with the selected identity, offset and mode and unchanged
physical data. Removing pool membership preserves the allocated desired row,
live generation and held descriptor's two data pages. Removing desired rows
then all members restores the exact original version-1 file; re-adding the
regions restores the exact configured version-2 file.

Each of 200 warmup and 200 measured cycles launches thirty-seven utility processes:
save-set, plan-preview-grow-batch and plan-grow-batch, plan-preview-capacity-batch and plan-capacity-batch,
plan-preview-contract-capacity-batch and plan-contract-capacity-batch,
pool-preview-add-batch and pool-add-batch,
pool-preview-order and pool-order,
pool-preview-expand-batch, pool-expand-batch, pool-space,
pool-preview-batch, pool-allocate-batch,
pool-preview-grow-batch, pool-grow-batch,
plan-preview-add-batch, plan-add-batch, pool-preview-contract-batch, pool-contract-batch, pool-preview-resize-batch, pool-resize-batch,
check-bundle, plan-preview-remove-batch and plan-remove-batch,
plan-preview-enroll-batch, plan-enroll-batch, plan-preview-forget-batch, plan-forget-batch, restore-bundle
and boot-restore. This is 14800 processes, 800 member additions, 400 pool queries
and 800 scratch placements/growths. No scratch mapping is created.
Four additional commands temporarily add pool-4 eligibility for an existing
mapping, preview/publish a two-pool keep batch, then remove that membership.
Every slab class and the large-page total must stay flat or decrease.

The actual guest-published pool-bearing bundle survives the reordered second
boot through production init. After the host enlarges only its disposable raw
disk, stale geometry must reject replay on the third boot. Explicit physical
capacity adoption and tail allocation/growth preserve both pool records. The
fourth boot must restore all seven mappings and report the original pool regions
and exact aggregate capacity, alongside durable old/tail data and modes.
`PLAN POOL BOOT PRESERVED` is required on both successful reboot phases.
The tail mapping now uses an additional pool whose region is expanded after
physical adoption and whose desired mapping grows through `pool-grow`;
[growth qualification](pool-growth.md) covers those commands and persistence.
Tail expansion now uses a previewed/retried batch; see
[expansion batch qualification](pool-expand-batch.md).
A mixed keep/new tail batch adds a durable read-only neighbor; see
[batch qualification](pool-batch.md). A growth batch then keeps the writable
tail and grows its read-only neighbor; see [growth batch qualification](pool-grow-batch.md).

Real guest coverage uses 512-byte MBR disks on VirtIO (ARM64) and AHCI (x86).
Mixed sectors, ambiguous identities, maximum bounds and publication faults use
host models. Pools describe saved allocation eligibility; live protection and
complete preflight remain separate. Spanning volumes, RAID and encryption are
outside this increment.
