# Atomic pool growth batch qualification

Run the native V controller in [README.md](README.md) with `--host`, then both
guest architectures. Production kernel code and the version-2 format are unchanged.

The host suite covers two-disk growth in request order, mixed 512/4096-byte
sectors, writable/read-only modes, mixed equal-size/growth requests and complete
equal-size retries. Every disk identity, mapping start/mode/order, untouched row
and member record must remain exact. Each old and requested extent must fit its
own selected member; another disk's free capacity cannot extend a mapping.

Rejection covers missing or repeated slots, absent pools, invalid complete
bundles, outside-member extents, zero/shrinking/unaligned/overflow lengths,
desired overlap, invalid counts and malformed CLI pairs. A feasible earlier
request followed by failure must preserve the whole set and caller output.
An independent cell oracle checks **4096 attempts**: all 256 two-disk
fragmentation patterns against 16 length pairs. It scans extension cells
without using the production planner and checks complete success or rollback.
A maximum batch grows 64 mappings across 64 disks/regions near the u64 limit,
roundtrips the 8768-byte bundle and retries the full 132-argument command.

Real-file tests cover preview, publication, byte-exact retries, directory writer
contention, and missing/corrupt/final-symlink/nonregular inputs. Preview remains
available under a writer lock. Shared publisher tests exercise changed and
equal-size batches through EINTR, three-byte short writes, write, file-fsync,
temporary-close, rename and directory-fsync failure. Before rename the old file
remains exact; afterward the complete new file is readable. No temporary survives,
and retries must write, rename and perform both flushes. Armed publisher faults
must not affect previews or reach publication after an impossible later request.
Buffered stdout failure returns failure: publication leaves the complete new
state, while preview leaves the old bytes. Host tests run under ASan/UBSan.

The first guest boot starts with two existing scratch mappings. An impossible
later request or repeated slot must preserve exact saved bytes and emit no
action rows. Successful preview reports growth on both disks without changing
saved or live geometry. Publication grows the saved rows together. Ordinary
replay rejects the smaller live views; an unlisted live extension conflict on
the later disk rejects complete-set preflight and explicit growth before the
first mapping changes. Removing it permits replay with both generations intact.
Held read-only/writable descriptors read prepared extension pages. Equal-size
retry reports two `keep` actions and preserves exact bytes; cleanup restores
the original bundle. `PLAN POOL GROWTH BATCH PASSED:` is required.

Each architecture runs 200 warmup and 200 measured forty-command cycles:
**16000 utility processes**, including 400 allocation batch previews/publications,
800 scratch placements, 400 growth batch previews/publications, 800 desired
scratch growths, 400 expansion batch previews/publications, 400 capacity batch
previews/publications, 400 pool queries and 800 member additions.
Neither scratch mapping becomes live. Every slab class and the large-allocation
page total must stay flat or decrease. The 1800-second per-boot limit is unchanged.

The four-boot fixture retains reordered discovery and physical-capacity adoption.
After a mixed keep/new allocation batch, a growth batch keeps the writable tail
at 8192 bytes and grows its read-only neighbor from 4096 to 8192 bytes. A held
read-only descriptor reads the flushed extension page after explicit replay.
The fourth boot must restore all seven mappings through production init and
preserve both neighbor pages, old/tail data, modes, disk identities and all three
ordered pool regions. The expanded tail pool has exactly **8372224** eligible
bytes remaining. `PLAN POOL GROWTH BATCH BOOT PRESERVED` is required.

Generated production/guest C for both architectures must contain no heap or V
runtime dependencies. Real guests cover VirtIO/ARM64 and AHCI/x86 with MBR and
512-byte sectors; mixed sectors, maximum bounds and publisher faults have host
coverage. Saved publication is atomic; live replay retains complete preflight
and the existing partial-application rules. Live administration still requires
serialization. Spanning, RAID, encryption and filesystem resizing remain open.
