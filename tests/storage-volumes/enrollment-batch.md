# Atomic disk snapshot enrollment qualification

Run the native V controller in [README.md](README.md) with `--host` and both
guest architectures. `plan-enroll-batch` and `plan-preview-enroll-batch` import
1–64 snapshots in request order, keeping existing indices and exact matches.

An independent append/keep oracle checks every existing/requested subset of
four disk plans under two request orders and two mixed-sector/MBR/GPT layouts:
**1024 cases**, including empty-request rejection. It constructs the expected
complete set and action indices without calling the production planner.
Remaining desired rows/modes, pending edits, identities, inactive storage and
pool bounds/alignment/priority stay exact. Matching retries add nothing and
retain original indices. New empty and populated disks append in request order.

Later conflicting geometry/sector size/modes/row order, duplicate identities,
duplicate global slots, invalid counts/plans and ambiguous existing identities
preserve every caller field and result. Maximum CLI tests retain all 64 source
descriptors, exercise all **67 arguments**, reach the full **8768-byte V2**
format with 64 disks/mappings/regions near u64 bounds and preserve byte-identical
all-keep retries. A later new disk at capacity fails atomically. Bad later
sources, self-import, aliases, corruption and invalid counts/empty paths never
publish a prefix or alter source plans.

Source-boundary tests mutate an earlier input while opening a later one:
corrupt bytes, replace it with a different valid snapshot or truncate it.
Final pinned-inode rechecks must fail before publishing/reporting. Replacing
its path retains the original descriptor/snapshot. Interrupted and short
preads succeed; EOF and final stat/read/open failures abort. Every opened input
is read-only/CLOEXEC and closes on success or failure, including buffered
stdout failure. Shared publisher faults cover changed/all-keep batches under
short/EINTR writes and write/file-fsync/close/rename/directory-fsync failures.
Old bytes stay before rename; afterward only the complete candidate appears.
Retries always write, rename and complete both fsyncs. Previews never publish.
Host tests use ASan/UBSan; production/guest C must pass no-heap/no-V-runtime
audits and strict compilation on both architectures.

The first guest boot checks later corrupt/duplicate inputs, conflicting
pending desired capacity, mixed new/matching preview under a held writer lock,
whole-set rollback and byte-identical retries. An unavailable empty import
blocks all later live actions, while held views, generations and data remain
intact. Reverse-order matching imports preserve disk indices. Cleanup restores
exact baseline bytes. `PLAN ENROLLMENT BATCH PASSED:` is required.

Each architecture runs 200 warmup and 200 measured **41-command cycles**:
**16400 utility processes**, including 400 two-disk enrollment previews and
400 publications with 800 ordered add actions each. Two unavailable empty
disks append, then both are forgotten before live replay. Existing capacity,
membership, priority, removal, allocation, growth, expansion and query checks
remain enabled. Scratch views stay offline. All slab classes and large pages
must stay flat or decrease; the per-boot limit remains 1800 seconds.

Four boots cover production init, reordered physical discovery and 16→24 MiB
capacity growth. The third boot omits the second physical disk's desired rows
and eligibility, forgets it, then reimports it together with a matching primary
snapshot. Eligibility/priority are restored explicitly and exact seven-mapping,
three-region baseline bytes must match. Live generation stays unchanged.
`PLAN ENROLLMENT BATCH SAVED:` is required. The fourth boot restores the actual
bundle, previews/retries both snapshots as keep and preserves exact bytes,
geometry, row modes, reverse pool priority and old/pool/grown/tail/neighbor data.
`PLAN ENROLLMENT BATCH BOOT PRESERVED` is required. Independent artifacts must
decode both source snapshots and final bundle CRCs and compare every imported
row/key with the corresponding saved disk.

This edits offline desired state. It does not probe physical source devices,
overwrite conflicting enrolled plans or create live mappings; complete live
preflight/replay and pool configuration remain explicit separate operations.
