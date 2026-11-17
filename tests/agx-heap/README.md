Compile `run.v` externally, then run `--measure` or `--sanitize`. The runner
compiles the complete production allocator with `-gc none -manualfree` and copies
`kernel/lib/math.v` for historical sources. Its lock service uses a real host mutex. Optional
`--allocator-source PATH` selects a retained baseline or counterexample.
`AGX_HEAP_TEST_C` and `AGX_HEAP_TEST_BINARY` retain output outside Git.
Temporary fixtures are removed before the runner exits, including negative cases.

The sanitized suite also checks 5,940 address/size/alignment combinations against
an independent division/remainder model. It covers zero/default alignment,
invalid requested alignments, size/address rounding, sign-extended GPU ranges,
the end of `u64`, exact capacity and invalid requests with deferred GC owners.
The baseline accepts alignment `3` and a wrapping 1 TiB interval; standalone
`--alignment-probe` and `--overflow-probe` executable modes retain those failures.
`bounds-counterexamples.v` retains five compiled bounds variants and both
baseline failures. Its arguments are the heap runner, baseline allocator source
and a fresh external directory.

The Darwin measurement warms the allocator, then samples actual malloc live
blocks/bytes across three sets of 10,000 allocate/release/GC cycles. It requires
zero retained growth. `MallocNanoZone=0` selects the ordinary allocator because
the default nano-zone statistics showed an additional 512-block step during churn.
The original source retains exactly 10,000 blocks / 320,000 bytes per sample.
This measures the production V code on the host; kernel slab rates are unmeasured.

`--measure-padding` samples another 10,000 pairs with different alignments.
The pre-padding-fix source retains 655,360,000 VA bytes, 10,000 records and
619,008 malloc bytes (10,004 blocks) in this sample. The fixed source requires
zero retained VA, records, blocks and bytes. Standalone `--padding-probe` shows
the original one-pair loss of 65,536 VA bytes and one record.

The sanitized suite checks 9,216 combinations of heap-start offsets, three
alignment choices, all release masks and all six release orders. Its independent
candidate-enumeration model checks placement across leading alignment gaps and
collected interior holes. GC restores the highest remaining reservation end.
All released records are collected, including interiors. Live records retain their
addresses and metadata; ASan verifies retired records. Allocation-triggered GC
must recover an entire padded heap. `padding-counterexamples.v` takes the runner,
pre-padding-fix allocator and a fresh external directory; four compiled variants
exercise the original gap, wrong initial frontier, preceding-record start and
destruction of a live prefix.

`--measure-capacity` grows from a warmed two-entry table to 8,192 simultaneous
records, releases them, then restores the warmed table capacity in the fixture.
This removes the legitimately owned final buffer from the comparison. The
pre-capacity-fix source retains 12 discarded buffers / 90,160 malloc bytes;
the fixed source requires zero additional blocks and bytes. The sanitized suite
checks 13 growth boundaries, ASan poisoning of all 12 replaced buffers, stable
allocation pointees and concurrent locked statistics readers. The initial empty
table has no buffer to retire. `capacity-counterexamples.v` takes the runner,
pre-capacity-fix allocator and a fresh external directory; four compiled variants
catch original, missing, late and lost ownership of the pointer buffer.

`--measure-collect` releases 8,192 records below one live allocation. The old
suffix-only collector reclaims zero records; the current collector reclaims
8,192 malloc blocks / 393,216 bytes for the current record layout while preserving
the pin and frontier. The fixture queries `malloc_size` before collection rather
than assuming a historical record size.
Another 288 offset/alignment/four-pin release-order cases test interior deletion,
later allocation, highest release, repeated GC and complete reset. Collected
interior VA gaps are reusable below live allocations. GC and placement scan
tracked records; native runtime cost remains unmeasured.

Sanitizers check eight release masks, deferred ownership until GC, complete
released-record destruction, automatic GC, idempotence and two concurrent
statistics readers. Freed-pointer checks query ASan without dereferencing freed
records. The tests perform no GPU operation, firmware handshake or boot.

