# Observed physical capacity contraction qualification

Run the native V controller in [README.md](README.md) with `--host` and both
architectures. `plan-contract-capacity-batch` and its preview select 1–64
enrolled MBR/GPT identities and adopt exact observed smaller or equal sizes.

An independent **4096-case** oracle enumerates identity, saved sector, exact
observation and contraction conditions across both request orders and eight
MBR/GPT/512/4096-sector layouts. Expected sets/results are built independently.
Desired rows, pending lengths, modes, offsets, slots, all pool bounds/priority,
unselected disks and inactive sentinels stay exact. Identity retries survive
unrelated disk compaction; selector geometry is ignored.

Later missing/duplicate/ambiguous identities, invalid counts/kinds, tiny/zero/
unaligned/overflowing sizes, expansion, mismatched observations, desired tails
and unselected pool windows outside retained capacity preserve all caller and
result fields. Maximum tests reach **64 requests / 195 CLI arguments**, full
u64 geometry and the **8768-byte V2** disk/mapping/region bound.

The physical syscall model replaces only device open/close/status/identity
reads and publisher fault boundaries. Exact read-only/CLOEXEC/NOFOLLOW/NONBLOCK
flags are asserted. All pins stay open until the final all-descriptor pass and
through publication and reporting; they drain before writer-lock release.
Tests reject partial opens, later regular/missing/symlink devices, short/EINTR/
failed reads, bad GPT CRC, offline/logical/partition devices, duplicate physical
IDs and final identity/sector/size/physical-ID changes. An early disk changing
after a later probe must fail. No mutating physical ioctl is permitted.

Changed/all-keep publication tests cover short/EINTR writes and write/file-fsync/
close/rename/directory-fsync errors. Before rename old bytes remain; afterward
only the complete candidate appears. Successful retries replace and complete
both flushes. Previews remain usable under writer locks and never publish.
Buffered stdout failure closes every pin and follows the same publication
rules. Corrupt/symlink/nonregular saved inputs and invalid complete lists never
open physical devices. Host suites run ASan/UBSan. Complete target/guest C is
audited for heap/V-runtime dependencies and strictly compiled for both targets.

First-boot guests verify identity selection, alias pinning, later mismatch and
duplicate rejection, complete previews under writer contention and unchanged
live views/generations/held data. `PLAN CAPACITY CONTRACTION BATCH PASSED:` is
required. Both targets retain **200 warmup + 200 measured 40-command cycles /
16000 utility processes**, including 400 complete contraction previews and
publications with 800 ordered keeps each. Slab classes/large pages must stay
flat or decrease; each boot retains the 1800-second limit.

All previous four-boot growth and pool assertions remain enabled. Fourth boot
preserves its actual **536/616/696-byte** bundles and prepares a separate
candidate with pool-4's unused end reduced from 24 to 20 MiB. The controller
preserves actual grown raw/config images before truncating only its disposable
raw disk to **20 MiB**. Fifth boot must reject old geometry without creating a
mapping. Old pool bounds reject adoption; a later secondary mismatch rolls back
the primary's real contraction. Complete read-only preview and publication then
adopt 24-to-20 MiB while retaining all seven desired mappings. Explicit replay
checks original data, grown tails and held descriptors. Pool-4 free capacity is
**4177920 bytes**. `PLAN CAPACITY CONTRACTION SAVED:` is required.

Sixth-boot production init restores exact contracted geometry before the test
starts. All seven mappings/modes/data and pool bounds persist; equal-size retries
preserve bundle bytes and live generations. `PLAN CAPACITY CONTRACT BOOT RESTORED:`
and `PLAN CAPACITY CONTRACTION BOOT PRESERVED` are required. Independent artifact
checks compare guest-produced old/new bundles, nested/outer CRCs, every retained
row/window, complete retry reports, bounded capacity and the actual raw disk's
entire retained prefix. All earlier artifact checks remain enabled.

The utility adopts observed disk geometry; it does not shrink a filesystem or
physical backend, relocate data or remove live mappings.
