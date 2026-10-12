# Atomic multi-pool allocation qualification

Run the native V controller in [README.md](README.md) with `--host` and both
architectures. `pool-allocate-set-batch` and `pool-preview-set-batch` plan
1–64 ordered `POOL SLOT LENGTH MODE` requests in one saved-state transaction.

An independent **4096-case** cell oracle covers all four-cell fragmentation
patterns in two pools, opposite member priorities, both request orders,
one/two-cell lengths and mixed MBR/GPT/512/4096-sector layouts. Expected full
sets and placement results are built without the production planner. Existing
keys/rows/modes, pool bounds/priority, unrelated state and inactive sentinels
stay exact; later exhaustion leaves every caller/result field unchanged.

Interleaved requests to one pool consume earlier placements. Matching rows
retain offsets after earlier space is freed; mixed keep/new requests apply
saved sector filtering. Wrong pools, lengths or modes reject a retry. Invalid
counts/pools/global slots/version/offset/mode/length, missing pools and duplicate
slots across pools fail atomically. Complete CLI syntax is checked before I/O.
Missing/corrupt/symlink/nonregular sources never produce a candidate file.

Maximum tests cover **64 pools/disks/requests / 259 CLI arguments**, near-u64
geometry, 64 mappings/regions and the **8768-byte V2** limit. Previews preserve
old bytes, complete publication matches an independently constructed set and
all-keep retries preserve exact bytes. Separate writer-lock tests require
preview availability and publication exclusion.

Shared publisher fault tests qualify changed/all-keep cross-pool batches under
short/EINTR writes and write/file-fsync/close/rename/directory-fsync failures.
Before rename old bytes remain; afterward only the complete candidate appears.
Successful retries replace and complete both flushes. Preview never enters the
publisher. Both commands detect buffered stdout failure. Host suites use
ASan/UBSan; complete production/guest C is audited for heap/V-runtime dependence
and strictly cross compiled for both targets.

First-boot guests reject later exhaustion, absent pools and duplicate global
slots, preview complete placements under writer contention, publish/retry in
reverse order and check a later live conflict prevents either new mapping.
Explicit replay verifies primary writable and secondary read-only data while
original descriptors/generations survive. Cleanup restores exact baseline
bytes. `PLAN MULTI POOL BATCH PASSED:` is required.

Each target runs **200 warmup + 200 measured 39-command cycles / 15600 utility
processes**, retaining every earlier storage assertion. The new workload adds
temporary pool eligibility for an existing mapping, 400 multi-pool previews
and publications with 800 ordered keep actions each, then removes that
temporary eligibility. Two more commands preview/publish complete equal-size
multi-pool growth within that temporary membership interval. Slab classes and
large pages must stay flat or decrease;
each boot retains the 1800-second limit.

The previous six-boot growth/contraction fixture remains enabled. After all
sixth-boot assertions, it preserves the actual **536-byte** contracted bundle,
adds two separate pool memberships and atomically allocates two rows while
retaining all seven original mappings. It saves the actual **680-byte V2**
planned configuration. `PLAN MULTI POOL BATCH SAVED:` is required. Seventh-boot
production init restores all nine mappings before the test starts; original
and newly allocated data, modes and independent pool priorities persist.
Reverse-order exact retries preserve bundle bytes and live generations.
`PLAN MULTI POOL BATCH BOOT PRESERVED` is required. Independent artifacts check
actual old/new bundles, nested/outer CRCs, every original row/member, appended
placements and memberships, complete retry reports and raw data. Every earlier
artifact assertion remains enabled.

This configures contiguous desired mappings; live application, spanning/RAID,
data relocation and filesystem resizing remain separate operations.
