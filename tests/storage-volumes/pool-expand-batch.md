# Atomic pool expansion batch qualification

Run the native V controller in [README.md](README.md) with `--host`, then both
guest architectures. Production kernel code and the version-2 format are unchanged.

The host suite covers expansion of two existing members in reversed saved order,
512/4096-byte sectors, mixed equal-end/expanded requests and complete equal-end
retries. Every disk identity, desired row and mode, member start/alignment/order
and other pool remains exact. A desired mapping inside added eligibility reduces
available space without preventing expansion. Adjacent pool regions are accepted.

Rejection covers missing or repeated members, absent pools, invalid complete
bundles, zero/shrinking/unaligned/overflow/out-of-disk ends, region overlap,
invalid counts and malformed CLI pairs. A feasible earlier expansion followed
by failure must preserve the complete set and caller results. An independent
cell oracle checks **6400 attempts**: 256 two-disk blocking-region patterns
against 25 requested-end pairs. It scans added eligibility cells without the
production validator, checking complete success or rollback, including a desired
row straddling the old end. A maximum batch expands all 64 existing regions
across 64 disks near the u64 limit, retains 64 mappings, roundtrips the 8768-byte
bundle and retries the full 132-argument command.

Real-file tests cover preview, publication, exact retries, writer contention and
missing/corrupt/final-symlink/nonregular inputs. Preview succeeds under a writer
lock. Shared publisher tests exercise changed and equal-end batches through
EINTR, three-byte short writes, write, file-fsync, temporary-close, rename and
directory-fsync failures. Before rename the old file remains exact; afterward
the complete new file is readable. No temporary survives; a retry must write,
rename and perform both flushes. Armed publisher faults must not affect preview
or reach publication after an impossible later request. Buffered stdout failure
returns failure: publication leaves complete new eligibility and preview leaves
old bytes. Desired mappings remain exact throughout. Host tests use ASan/UBSan.

The first guest boot starts from the actual two-disk bundle. An impossible later
request or repeated member must leave exact saved bytes and emit no actions.
An independently held directory lock rejects publication but permits complete
preview. A successful reversed-order request expands both members, reports the
requested order, and retains saved allocation priority. Exact capacity rises
from 16384 to 24576 bytes. Retry reports both members kept and preserves exact
bytes. A subsequent 8192-byte allocation must still select the first saved disk
and apply separately; preexisting geometry, generations and a held descriptor's
data stay intact. Cleanup restores exact baseline bytes.
`PLAN POOL EXPANSION BATCH PASSED:` is required.

Each architecture runs 200 warmup and 200 measured forty-command cycles:
**16000 utility processes**, including 400 expansion batch previews/publications
with one expansion and one retained member each, 400 allocation batch
previews/publications with 800 scratch placements, and 400 growth batch
previews/publications with 800 desired growths. There are 800 member additions
and 400 capacity batch previews/publications and pool queries. Scratch mappings
stay offline. Every slab class
and the large-allocation page total must stay flat or decrease. The 1800-second
per-boot limit is unchanged.

Four boots cover reordered discovery, physical capacity adoption and production
init replay. Expansion beyond saved geometry must fail for the entire batch even
after the raw disk has physically grown. After explicit adoption, a single-member
batch previews/publishes the enlarged tail and retries its equal end before
allocations and growth. The fourth boot must retain all three ordered regions,
seven mappings, disk identities, modes and old/tail/neighbor pages. The expanded
tail pool has exactly **8372224** eligible bytes remaining.
`PLAN POOL EXPANSION BATCH BOOT PRESERVED` is required.

Generated production/guest C for both architectures must contain no heap or V
runtime dependencies. Real guests cover VirtIO/ARM64 and AHCI/x86 with MBR and
512-byte sectors; mixed sectors, maximum bounds and publisher faults have host
coverage. Expansion changes saved eligibility; it does not reserve live extents
or adopt physical geometry. Live administration still requires serialization and
separate preflight/application. Spanning, RAID, encryption and filesystem resizing
remain open.
