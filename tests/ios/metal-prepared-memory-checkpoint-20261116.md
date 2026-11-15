# Prepared software Metal execution checkpoint — 2026-11-16

Source revision: `86e2b3104e88b850642cdfdc101b9a7d2a4289bf`.

Software Metal pipelines now prepare their memory function once and reuse the
validated profile for deferred dispatches. The public `IRPreparedMemoryFunction`
captures the function and borrowed indexes privately and returns argument
requirements as copies. Each run still checks current buffer bounds, offsets,
alignment, permissions, step budgets and actual memcpy overlap before writes.
Execution scratch remains fresh per run. The ordinary API still preflights each
call; its shared execution body is byte-identical to the previous implementation.

The prepared function owns only its profile arrays. All borrowed indexes and
backing bitcode must remain alive and immutable until the last run. Free the
preparation exactly once before freeing those indexes. Pipeline cleanup and
early-error defers retain that order; the object does not deep-copy or freeze
caller storage. Valid LLVM IR remains a precondition.

AddressSanitizer and UndefinedBehaviorSanitizer validation passed:

- 28,928 prepared-versus-ordinary scalar/vector byte comparisons with independent
  expected bytes, covering i1..i64, half/float and all supported vector shapes.
- 3,314 counted controls for changing inputs, branches/PHIs, memory intrinsics,
  poison results, bindings, budgets and argument indexes. Additional checks
  cover metadata copies, recovery after poison failures, aliasing, alignment,
  readonly address space 2, invalid cold blocks, empty and uninitialized objects.
- Existing native vector memory regression: 61,440 exact LLVM comparisons, 640
  poison/undef/freeze cases, 8,640 guard refusals and its remaining controls.
  The scalar-memory regression passes 16,896 copies; vector-memory, switch and
  memory-intrinsic units also pass.
- Normal and deterministic Swift hashing modes each pass 40 existing vector
  dispatches plus eight dispatches reusing prepared pipelines. Reuse changes
  buffer offsets, reads deferred input bytes and preserves disjoint output
  snapshots after caller references are released. Both modes drain two runtimes.

A five-round alternating microbenchmark executes a function with an unvisited
2,048-instruction block 100 times per sample. Median ordinary time was
61.778084 ms versus 1.433666 ms prepared (43.1x) in this sanitizer build. Raw
nanosecond samples are retained. This synthetic result does not measure an
application or Fortnite, and preparation is outside the prepared timing.

Evidence is retained at `/Users/alex/Library/Caches/vinix-ios/prepared-memory-20261116-r1`; the verified archive is `/Users/alex/Library/Caches/vinix-ios/prepared-memory-20261116-r1.tar.gz`. Complete typed inventory and archive
logical-byte/metadata comparison pass. Originals remain retained; no restoration
replay is claimed.

- Archive SHA-256: `43e1a62adf2d0a35dabbf247a84ef7ec7749c18fe4016e8152b33e18b8f0a574`.
- Inventory SHA-256: `f535e2aaa399cfc13f01ef8e6334658e29f15bcaf5fb041b0cfd61ed04f0867a`.
- Committed source archive SHA-256: `3a5849e8786ea78ce27ef7c1a0368b6c833ebf4d3874c65dd38c6e99b2c8e353`.

`check-recovery-results` contains the final prepared test and benchmark.
`regression0` through `regression4` and `software` retain the successful
regressions/runtime checks. The bundle contains source, comparisons, IR/bitcode,
generated C, binaries, commands/logs, compiler/library identities and reviewed
source hashes checked against the feature commit. Reproduce the prepared test
with `tests/ios/air-memory-prepared.v LLVM_AS FRESH_EXTERNAL_DIR` and runtime
checks with `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR vector-memory`,
using the repository module paths and retained captured host toolchain.

Local toolchain/library dependencies remain referenced; this is not a hermetic
rebuild or full runtime-suite qualification. The LLVM JIT regression reference
is uninstrumented. Leak detection is disabled and retained heap is unmeasured.
Dispatch remains one CPU invocation. No GPU commands, rendering, guest launch
or Fortnite frame is newly qualified.
