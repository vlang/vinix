# Pool expansion and mapping-growth qualification

Run the native V controller commands in [README.md](README.md). The host suite
compiles the production utility with ASan/UBSan and audits both architectures'
complete generated utility C for implicit allocations or V runtime dependencies.
The version-1/version-2 format, allocator, restore and init-policy suites remain
enabled.

Host coverage requires:

- Expansion retaining member order, start, alignment, disk identity and all
  desired mappings. Occupied rows in added eligibility reduce free capacity;
  first fit keeps the original member priority.
- Atomic rejection of absent members, shrink, unaligned/overflowing/out-of-disk
  ends and overlaps with another pool on the same disk. Adjacent regions and
  expansion with a full 64-region table are accepted. The saved capacity must
  be adopted before expanding into a larger physical tail.
- Growth requiring both old and requested extents inside the selected member,
  retaining disk/start/slot/mode and every other row/region. Missing pools/slots,
  wrong membership, straddling mappings, shrink, zero, sector misalignment,
  bounds/overflow and desired-row overlap leave state and result outputs intact.
- An independent sector oracle for all 128 seven-sector fragmentation patterns
  at nine growth lengths (1152 cases), including readonly/writable rows and
  insufficient contiguous room despite capacity elsewhere.
- Near-u64 geometry, different 512/4096-byte sector sizes, regular-file and
  final symlink/nonregular/corrupt/missing input rules, and strict decimal/argument
  parsing for both commands.
- Changed and equal-size commands through every shared publisher boundary:
  EINTR/short writes, write, file-fsync, close, rename and directory-fsync.
  Before rename the previous bundle survives; after failed directory fsync the
  complete new file is visible with a failure result. An equal-size retry must
  write, rename and perform both flushes. Temporaries and descriptors drain.
- Buffered stdout failure returning an error after complete publication for
  both expansion and growth.

The first guest boot requires `PLAN POOL GROWTH PASSED:`. Expanding the first
member from 4096 to 8192 eligible bytes must increase aggregate capacity while
retaining allocation priority. A new readonly view is planned on that member,
created separately, then grown offline to 8192 bytes. Default replay rejects
the old live length. An unlisted view in its extension must block all preview
actions and explicit growth without changing geometry or generation.

Removing the conflict permits a grow action and explicit replay. A held readonly
descriptor reads the prepared second page, and mode/generation remain intact.
Invalid growth requests preserve the saved file; equal-size expansion/growth
retain its exact bytes and repeated replay keeps the generation. Scratch cleanup
restores the exact original bundle and member order.

Each of 200 warmup and 200 measured cycles now executes forty utility
processes, including allocation, growth and expansion batch previews/publications:
16000 processes, 400 expansions, 800 desired growths, 800 scratch placements,
400 pool queries and 800 cycle member additions. No scratch view is created.
Every slab class and the large-page
total must stay flat or decrease.

The second boot restores the actual saved pool bundle with reordered physical
devices. Before the third boot the controller enlarges its disposable raw
file to 24 MiB; stale saved geometry and expansion beyond unadopted capacity
must fail. After explicit adoption, the guest enrolls a 4096-byte tail member,
expands it to the full adopted tail, allocates and applies a writable view, then
uses pool-aware desired growth and explicit replay through a held writable
descriptor. Both durable tail pages and old data/modes/generations are verified.

The fourth boot must restore all seven mappings through production init, keep
the two original pool records, and report the expanded tail pool's exact
`8372224` free bytes alongside its grown 8192-byte writable mapping and grown
8192-byte read-only batch neighbor. See [batch qualification](pool-batch.md)
and [growth batch qualification](pool-grow-batch.md).
`PLAN POOL GROWTH BOOT PRESERVED` is required. The final file is a guest-published
version-2 bundle with three regions; no host plan injection occurs.

Guest coverage is MBR/512-byte VirtIO on ARM64 and AHCI on x86. Mixed sectors,
maximum/overflow geometry and publication faults use host models. Expansion
and growth plan saved block capacity; filesystem resizing, spanning volumes,
RAID, encryption and live extent reservations remain separate work. See
[the command contract](../../docs/storage-volumes.md#pool-expansion-and-mapping-growth).
