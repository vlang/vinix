# Atomic explicit mapping addition qualification

Run the native V controller in [README.md](README.md) with `--host` and both
architectures. `plan-add-batch` and `plan-preview-add-batch` select enrolled
MBR/GPT identities and explicitly place 1–64 desired extents with `rw`/`ro` modes.

Independent append/keep oracles check **1024** existing/requested subsets under
two request orders and two mixed-sector identity layouts. Expected rows, slot
ownership, action masks and current disk indices are constructed independently.
New rows append within each disk; matching rows, pending desired state, inactive
sentinels, disk order and pool bounds/alignment/priority remain exact. Later
wrong/absent identities, conflicting row fields/modes, repeated global slots,
invalid versions/counts, unaligned/overflowing/overlapping extents and ambiguous
existing identities preserve every caller and output field. Explicit sector-
aligned mappings outside pool windows require no pool alignment. Exact identity
retries retain rows after another disk is forgotten and pool indices compact.

Maximum tests exercise **64 requests / 323 CLI arguments**, mixed MBR/GPT/sector
layouts near u64 bounds, 64 disks/mappings/regions and the **8768-byte V2** limit.
Previews preserve original bytes; decoded publication matches an independently
constructed set, and exact retries preserve file bytes. Every syntax token is
checked before I/O, including later identity/mode/numeric failures, overflows,
invalid counts and zero lengths. Missing/corrupt/symlink/nonregular sources fail
without publication temporaries. Publisher faults cover changed/all-keep batches
under short/EINTR writes and write/file-fsync/close/rename/directory-fsync errors.
Before rename old bytes stay; afterward only the complete candidate may appear.
Every retry writes, renames and completes both fsyncs. Previews never publish.
Both commands detect buffered stdout failure. Writer exclusion preserves preview
availability. Host suites use ASan/UBSan; production/guest C must pass no-heap/
no-V-runtime audits and strict cross compilation on both architectures.

First-boot guests verify later wrong-disk/unaligned failures, mixed add/keep
preview under a held directory writer lock, exact publication retries and
unchanged live views before application. A conflicting later live disk blocks
creation of the earlier requested view. After explicit replay, read-only modes,
raw extent data and original generations remain correct. Held descriptors survive
desired omission; cleanup restores exact baseline bytes and removes scratch
live views explicitly. `PLAN ADDITION BATCH PASSED:` is required.

Each architecture runs 200 warmup and 200 measured **41-command cycles / 16400
utility processes**, including 400 complete explicit addition previews and
publications with 800 exact keep actions each. Existing allocation/growth rows
are retried by identity before live preflight and scratch desired removal.
All previous allocation, growth, expansion, capacity, membership, priority,
removal, enrollment, forgetting, query and health checks remain enabled. Slab
classes and large pages must stay flat or decrease; the per-boot limit remains
1800 seconds.

Third-boot preparation removes seven desired rows while preserving live views
and pool metadata, then re-adds them as one interleaved cross-disk identity batch.
Original per-disk row order and the exact **536-byte** baseline must recover;
live generations remain unchanged. `PLAN ADDITION BATCH SAVED:` is required.
Fourth-boot production init restores the actual saved bundle, checks all existing
data/modes/priority and retries all seven additions as keep with stable disk
identities. Exact file bytes must remain. `PLAN ADDITION BATCH BOOT PRESERVED`
is required. Independent artifact checks retain actual V2 bundles, CRCs, every
row/key, imported snapshots, action reports and durable data samples.

These commands edit offline desired mappings; physical allocation, live
creation/removal, filesystem resizing and pool allocation remain separate.
