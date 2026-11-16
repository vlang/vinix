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
model saves each reservation frontier before allocation and requires GC to
restore that frontier, including leading padding. Live prefixes retain their
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

Sanitizers check eight release masks, delayed interior ownership, suffix-only
destruction, automatic GC during allocation, idempotence and two concurrent
statistics readers. Freed-pointer checks query ASan without dereferencing freed
records. The tests perform no GPU operation, firmware handshake or boot.

Compile `counterexamples.v` and pass the runner, original allocator source and a
fresh external directory. It retains four compiled negative cases: original
retention, missing free, early free and double free. Compile `check.v` for host
and native generated-C checks; `--selftest HOST_C` rejects five ownership/locking
mutations. `check.v --native CURRENT_C BASELINE_C` retains the earlier
metadata-reclamation proof for its original bundles. For bounds arithmetic,
compile `check-bounds.v`: `--host CURRENT_C` checks scalar arithmetic and
ownership, `--selftest CURRENT_C` rejects five guard/allocation mutations, and
`--native CURRENT_C BASELINE_C` additionally preserves the heap/GPU/event
lifetime bodies and owning layouts against the pre-bounds baseline. Those
historical native and GC host proof modes require their original bundles.
For current GC, compile `check-padding.v`: `--host CURRENT_C` checks exact
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
`check-padding.v --native` retains its original pre-padding baseline contract;
its host/selftest modes continue to check the current GC and locked getters.