Compile `counterexamples.v` and pass the runner, original allocator source and a
fresh external directory. It retains four compiled negative cases: original
retention, missing free, early free and double free. Compile `check.v` for host
and native generated-C checks; `--selftest HOST_C` rejects five ownership/locking
mutations. `check.v --native CURRENT_C BASELINE_C` retains the earlier
metadata-reclamation proof for its original bundles. For historical bounds arithmetic,
compile `check-bounds.v`: `--host CURRENT_C` checks scalar arithmetic and
ownership, `--selftest CURRENT_C` rejects five guard/allocation mutations, and
`--native CURRENT_C BASELINE_C` additionally preserves the heap/GPU/event
lifetime bodies and owning layouts against the pre-bounds baseline. Those
historical native and GC host proof modes require their original bundles.
For the historical suffix-only GC, `check-padding.v --host CURRENT_C` checks exact
stack-only frontier restoration, unlink-before-free and locked readers;
`--selftest CURRENT_C` rejects eight ownership/locking/frontier/live-prefix
mutations. `--native CURRENT_C BASELINE_C` restores the exact old frontier line
and requires the remaining GC body, six heap bodies, ten owning declarations,
nine GPU lifetime bodies and ten event methods to match the pre-padding baseline.
The native build may omit unused statistics getters; host modes require both.
Historical checkers and their complete original bundles remain unchanged.

For current construction, `check-capacity.v --host CURRENT_C` also checks the
stack return, exclusive ownership flag and actual V runtime copy/free/transfer
path through the actual allocator free. `--selftest CURRENT_C` rejects eight
constructor, allocation, buffer-free and flag-transfer mutations.
`--native CURRENT_C BASELINE_C` reconstructs the
exact pre-capacity constructor, requires six other heap bodies and all ten
owning declarations, nine GPU lifetime bodies and ten event methods to match.
Its native mode and all `check-padding.v` modes retain their original contracts
and require the original complete bundles. Current construction host/selftest
modes remain applicable. Bounds C proof modes require their original bundles
because the reservation now calls the best-fit search wrapper.

For GC before hole-history bookkeeping, `check-collect.v --host CURRENT_C` requires the complete exact
stack-only descending collector and locked readers. `--selftest CURRENT_C`
rejects ten ownership, pin, scan, frontier and locking mutations. Native mode
compares six unchanged heap bodies, ten owning declarations, nine GPU lifetime
bodies and ten event methods with the pre-collection baseline. That native proof
mode requires its original bundle. Its host/selftest modes also require the
original pre-history collector; use `check-history.v` for current GC.
`collect-counterexamples.v` takes the runner, pre-collection source and a fresh
external directory; six compiled variants exercise the old source, suffix-only
collection, stopping at a live record, freeing live records, changing an interior
frontier and skipping records.

`--sanitize-bounds`, `--sanitize-padding`, `--sanitize-capacity` and
`--sanitize-collect` and `--sanitize-reuse` execute the named property under ASan/UBSan. Counterexample
runners use these modes so historical baseline sources reach their intended
property failure independently of newer GC semantics. The interval-bounds
negative now fails directly in the overflowing-interval probe. Historical checkers and
complete original bundles remain unchanged.

The reuse suite includes a full-capacity interior-hole probe, raw-hole ranking
before alignment padding, and 3,072 fragmented/aligned/deferred-release cases
against independent candidate enumeration. Pending released records occupy
their ranges until GC. Pointer rotation preserves VA order without moving
allocation records. Equal-size eligible holes now prefer the newest inserted
hole, following DRM MM's size-tree order. Placement scans tracked records; GC also compacts the
pointer table. Native cost remains unmeasured.

`check-reuse.v --host CURRENT_C` requires checked scalar placement helpers,
identical pre/post-GC range limits, a monotonic high frontier and stack pointer
rotation around one explicit record owner. Its selftest rejects twelve bounds,
retry, ranking, pending-owner, frontier, sorting and allocation mutations. Native
mode compares six unchanged heap bodies, ten owning layouts, nine GPU lifetime
bodies and ten event methods against the pre-reuse baseline. Reference mode takes
Asahi `alloc.rs` and the pinned `drm_mm.c`. `reuse-counterexamples.v` takes the
heap runner, pre-reuse allocator and a fresh external directory; eight compiled
variants exercise capacity loss, ranking, ordering and deferred collection.

`tlb-reuse-run.v` always enables ASan/UBSan with `-gc none -manualfree`, matching
the kernel, and combines the production allocator
and page tables with the existing TLBI fixture. Two hundred uncached global/ASID
cycles verify old leaves are invalidated before reuse, new mappings name the new
backing, live pins stay mapped and all page tables are released. Optional
`AGX_HEAP_TLB_BINARY` and `AGX_HEAP_TLB_C` retain artifacts externally. These tests
replace privileged instructions and do not execute firmware cache invalidation.
ASan also verifies collected metadata is poisoned and live pin metadata survives.

