# Atomic multi-pool mapping growth qualification

Run the native V controller in [README.md](README.md) with `--host` and both
guest architectures. `pool-grow-set-batch` and `pool-preview-grow-set-batch`
plan 1–64 ordered `POOL SLOT LENGTH_BYTES` requests in one saved-state edit.

An independent **16384-case** extension-cell oracle covers all fragmentation
masks in two pools, both request orders, one-to-four-cell lengths and mixed
MBR/GPT/512/4096-sector layouts. Each pool prefers an empty alternate disk;
growth must still use the existing mapping's own member. Expected complete
sets/results are built without the production planner, including unrelated
rows, identities, bounds/priority and inactive sentinels. Failure preserves
every caller/result field. Exact retries retain all offsets/modes.

Additional cases cover repeated/interleaved pools, mixed keeps/growths, desired
extension collisions, absent/wrong pools, absent/duplicate/global slots,
outside-member old extents, invalid complete sources, zero/shrinking/unaligned/
overflow lengths and invalid counts. Full **64-pool/disk/request / 195-argument**
CLI batches use near-u64 geometry, 64 mappings/regions and the **8768-byte V2**
limit. Preview preserves old bytes; publication matches an independently
constructed set and equal-size retries preserve exact bytes. Complete decimal
tokens and count remainders are rejected before source I/O. Real-file tests
reject corrupt/missing/symlink/nonregular sources and check writer exclusion
with preview availability.

Shared real-publisher fault models qualify changed/all-keep cross-pool growth
under short/EINTR writes and write/file-fsync/close/rename/directory-fsync
failures. Before rename old bytes remain; afterward only the full candidate
appears. Retrying completes both flushes. Armed faults never reach preview or
publication after later invalid growth. Both commands detect buffered stdout
failure. Host suites use ASan/UBSan; complete utility/guest C is audited for
heap/V-runtime dependencies and strictly cross compiled for both targets.

First boot grows the two new multi-pool mappings in place. Later exhaustion,
missing pools and duplicate global slots preserve exact saved bytes and emit
no prefix. Complete preview stays available under writer contention. Planning
changes no live length; a later unlisted extension conflict rejects the entire
live preflight and neither view grows. Removing the conflict permits explicit
replay with both generations and held writable/read-only descriptors intact.
Held descriptors read the prepared A9/AA extension pages, while original
A7/A8 data, modes and starts stay exact. Reverse-order all-keep retry preserves
the full bundle. Existing cleanup restores the baseline and original held
E7 data. `PLAN MULTI POOL GROWTH PASSED:` is required.

Both targets retain **200 warmup + 200 measured 41-command cycles / 16400
utility processes**, with every earlier storage assertion enabled. Two new
commands preview/publish a two-pool equal-size growth inside the existing
temporary pool-membership interval. Each family runs 400 batches and 800
ordered keep actions. Every slab class and large-page total must stay flat or
decrease; the 1800-second per-boot limit remains unchanged.

All seven earlier boots remain enabled. After seventh-boot allocation
assertions, the guest captures the exact **680-byte / nine-row / five-region**
allocation bundle, grows only slots 19/20 from 4096 to 8192 bytes and saves the
actual planned configuration. `PLAN MULTI POOL GROWTH SAVED:` is required.
Eighth-boot production init restores both grown lengths before the test starts;
all old mappings/data/modes and both extension pages persist. Complete equal-size
retries preserve bytes/generations. `PLAN MULTI POOL GROWTH BOOT PRESERVED` is
required. Independent artifacts construct the exact grown bundle by changing
only those two lengths and nested/outer CRCs; actual published/planned/boot
copies and complete retry reports must match. Actual raw data and every prior
artifact assertion remain enabled.

This changes contiguous desired mapping lengths. Physical adoption, eligibility
changes, live replay, relocation and filesystem resizing remain separate.
