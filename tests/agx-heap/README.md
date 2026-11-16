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

Sanitizers check eight release masks, delayed interior ownership, suffix-only
destruction, automatic GC during allocation, idempotence and two concurrent
statistics readers. Freed-pointer checks query ASan without dereferencing freed
records. The tests perform no GPU operation, firmware handshake or boot.

Compile `counterexamples.v` and pass the runner, original allocator source and a
fresh external directory. It retains four compiled negative cases: original
retention, missing free, early free and double free. Compile `check.v` for host
and native generated-C checks; `--selftest HOST_C` rejects five ownership/locking
mutations. `check.v --native CURRENT_C BASELINE_C` retains the earlier
metadata-reclamation proof for its original bundles. For current bounds code,
compile `check-bounds.v`: `--host CURRENT_C` checks scalar arithmetic and
ownership, `--selftest CURRENT_C` rejects five guard/allocation mutations, and
`--native CURRENT_C BASELINE_C` additionally preserves the heap/GPU/event
lifetime bodies and owning layouts. The native build may omit unused statistics
getters; `check.v --host` always requires both. Historical proof modes and their
complete original bundles remain unchanged.