`--sanitize-history` runs three targeted newest-hole/split/alignment probes and
9,216 seeded split/coalesce/deferred-release steps. The independent model keeps
reservations in creation order and holes in chronological order, enumerates
candidate addresses and infers containing intervals by pairwise comparisons.
`--sanitize-history-invariants` also checks every production rank against that
chronological list after each step. Ranks stay bounded by the number of holes;
there is no lifetime counter to wrap and no new metadata allocation.
`history-counterexamples.v` retains eight compiled negatives, including the
previous allocator, oldest/lowest ties, reversed split ordering, stale coalescing,
unbounded counts and omitted rank compaction. Each must fail its designated
runtime assertion; compile failures do not count as rejection.

For generated C before FIFO collection, use `check-history.v --host C`, `--selftest C`,
`--native C BASELINE_C` or `--reference DRM_MM_C`. Fourteen selftest mutations
cover ranking, compaction, bounds, coalescing and ownership. Native mode removes
only the exact scalar GC history block, then requires the original collector
body to match; owning declarations differ only in three scalar rank fields.
GPU and event ownership bodies remain unchanged. Current construction checks
in `check-capacity.v` still apply. The `check-reuse.v` and `check-collect.v`
native/host proof modes now retain their historical contracts and require their
original complete bundles; they were not weakened for the new history fields.

The tie rule matches the same insertion/removal stream. Collection follows
release FIFO order and supports a count limit. G13 shared and shared-read-only
heaps now release immediately; private and GPU-read-only heaps retain deferred
release. Manager collection triggers, backing/accounting behavior and native
performance remain different or unqualified.

`--sanitize-garbage` runs 19,440 release-permutation/count/offset cases and 10,240
mixed partial-collection/reuse steps. It compares pending counts, rounded bytes,
every bounded release rank and every hole rank with an independent pending-address
FIFO and chronological hole list. Count zero, all six-release permutations,
oversized counts, duplicate/unknown releases, partial collection, live pins and
deferred ownership are covered. `--sanitize-garbage-probe` uses only the established
API so the previous allocator reproduces its descending-VA mismatch at runtime.
`--sanitize-garbage-limits` isolates bounded collection for compiled negatives.

`garbage-counterexamples.v` rejects ten compiled policy/accounting/rank variants.
`check-garbage.v --host C`, `--selftest C`, `--native C BASELINE_C`, and
`--reference ALLOC_RS KVEC_RS DRAIN_RS` check scalar bookkeeping, fifteen C
mutations, unchanged native ownership and the pinned upstream vector/drop path.
The historical `check-history.v` contract now also requires its original complete
bundle; it was not changed for the FIFO collector. Existing heap/padding/collection
negative generators target the new FIFO selector. The ownership measurement
checks the actual malloc block size; its original-source case still requires
10,000 blocks / 320,000 bytes. Padding/collection matrices now check live byte
counts before dereferencing retained records, catching a removed live owner early.

The old default-Boehm heap/TLB fixture crashed with ASan fake-stack detection;
the same binary passed with fake stacks disabled, and a traced variant passed.
Those diagnostics are retained. Acceptance uses the kernel's manual memory model
with fake-stack detection enabled and explicit freed-metadata checks. Default
Boehm/ASan interoperability is not qualified by this fixture.

`--sanitize-policy` checks immediate retirement and interior reuse without GC,
the ordinary constructor's deferred default, 4,320 policy/offset/release-order
cases and 20,480 mixed policy/reuse/partial-GC steps. The independent interval,
FIFO and hole-history model checks pending statistics, bounded ranks and live
record addresses. ASan verifies that only immediate owners are poisoned on
release. `--measure-policy` requires zero retained records, blocks and bytes
across three 10,000-operation runs with no explicit GC. The heap/TLB fixture
checks 400 cycles across both policies, global mappings and per-ASID mappings.

`policy-counterexamples.v HEAP_RUNNER BASELINE_ALLOCATOR FRESH_EXTERNAL_DIRECTORY`
rejects seven compiled policy variants at their designated runtime assertions.
`check-policy.v --host C`, `--selftest C`, `--native C BASELINE_C` and
`--native-selftest C BASELINE_C` check the construction-time flag, locked one-owner
collection and direct return without reading retired aliases. Ten host and four
native C mutations exercise policy forwarding, defaults, class selection and
ownership gates. Native comparison requires the existing collector and GPU
unmap, invalidation, rollback and lifetime bodies to match the baseline.
