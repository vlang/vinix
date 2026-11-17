# Logical GPU queue record reclamation

Status: this lifetime fix passes offline checks; **full driver parity remains
incomplete**. Sources start at Vinix `bc40b06d096fc9626f25f5c8cbd519dfbc8cdf97`.
The reference remains Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf`,
selected through the retained Omarchy/package source chain in the
[parity index](m1-agx-parity.md). This increment compares that pinned source;
it makes no new latest-upstream claim.

Vinix's `WorkQueue.destroy()` canceled borrowed slots and returned without
freeing the logical record. Both native file teardown and fake G17 teardown
therefore leaked one record per successful queue lifetime. This is separate
from the previously fixed [G13 GPU-resource records](m1-agx-queue-records.md).
Upstream `drivers/gpu/drm/asahi/workqueue.rs` owns WorkQueue through reference
counted allocations, with pending containers under its mutex; `queue/mod.rs`
retains workqueue references in prepared jobs. Vinix's logical record is an
exclusive file owner, rather than an equivalent Rust object graph.

The new `free_workqueue()` reclaims only that metadata, after destruction and
its deferred unlock return. Close preserves cancellation order, then removes
and frees rows in descending order. Detached G13 queues retain their existing
capture, backing and mapping gates. Idle fake destruction and G17/legacy
destruction save a pointer value before deleting a row: mutable foreach
variables alias the pointer array and may change when deletion shifts it.
Failed constructor frees use the same disposer. The constructor's verified
allocation is marked `@[freed]`.

Fake submission holds the file lock while using a queue. Asynchronous jobs
retain a pending slot and file/VM pin; the worker finishes its last queue
access, including the queue unlock, before dropping that pin. An idle destroy
also drains a concurrent completion through the queue lock. No worker queue
access follows a possible final file close. Borrowed WorkItems and fences stay
alive independently. An independent lifetime review found no blockers after
the saved-pointer correction. Production kernel builds omit debug assertions;
the existing caller gates carry the lifetime contract.

The controlled host measurement uses the production queue allocation and
extracted fake close logic, `-gc none -manualfree`, one warmed file and
`MallocNanoZone=0`. Baseline: 10,000 closes retain 10,000 records and
12,800,000 malloc-accounted bytes. Fixed: zero retained blocks/bytes in each
of three 10,000-close batches. The fixture queue is 1,056 bytes before malloc
rounding; its instrumented lock and allocator differ from native kernel slabs.
No native memory-rate claim follows from these host bytes.

Validation:

- All 75 focused V test files pass. ASan/UBSan with fake stacks pass production
  slot cancellation/completion, 143 fake owner cases and 51 native file owner
  cases plus aggregate-pin retention. The existing file-close suite, including
  216 G13 metadata cases, passes.
- Seven compiled negative variants fail their designated lifetime assertions;
  six native C-checker mutations are rejected. Native ARM C confirms exactly
  seven disposal callers and saved pointer values, unchanged layouts, and 18
  unchanged cancellation/completion/capture/backing bodies.
- Isolated ARM and x86 builds pass. The original strict x86 C checker passes
  after its existing discard-path normalization; x86 excludes the affected
  queue modules. ARM allocation diagnostics decrease only from 378 to 377
  sites across 835 sources; x86 stays at 289 across 813. The existing allowance
  check still fails for other sites. No allowance list was changed.
- Existing G13 failure, 3,640 constructor, 3,672 context-retirement and 1,008
  deferred-context cases pass. The reference source gate passes; the complete
  parity audit still reports `not_equivalent`.

Complete external evidence is retained at
`/Users/alex/.local/state/vinix/omarchy-m1-workqueue-records-20261117/`.
The bundle includes sources, baseline and final generated C/ELFs, diagnostics,
measurement binaries, negative cases, logs, build input inventories and review.
The pre-annotation ARM build is diagnostic: the constructor's new scalar local
changes its C; no identical-ELF claim is made. The original complete preceding
bundle is checked before sealing this one. Full archive restoration and typed
inventory checks verify all retained payloads. A post-commit receipt binds
feature paths and reports to their committed bytes.

SHA-256 pins:

- Inventory: `5178619abedb27ba4cd03840a890666ee68f6e620246e302849f9418fcf4e854`
- Complete archive: `de0dc91166299eee7af0fefa45db0f6310c1e02c0c897c5744864ad407fb8ccc`
- ARM ELF: `7d5268dc02cfdfe79273d3c1440162f25133a461c5ba87728da3654edd7fac89`
- x86 ELF: `dba6fe027d5ac80faab8173d40f88f13587d2df4b128b92625ec4d86b11b1e9e`
- ARM generated C: `5d13acaf353fae43c7505c17fe8f8421c7218fce1ca0313713e624cd687a2853`

Remaining gaps include modern ioctl/Mesa integration, allocator backing and
accounting, native scheduling/performance, and firmware/event lifecycle paths.
Host tests do not establish hardware correctness. No GPU access, firmware
execution, boots, reboots or deployments occurred.
