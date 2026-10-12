# Atomic desired mapping removal qualification

Run the native V controller in [README.md](README.md) with `--host` and on both
guest architectures. `plan-remove-batch` and `plan-preview-remove-batch` accept
1–64 distinct desired slots; missing slots are idempotent keep actions. Live
views and existing single-slot removal behavior are preserved.

An independent stable-filtering oracle enumerates every nonempty ordered
subset of six slots: 1956 sequences under four mixed-sector/MBR/GPT and
interleaved-pool layouts, or **7824 cases**. Each request includes an absent
slot. The complete result must match independent compaction, cleared vacated
rows and slot ownership. Remaining rows/modes, pending edits, disk identities,
enrollment/indices, unused storage and every pool bound/alignment/priority stay
exact. Detailed removal results identify the original disk/row in request
order. Each absent retry has no removed actions and keeps the entire set.

Later duplicates/out-of-range slots, invalid counts and invalid source sets
preserve caller state and results. Maximum tests remove all 64 slots on one
disk and across 64 disks near u64 capacity bounds. Both commands exercise all
**67 CLI arguments**, preview byte preservation, exact all-absent retries,
retained empty disk/pool enrollment and freed global slot reuse. Malformed
unsigned numbers/counts return usage failure before source access; corrupted,
final-symlink, missing and nonregular files stay untouched.

Real-file tests cover changed/all-absent batches under short/EINTR writes and
write/file-fsync/close/rename/directory-fsync failures. Before rename the old
file remains; after rename only the complete candidate may appear. Every retry
must write, rename and complete both flushes. Preview never enters the publisher
under armed faults. The shared fixture asserts locking at rename and directory
fsync, cleanup of unpublished temporaries, and buffered stdout failure for
both commands. The independent writer-lock fixture blocks publication while
allowing complete removal preview. Host suites use ASan/UBSan.

The first guest boot rejects a later duplicate/bad slot and preserves exact
bytes. It previews a reverse cross-disk remove/absent/remove list under a held
writer lock, publishes both removals atomically, retries all absent slots and
checks exact saved bytes. Replay omits removed desired rows while live views,
generations and held read-only data remain usable. A freed desired slot can
be planned on another disk, but live preflight rejects its conflicting old
view before creating a prefix. Cleanup restores exact baseline bytes/modes.
`PLAN REMOVAL BATCH PASSED:` is required.

Each architecture runs 200 warmup and 200 measured thirty-nine-command cycles:
**15600 utility processes**. The two single-slot scratch removals become one
complete preview and one complete publication, with 400 batches and 800 ordered
removals in each family. Existing capacity, membership, priority, allocation,
growth, expansion, preflight and replay checks remain enabled. Scratch views
stay offline. All slab classes and large pages must stay flat or decrease;
the per-boot limit remains 1800 seconds.

Four boots exercise production init, reordered physical disk discovery and
physical growth from 16 to 24 MiB. Before the final save, the third boot adds
temporary desired slots 19/20 on both disks, previews/removes both and verifies
exact baseline bytes; `PLAN REMOVAL BATCH SAVED:` is required. The fourth boot
checks both views remain absent, previews/retries them as keep and preserves
the complete seven-mapping, three-region bundle and reverse pool priority.
`PLAN REMOVAL BATCH BOOT PRESERVED` is required. Independent artifacts must
decode both CRC layers, confirm slots 19/20 are absent, preserve every remaining
row/mode and retain old/pool/grown/tail/neighbor data.

Both production/guest C outputs must pass existing no-heap/no-V-runtime audits
and strict target compilation. Real guests cover VirtIO/ARM64 and AHCI/AMD64;
mixed-sector/GPT and full limits have host coverage. This feature edits desired
state; live removal, relocation, RAID and encryption remain separate operations.
