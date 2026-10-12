# Atomic cross-pool window resizing qualification

Run the native V controller in [README.md](README.md) with `--host` and both
architectures. `pool-resize-batch` and `pool-preview-resize-batch` resize both
bounds of 1–64 existing pool members selected by identity/pool pairs.

Independent bounds/action/priority oracles check **1024** existing/requested
transfer subsets under two request orders and mixed MBR/GPT/sector layouts.
Adjacent pools can transfer unused bytes in either order, including receiver
expansion before donor contraction. Expected windows and results are built
without the production planner. A further **2592** cell-oracle cases cover both
outer bounds, nine shared boundaries, all four-cell occupation patterns and
both request orders. Every occupied cell retains its original pool eligibility.
All mappings, modes, pending lengths, slots, disk/region order, interleaved other
pools, alignment, allocation priority and inactive sentinels stay exact.

Later missing/wrong/ambiguous identities or members, duplicate normalized
identity/pool pairs, invalid pools/counts/keys, zero or empty bounds, unaligned
or overflowing bounds, released occupied heads/tails and final overlaps leave
every caller and result field unchanged. Mapping intersections crossing either
original boundary are clipped correctly. Bounds need only match saved sector
geometry; request geometry is ignored and identity retries follow compaction.

Maximum tests exercise **64 requests / 259 CLI arguments**, 64 disks/mappings/
regions near u64 bounds and the **8768-byte V2** limit. Previews preserve old
bytes; decoded publication equals independently constructed bounds with
unchanged rows. Equal-bound retries preserve exact bytes. Every token and
count/remainder is checked before I/O. Missing/corrupt/symlink/nonregular inputs
fail without publisher temporaries.

Publisher faults cover mixed cross-pool edits and all-keep retries under short/
EINTR writes and write/file-fsync/close/rename/directory-fsync failures. Old bytes
remain before rename; afterward only the complete candidate appears. Successful
retries complete both fsyncs and replacement. Previews never publish and remain
available under a writer lock. Both commands detect buffered stdout failure.
Host suites use ASan/UBSan. Complete production/guest C must pass no-heap/
no-V-runtime audits and strict cross compilation on both architectures.

First-boot guests reject later occupied heads/tails, missing/duplicate members
and final overlaps, preview a complete transfer under a writer lock, publish
and retry in reverse order, then allocate into newly admitted receiver capacity.
Held read-only/writable views, generations and F2/F3 data stay intact. Removing
a desired head permits releasing it while its unlisted live descriptor remains
readable. Cleanup restores exact baseline bytes and original E7 data/generation.
`PLAN POOL RESIZE BATCH PASSED:` is required.

Each architecture runs 200 warmup and 200 measured **39-command cycles / 15600
utility processes**, including 400 complete resize previews/publications with
800 ordered keep actions each. Every earlier storage assertion remains enabled.
Slab classes and large pages must stay flat or decrease; the per-boot limit
remains 1800 seconds.

Third-boot preparation transfers an unused boundary between adjacent pool-5/
pool-6 windows on the secondary identity. It saves the actual **696-byte V2**
configuration with original pool-5 priority (disk 1 then 0) and new pool-6
priority (disk 0 then 1). Live generations remain unchanged.
`PLAN POOL RESIZE BATCH SAVED:` is required. Fourth-boot production init restores
it; both pool queries and equal-bound identity retries retain capacity, bounds,
priority and exact bytes. The fixture saves actual planned/boot resized bundles
before explicitly reversing only the unused transfer and removing the new
memberships, returning the prior **616-byte** contraction state and then the
**536-byte** baseline for earlier independent assertions.
`PLAN POOL RESIZE BATCH BOOT PRESERVED` is required. Artifact checks verify all
actual bundles, CRCs, ordered windows, retry reports and durable data samples.

Resizing edits saved eligibility. Physical disk/filesystem size, data relocation,
live detach and encryption remain separate operations.
