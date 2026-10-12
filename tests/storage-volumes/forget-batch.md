# Atomic identity-based disk forgetting qualification

Run the native V controller in [README.md](README.md) with `--host` and both
guest architectures. `plan-forget-batch` and `plan-preview-forget-batch` select
1–64 empty participants by stable MBR/GPT identity, with safe absent retries.

Independent oracles check **1024** existing/requested subset combinations under
two request orders and two mixed-sector MBR/GPT layouts. They construct expected
surviving plans and old/new disk indices without the production planner.
Interleaved protected disks, mapping modes/global slots, inactive sentinels and
pool bounds/alignment/order/priority remain exact. Removed active positions are
cleared; remaining inactive storage is preserved. Matching absent retries keep
all survivors, including disks occupying a forgotten disk's former index.

Later populated disks, pool members, duplicate identities (even with different
geometry), invalid identities/counts/sets and ambiguous existing identities
preserve every caller and output field. Removing all enrolled disks fails.
Parser tests round-trip every GPT byte in printed GUID order and MBR byte order,
accept uppercase hexadecimal letters, reject zero/malformed/oversized identities
without changing output and reject malformed CLI arguments before file access.
Maximum tests use **64 identities / 67 arguments** on the full **8768-byte V2**
format, remove 63 disks in reverse request order while keeping one populated
disk with 64 mappings/regions near u64 bounds, remap every region from 63 to 0
and produce the exact **4736-byte** expected bundle. Repeating the same list
must preserve the survivor and file bytes. Bad/missing/symlink/nonregular bundle
sources fail without publication temporaries.

Shared publisher fault tests exercise changed/all-absent batches under
short/EINTR writes and write/file-fsync/close/rename/directory-fsync failures.
Before rename the old file remains; afterward only the complete compacted
candidate may appear. Retries always write, rename and complete both fsyncs.
Previews never publish. Both paths detect buffered stdout failure. Directory
lock tests reject publication while read-only previews remain available.
Host suites use ASan/UBSan; complete production/guest C must pass no-heap/no-V-
runtime audits and strict cross compilation on both architectures.

The first guest boot checks later populated/pool member and duplicate-request
failure, a mixed forget/absent list under a held writer lock, complete action
and survivor reports, exact durable retries, live generations and held-view
data. `PLAN FORGET BATCH PASSED:` is required. Each architecture runs 200 warmup
and 200 measured **37-command cycles / 14800 utility processes**, including
400 two-disk forgetting previews and publications with 800 ordered forget
actions each. Existing enrollment previews/publications and all capacity,
membership, priority, removal, allocation, growth, expansion and query checks
remain enabled. Slab classes and large pages must stay flat or decrease;
the 1800-second per-boot limit is unchanged.

The third boot puts two empty offline participants before the real secondary
disk. Its allocation pool refers to disk 3. Forgetting both empty identities
compacts that disk and its pool reference to index 1 while preserving priority,
all seven mappings and exact baseline bundle bytes. A held live generation
stays unchanged. `PLAN FORGET BATCH SAVED:` is required. Fourth-boot production
init restores the actual compacted bundle; both absent identities retry as keep
and retain exact bytes and physical disk indices. Existing data/mode/priority
checks remain enabled. `PLAN FORGET BATCH BOOT PRESERVED` is required.

This edits offline desired enrollment. It does not detach live mappings,
release extents, erase data or remove desired rows/pool membership implicitly.
