Compile `run.v` externally, then run `--measure` or `--sanitize`. The runner
compiles the complete production allocator and `kernel/lib/math.v` with
`-gc none -manualfree`. Its lock service uses a real host mutex. Optional
`--allocator-source PATH` selects a retained baseline or counterexample.
`AGX_HEAP_TEST_C` and `AGX_HEAP_TEST_BINARY` retain output outside Git.
Temporary fixtures are removed before the runner exits, including negative cases.

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
mutations. `--native CURRENT_C BASELINE_C` proves the GC change is exactly one
unlink-before-free operation while other allocator/GPU/event bodies and owning
layouts remain unchanged. The native build may omit unused statistics getters;
the host check always requires both.
