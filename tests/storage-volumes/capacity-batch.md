# Atomic physical capacity adoption batch qualification

Run the native V controller in [README.md](README.md) with `--host`, then both
guest architectures. Production kernel code, ioctl and saved V1/V2 formats
are unchanged.

The planner suite preserves disk identity, logical sector size, every desired
row and mode, pending growth, ordered pool bounds and unused in-memory storage.
It covers reversed request/member order, mixed adopt/keep requests and complete
equal-capacity retries. Any invalid list or later observed key must preserve
the entire original set and caller results. An independent four-condition
oracle checks **4096** combinations: matching identity, matching sector, exact
expected bytes and no shrink for each disk, under both request orders and eight
mixed-sector/MBR/GPT configurations. The maximum batch retains 64 disks, mappings
and regions near u64 limits and roundtrips the complete 8768-byte bundle.

Real-file probe tests replace only the physical open/close, read-only status
and identity-read boundaries, plus the existing publisher fault boundary.
Every disk must remain pinned together during final verification and publication.
The exact query order is all initial probes followed by all final probes. An
early disk changing during a later initial probe must be rejected. Coverage
includes EINTR, short/error reads on both passes, missing/offline/virtual/partition
targets, malformed GPT, changed identifiers, sectors, capacities or runtime IDs,
repeated physical IDs, and later open failure. Every opened descriptor drains;
invalid metadata lists and malformed/corrupt saved files open no devices.
Later regular-file, missing and final-symlink devices close the earlier pin.

Preview succeeds under an independently held writer lock and never enters the
publisher, even with every publisher fault armed. Changed and equal-capacity
batches exercise short/interrupted writes and write/file-fsync/close/rename/
directory-fsync failure. The old file remains before rename; afterward the
complete new capacities may already be visible. Retrying must perform both
flushes and atomic replacement with no surviving temporary. Device cleanup
occurs while the writer's directory lock is still held. Buffered stdout failure
returns failure for preview/publication and closes every device, preserving the
same old/complete-new rule. The full **195-argument** CLI pins and retries all
64 simulated physical disks. Host tests use ASan/UBSan.

The first guest boot requires later expected-size and duplicate logical/physical
disk failures to preserve exact saved bytes with no action rows. A final device
symlink fails, while a physical mknod alias is accepted. Publication is excluded
by a held directory lock; complete reverse-order preview remains available.
Equal-capacity publication/retry retains exact bytes, live geometry/generations
and a readable held view. `PLAN CAPACITY BATCH PASSED:` is required.

Each architecture runs 200 warmup and 200 measured forty-command cycles:
**16000 utility processes**, including 400 complete capacity previews/publications
with 800 retained-disk actions each, 400 expansion previews/publications, 400
allocation previews/publications with 800 placements and 400 growth
previews/publications with 800 desired growths. There are 800 cycle member
additions and 400 pool queries. Scratch mappings remain offline. Every slab
class and the large-allocation page total must stay flat or decrease. The
1800-second per-boot limit is unchanged.

Four boots preserve reordered discovery and production-init replay. After one
raw disk physically grows from 16 to 24 MiB, stale saved geometry must be
rejected. A feasible first adoption followed by a later wrong size must leave
both saved capacities unchanged. Reverse-order preview then reports one keep
and one adoption; publication adopts exactly the grown disk, and complete
retry reports both kept. Subsequent pool expansion, tail allocation/growth and
read-only neighbor replay remain separate. The fourth boot must retain seven
mappings, three ordered regions, exact identities/modes and old/tail/neighbor
pages. Repeating the complete capacity batch retains all live generations.
`PLAN CAPACITY BATCH BOOT PRESERVED` is required.

Generated production/guest C for both architectures must have no heap or V
runtime dependencies. Real guests cover VirtIO/ARM64 and AHCI/x86 with MBR and
512-byte sectors; mixed sectors/GPT, maximum bounds and probe/publisher races
have host coverage. Descriptor pins and sequential rechecks cannot freeze
hardware geometry. Serialized administration, separate live preflight/replay,
unchanged partial-application rules and existing identifier provenance limits
still apply. RAID, encryption and filesystem resizing remain open.
