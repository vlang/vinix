# Atomic explicit mapping growth qualification

Run the native V controller in [README.md](README.md) with `--host` and both
architectures. `plan-grow-batch` and `plan-preview-grow-batch` grow 1–64 existing
desired mappings by enrolled MBR/GPT identity, independently of pool membership.

Independent length/action oracles check **1024** existing-growth/requested subsets
under two request orders and two mixed-sector identity layouts. Expected rows,
old/new lengths, current disk indices and grow/keep actions are constructed
without the production planner. Only requested lengths change; offsets, modes,
global slots, row/disk order, inactive sentinels and pool bounds/alignment/priority
remain exact. Later wrong/absent identities or slots, duplicate/invalid slots,
invalid counts, zero lengths, shrink, unaligned/overflowing/overlapping extents
and ambiguous saved identities preserve every caller/results field. Sector-
aligned growth outside pool windows does not require pool alignment. Equal-size
identity retries still target the right disks after unrelated compaction.

Maximum tests exercise **64 requests / 195 CLI arguments**, mixed MBR/GPT/sector
layouts near u64 bounds, 64 disks/mappings/regions and the **8768-byte V2** limit.
Read-only preview preserves bytes; decoded publication matches an independent
expected set. Equal-size retries preserve exact bytes; a later shrink does not
publish a prefix. Every token is parsed before I/O, including later bad identity,
slot/length syntax, numeric overflow, zero length and invalid counts/remainders.
Missing/corrupt/symlink/nonregular bundles fail without publisher temporaries.

Publisher faults cover changed/all-keep batches under short/EINTR writes and
write/file-fsync/close/rename/directory-fsync failures. Old bytes stay before
rename; afterward only the complete new set appears. All successful retries
write, rename and complete both fsyncs. Previews never publish. Both commands
detect buffered stdout failure. Writer exclusion preserves preview availability.
Host suites use ASan/UBSan; production/guest C must pass no-heap/no-V-runtime
audits and strict cross compilation on both architectures.

First-boot guests verify later wrong-disk/unaligned/duplicate failures, complete
mixed grow/keep preview under a directory writer lock and offline publication.
A later unlisted live extension conflict blocks the first requested growth.
After explicit replay, both live generations and held descriptors survive;
read-only mode and raw extension bytes remain correct. Equal-size retries retain
exact bytes. Desired omission keeps unlisted grown views until explicit removal;
cleanup recovers the baseline and preserves original generations/data.
`PLAN EXPLICIT GROWTH BATCH PASSED:` is required.

Each architecture runs 200 warmup and 200 measured **39-command cycles / 15600
utility processes**, including 400 complete explicit growth previews/publications
with 800 ordered keep actions each. The former single unchanged desired growth
becomes a two-disk identity preview and publication. Existing allocation, growth,
expansion, capacity, membership, priority, removal, enrollment, forgetting,
addition, query, health and replay checks remain enabled. Slab classes and large
pages must stay flat or decrease; the per-boot limit remains 1800 seconds.

Third-boot preparation rebuilds the same seven-row configuration with two smaller
desired lengths and preserved live views. One interleaved cross-disk growth batch
must recover the exact **536-byte** baseline, row/pool order and live generations.
`PLAN EXPLICIT GROWTH BATCH SAVED:` is required. Fourth-boot production init
restores actual saved geometry/data/modes/priority and both growth requests retry
as keep with exact bytes. `PLAN EXPLICIT GROWTH BATCH BOOT PRESERVED` is required.
Independent artifact checks retain checksummed V2 bundles, every row/key, imported
snapshots, action reports and durable data samples, including both scratch
extension patterns after removal/reboot.

The commands edit offline desired capacity; live application, physical capacity
adoption, relocation, pool eligibility and filesystem resizing remain separate.
