# Atomic pool allocation batch qualification

Run the native controller in [README.md](README.md) with `--host`, then both
guest architectures. Production kernel code and the saved format are unchanged.

The host batch suite covers request/member ordering, mixed 512/4096-byte
sectors, explicit writable/read-only modes, placement alignment, no backtracking,
cross-disk placement, matching-row retries and mixed keep/new requests. Removing
earlier rows must not relocate a retained mapping. A matching manually added
row within the selected region is eligible; a wrong length/mode, missing member
or outside/straddling extent is not. Bounds cover zero/65 requests, duplicate
and out-of-range slots, unknown versions/flags, nonzero request offsets,
unaligned/overflow lengths, absent pools and invalid files/CLI triples.

An independent cell oracle checks all 256 two-disk fragmentation patterns
against all 16 pairs of request lengths: **4096 batch attempts**. It fills cells
for each successful request before considering the next, scanning saved member
order and aligned starts without using the production gap enumerator. Complete
success must match both placements and modes and preserve every original row,
identity and pool record. Any failure must preserve the entire original set and
caller output, including when a first placement would have fit. A maximum batch
fills all 64 slots across 64 disks/regions near the u64 address limit, roundtrips
the 8768-byte version-2 bundle and retries with every row retained.

Real-file tests prove previews leave bytes unchanged and create no temporary;
publication creates both mappings together and retries preserve exact bytes.
Corrupt, missing, final-symlink and nonregular sources fail. The shared publisher
fixture tests new allocations and complete matching-row retries through EINTR,
three-byte short writes and every write, file-fsync, close, rename and directory-
fsync failure. Before rename the original file remains exact; after rename the
complete new file is readable. No temporary survives. A retry must write,
rename and perform both fsyncs, including after failed directory fsync.
Preview must never enter that boundary, even when a publisher fault is armed.
Buffered stdout failure must return failure; publishing leaves all rows saved,
while preview leaves the original bytes. These run with ASan/UBSan.

Guest functional tests start with the actual configured two-disk bundle.
A feasible first request followed by an impossible request, or a repeated slot,
must leave exact original bytes and emit no placement rows. Successful preview
reports slot 14 read-only on the first disk and slot 15 writable on the second,
without creating a mapping or changing the file. Publication remains offline.
An unlisted live conflict on the later disk must reject complete-set checking
and replay before creating either mapping. Removing it permits explicit replay.
Both disk identities and modes must match the preview. Repeating the batch must
report both saved placements as `keep`, preserve exact bytes, and retain both
live generations and a readable held descriptor. A mode mismatch fails without
changing the bundle. Cleanup restores exact baseline bytes.

Each of 200 warmup and 200 measured cycles now executes 41 utility processes:
scrub-data, verify-data, save-set, plan-preview-grow-batch and plan-grow-batch, plan-preview-capacity-batch and plan-capacity-batch,
plan-preview-contract-capacity-batch and plan-contract-capacity-batch,
pool-preview-add-batch and pool-add-batch,
pool-preview-order and pool-order,
pool-preview-expand-batch and pool-expand-batch,
pool-space, two-request pool-preview-batch and pool-allocate-batch,
pool-preview-grow-batch and pool-grow-batch,
plan-preview-add-batch and plan-add-batch, pool-preview-contract-batch and pool-contract-batch, pool-preview-resize-batch and pool-resize-batch,
check-bundle, plan-preview-remove-batch and plan-remove-batch,
plan-preview-enroll-batch and plan-enroll-batch, plan-preview-forget-batch and plan-forget-batch, restore-bundle and
boot-restore. This is **16400 processes**, 400 allocation previews/publications,
800 scratch placements, 400 growth previews/publications, 800 scratch growths,
800 member additions, 400 expansion previews/publications, 400 capacity batch
previews/publications and 400 pool queries. Neither scratch mapping becomes live.
Four additional commands temporarily add pool-4 eligibility for an existing
mapping, preview/publish a two-pool keep batch, then remove that membership.
Two more commands preview/publish complete equal-size multi-pool growth before
that temporary membership is removed.
Every slab class and the large-
allocation page total must stay flat or decrease. The existing 1800-second
per-boot limit is unchanged.

The four-boot fixture retains reordered discovery and explicit physical-capacity
adoption. After growing its writable tail view, it previews and publishes one
matching writable tail row plus a new read-only neighbor in one batch. Raw data
is flushed before publication. The fourth boot must restore all seven mappings
through production init, with exact disk identities, old/tail data, the new
read-only pages and the three ordered pool records. The neighbor grows through
a subsequent mixed keep/grow batch; see [growth batch qualification](pool-grow-batch.md).
Original pool capacity stays unchanged; the expanded tail pool has exactly
8372224 eligible bytes remaining.
`PLAN POOL BATCH PASSED:` and `PLAN POOL BATCH BOOT PRESERVED` are required.

Both architectures' generated production/guest C must contain no heap or V
runtime dependencies. Real guests cover VirtIO/ARM64 and AHCI/x86 with MBR and
512-byte sectors; mixed sectors and maximum bounds have host coverage. Batch
publication is atomic desired configuration, while live replay retains the
existing preflight and partial-application rules. Spanning, RAID, encryption,
concurrent live administration and filesystem resizing remain outside this increment.
Saved-state writer coordination is qualified separately in [plan-lock.md](plan-lock.md).
