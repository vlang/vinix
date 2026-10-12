# Atomic pool eligibility contraction qualification

Run the native V controller in [README.md](README.md) with `--host` and both
architectures. `pool-contract-batch` and `pool-preview-contract-batch` release
unused tails of 1–64 existing pool windows selected by MBR/GPT identity.

Independent end/action oracles check **1024** existing/requested subsets under
two request orders and two mixed-sector identity layouts. Expected windows,
old/new ends and disk indices are built without the production planner. Desired
rows, modes, pending lengths, global slots, disk/region order, inactive sentinels,
interleaved other pools and allocation priority stay exact. Later missing/wrong
identities/members, duplicate identities, invalid pools/counts/keys, zero/empty
ends, expansion, unaligned/overflowing bounds or occupied tails preserve every
caller and result field. Explicit mappings crossing either original boundary
protect only their occupied intersection. A sector-aligned end need not match
larger pool alignment. Identity retries still work after unrelated compaction.

Maximum tests exercise **64 requests / 132 CLI arguments**, mixed MBR/GPT/sector
layouts near u64 bounds, 64 disks/mappings/regions and the **8768-byte V2** limit.
Previews preserve old bytes; decoded publication matches independently expected
windows with unchanged rows. Equal-end retries preserve exact bytes; a later
invalid contraction never publishes a prefix. Counts/remainders and every token
are checked before I/O, including later identity/numeric failures, invalid pool,
zero ends and decimal overflow. Missing/corrupt/symlink/nonregular sources fail
without publisher temporaries.

Publisher faults cover changed/all-keep batches under short/EINTR writes and
write/file-fsync/close/rename/directory-fsync failures. Before rename old bytes
remain; afterward only the complete candidate appears. Every successful retry
writes, renames and completes both fsyncs. Previews never publish. Both commands
detect buffered stdout failure; writer exclusion preserves preview availability.
Host suites use ASan/UBSan. Production/guest C must pass no-heap/no-V-runtime
audits and strict cross compilation on both architectures.

First-boot guests verify later occupied-tail/missing/duplicate failures, complete
mixed contract/keep preview under a directory writer lock, equal-end retries and
accurate reduced free capacity. Removing a desired tail permits contraction while
its unlisted live descriptor/data/generation survive. Future two-disk allocations
fit only retained windows and remain offline. Cleanup restores exact baseline
bytes and preserves original generations/data. `PLAN POOL CONTRACTION BATCH
PASSED:` is required.

Each architecture runs 200 warmup and 200 measured **40-command cycles / 16000
utility processes**, including 400 complete contraction previews/publications
with 800 ordered keep actions each, against fully occupied window ends. All
previous capacity, allocation, growth, expansion, membership, priority, removal,
enrollment, forgetting, explicit addition/growth, query, health and replay checks
remain enabled. Slab classes and large pages must stay flat or decrease; the
per-boot limit remains 1800 seconds.

Third-boot preparation adds two unused pool-5 windows in reversed member order,
contracts their ends from 12 KiB to 8 KiB and saves the actual **616-byte V2**
configuration. Live generations stay unchanged. `PLAN POOL CONTRACTION BATCH
SAVED:` is required. Fourth-boot production init restores it, and pool queries
and equal-end identity retries retain bounds, priority and exact bytes. The
fixture preserves actual planned/boot contracted bundles before explicitly
removing only these unused memberships, recovering the previous **536-byte**
baseline for the earlier independent boot assertions. `PLAN POOL CONTRACTION
BATCH BOOT PRESERVED` is required. Artifact checks validate both contracted
bundles, CRCs, every key/row/window, priority, retry reports and durable held-tail
data, alongside all previous baseline/snapshot/raw-data checks.

Contraction changes saved eligibility; physical size, live detach, filesystem
resize, relocation and encryption remain separate.
