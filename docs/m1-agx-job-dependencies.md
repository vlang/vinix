# Captured scheduler dependency deduplication

Both G13 submission ABIs now reduce their private input copy before pending
publication. Nil fences disappear; each context keeps its greatest unsigned
sequence, preserving the context's first position and the first equal-sequence
record. A newer selected fence can release its wait without waiting again on a
discarded older record. Different contexts still wait independently; input errors
do not become the job's own completion error. Original snapshots remain unchanged.

The reduction reuses existing copied storage and introduces no allocation or
metadata release. Dynamic results keep their allocation base even when reduced
to zero records. Existing failure rollback and worker ownership transfer/release
remain intact. An initial unsafe address still caused V to heap-box the copied
header. The retention probe caught this; direct field writes now keep it on the
stack. Initial sources, ARM C/ELF and failed measurements remain retained.

Reference: Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf`. Native builds
pin Vinix `4755d6b55c6459658fe48fc25b7fbcc0ebf71abb` plus two owned overlays;
concurrent event edits are excluded. Offline checks pass:

- ASan/UBSan with kernel GC mode: 4,096 selections and 32 real legacy/modern
  pending lifecycle cases, plus full existing async/modern/timeline/queue
  regressions. Boundary lists 0/1/2/64/65/129/1,025 test allocation refusal,
  private source preservation, independent backing and nil-only dynamic cleanup.
- Four compiled negatives fail designated missing-integration, reversed latest
  selection, replaced ties and borrowed-copy ownership assertions.
- All 4,096 selections and generic-fence readiness outcomes match compiled
  unchanged pinned `drm_sched_job_add_dependency`,
  `drm_sched_entity_add_dependency_cb` and comparator bodies. Xarray/refcount/
  callback plumbing is modeled and the comparator's 64-bit branch is selected.
- Nine warmed 1,000-operation copy/release batches at 4/65/1,025 records retain
  zero host malloc blocks/bytes. This does not qualify successful-publication
  metadata reclamation or native slab/whole-kernel retention.
- ARM MP and x86 builds and all 79 source-contract files pass. ARM C rejects
  hidden/new reduction allocations, matches sanitized/measurement/trace bodies,
  and confirms submit changes only its private-copy call. Fifteen shared capture,
  polling, completion, owner and transfer bodies match baseline. X86 prunes the
  reducer and preserves its shared DRM transfer body. Independent lifetime review
  found no remaining blocker, including zero-count owners and stack fixtures.
- Allocation diagnostics remain 377 ARM / 289 x86 sites across 854 / 825 source
  files. Every file/kind count matches the preceding complete bundle; existing
  allowance failures remain. Allowances and historical checkers are unchanged.

Full parity remains **incomplete**. This comparison qualifies Vinix's native
64-bit fence model. Asahi publishes scheduler finished fences initialized with
32-bit sequences; Vinix queue fences currently use 64-bit timestamps. Their
wraparound equivalence is not established. Scheduler policy, published metadata
reclamation, sync interoperability, backing/purge behavior, matched Mesa and
hardware acceptance remain open or unqualified. Generic timeline capability
stays disabled. No hardware access, firmware execution, Vinix/QEMU boot,
deployment or reboot occurred.

Maintained [tests and runners](../tests/agx-job-dependencies/README.md). Complete
selected evidence, archive/restoration and post-commit receipt are retained at
`/Users/alex/.local/state/vinix/omarchy-m1-job-dependencies-20261117/`.
Sealing rechecks the original complete preceding bundle and both new bundle roots;
binding verifies committed feature bytes against sealed source. Earlier setup,
wrapper and header-boxing failures remain separately retained.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `60e9268c853f2b0c0da974d7ce7f623e414f49626718e2f1147fc1e43bc46e94` |
| `bundle.tar.gz.inventory.txt` | `b6759160ab9924d98f7f3ef509ac76eaed6fa8c8a34cce39fa6ff0543e08c5b0` |
| ARM ELF | `04bdbef3738be7afb88fc2d2af41fe5b254a58add22d5cc45063b35e37fd28f8` |
| ARM C | `587aa7df2baa656d2ddcbcf7a9d3360a88f006a7c4d2c75dbebc9cbe47426e21` |
| x86 ELF | `d05a87e5b7a16eb292c0a0df7125ce09cf9902dfa7346a4fe6966b594e8f6640` |
| x86 C | `a9363631961fba5222527ed4ab66ef5c37267fbc4cb68c49b3cba2396b7873f6` |
