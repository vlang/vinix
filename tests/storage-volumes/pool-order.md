# Pool allocation priority qualification

Run the native V controller in [README.md](README.md) with `--host` and on both
guest architectures. `pool-order` and `pool-preview-order` accept a complete
1–64 member permutation. Kernel, ioctl and saved V1/V2 formats are unchanged.

The independent oracle enumerates all 720 six-member permutations under four
mixed-sector/MBR/GPT and interleaved-pool layouts: **2880** expected orders.
Each expected row is constructed from disk-specific fixture bounds. Only the
selected pool's existing positions may change; other regions, identities,
desired rows/modes, pending edits and unused storage remain exact. Aggregate
free capacity must stay equal. A subsequent first-fit allocation must select
the requested first disk. An unchanged-order retry retains every byte and
reports each previous priority equal to its requested priority.

Invalid counts, incomplete orders, duplicates, foreign/absent disks, absent
pools and corrupt saved sets preserve the entire set and caller results.
Maximum coverage reverses all 64 members near u64 bounds, roundtrips the full
8768-byte V2 format, and previews/publishes/retries all **68 CLI arguments**.
Malformed unsigned numbers and counts return usage failure before file access.
Corrupt, final-symlink, missing and directory sources stay untouched.

Real-file publisher tests exercise changed and unchanged orders under short/
EINTR writes and write/file-fsync/close/rename/directory-fsync faults. The old
file stays before rename; after rename the complete candidate may be visible.
Retry must always write, rename and complete both flushes. Preview never enters
the publisher under armed faults and remains available under an independent
writer lock. Both commands detect buffered stdout failure. Directory locking
remains asserted at rename and directory fsync. Host tests use ASan/UBSan.

The first guest boot checks incomplete, duplicate and absent-member failures,
complete preview under a held writer lock and exact saved-byte rollback.
Publishing reverse priority sends first fit to the other physical disk; a
durable retry reports both kept. Restoring the original priority changes the
next allocation while preserving the earlier desired placement, live geometry,
generations and held read-only data. Cleanup restores exact baseline bytes.
`PLAN POOL PRIORITY PASSED:` is required.

Each architecture runs 200 warmup and 200 measured forty-command cycles:
**16000 utility processes**, including 400 priority previews/publications and
800 ordered member actions each. Existing capacity, membership, allocation,
growth, expansion, preflight and replay operations remain enabled. Scratch
mappings stay offline. Every slab class and large-page total must stay flat or
decrease; the per-boot limit remains 1800 seconds.

Four boots preserve actual production-init replay after disk reordering and
physical growth from 16 to 24 MiB. The third boot explicitly reverses pool 3's
priority before saving the final seven-mapping, three-region bundle. The fourth
boot previews/retries that persisted order with two keep actions and exact
bundle bytes. Existing modes, generations and old/tail/neighbor/pool data stay
intact. `PLAN POOL PRIORITY BOOT PRESERVED` is required. Independent artifacts
must decode the actual pool table as disk 1 then disk 0, followed by the tail
region, without changing the disk-plan order or region bounds.

Production/guest C for both architectures must pass the existing no-heap/
no-V-runtime audits and strict cross compilation. Real guests cover VirtIO/
ARM64 and AHCI/AMD64 with MBR/512-byte sectors; mixed-sector/GPT and full bounds
have host coverage. This feature controls offline allocation priority. It does
not move data, rebalance existing mappings or reserve live extents; those
operations and the encompassing RAID/encryption roadmap work remain separate.
