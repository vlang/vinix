# Atomic pool membership batch qualification

Run the native V controller in [README.md](README.md) with `--host` and on both
guest architectures. Production kernel, ioctl and saved V1/V2 formats are
unchanged. Four commands add/remove 1–64 members of one pool or preview the
complete edit without publishing or acquiring a writer lock.

The independent oracle checks **4096 additions and 4096 removals**: both request
orders, four existing-member combinations, eight window choices per disk,
four sector combinations and MBR/GPT identity configurations. It independently
checks saved bounds, logical sectors, alignment and overlap. Desired mappings,
modes, pending growth, disk identities and inactive storage are preserved.
New regions append in request order; matching members retain saved priority.
Removal keeps unrelated regions in order and clears only vacated active rows.
Later failure preserves the complete original set and caller results.

Bounds include invalid counts, repeated/absent indices, wrong pools, invalid
saved bundles, mismatched existing windows, full tables and near-u64 extents.
All 64 matching members retry at the full region limit. Complete removal returns
to V1; admission roundtrips the maximum 8768-byte V2 bundle. The full **260-argument
addition CLI** and **68-argument removal CLI** preview, publish and retry all
64 members. Corrupt, symlink, directory and missing inputs remain untouched.
An absent selected pool is an all-keep removal; every index must still refer
to an enrolled disk. Single-member command semantics remain unchanged.

Real-file publisher tests run additions/removals and matching/absent retries
through short/EINTR writes, write/file-fsync/close/rename failures and a directory
flush failure after rename. Before rename the original remains; after rename
the complete candidate may be visible. A subsequent retry must write, perform
both flushes and rename, even when every request is kept. Preview never enters
the publisher under any armed fault. Both families detect buffered stdout
failure. Directory-lock assertions remain enabled at rename and directory
flush; host lock tests check both preview/writer families. All host suites
use ASan/UBSan.

The first guest boot checks later-addition failure, duplicate requests and
missing enrolled removal indices with exact saved-byte rollback. Both complete
previews succeed while publication is excluded by an independent writer lock.
Reverse-order new admissions define first fit, and matching retries cannot
reorder them. Mixed keep/new admission and absent/present removal are checked.
Removing members retains desired rows, modes, existing live generations and a
readable held descriptor. Cleanup restores exact baseline bytes.
`PLAN POOL MEMBERSHIP BATCH PASSED:` is required.

The two previous single-member additions in each cycle become a complete
membership preview and publication. Each architecture still runs 200 warmup
and 200 measured thirty-nine-command cycles: **15600 utility processes**, including
400 complete membership previews/publications with 800 member actions each.
Existing capacity, allocation, growth, expansion, replay and preflight work
remain enabled. Scratch mappings stay offline. Every slab class and large-page
total must remain flat or decrease; the 1800-second per-boot limit is unchanged.

Four boots check reordered discovery, actual production-init replay, and
capacity adoption after the raw disk grows from 16 to 24 MiB. The newly adopted
tail is admitted through a membership preview/publication before separate
expansion and mapping allocation/growth. The fourth boot retries both original
members in reverse request order, preserving the exact checksummed seven-row,
three-region bundle. Live generations, permissions and old/tail/neighbor/pool
bytes remain intact. `PLAN POOL MEMBERSHIP BATCH BOOT PRESERVED` is required.

Both architecture production/guest generated C outputs must remain free of
implicit heap or V-runtime dependencies. Real guests cover VirtIO/ARM64 and
AHCI/AMD64 with MBR and 512-byte sectors; mixed sectors/GPT and maximum bounds
have host coverage. Membership changes saved eligibility and leaves physical
adoption, allocation and live replay separate. The encompassing RAID/encryption
and filesystem-resizing roadmap work remains open.
