# Shader value arguments and builtin checkpoint — 2026-11-16

Source revision: `fb13fc744c8452d853acca86cdfb4c4202484546`.

The memory interpreter accepts interleaved buffer and typed value arguments
through ordinary and prepared execution. Scalars are i1..i64, half or float;
fixed vectors have 1..16 lanes. `IRMemoryBinding.values` supplies raw u64 lane
words, masked to the declared width. Canonical value bindings have no buffer
data, offset, writable flag or nondefault base alignment. Buffer bindings have
no value words. Validation precedes writes and all values are captured before
execution, including when their backing memory aliases output. Caller arrays
remain borrowed; execution owns and frees the snapshots on success and error.

Software Metal binds `air.thread_position_in_grid` as uint or uint3 and
`air.thread_index_in_threadgroup` as uint. Values are zero for the existing
1x1x1 grid/group, with no encoder buffer slot required. Each semantic may appear
once. Exact integer shapes, optional matching type names and plain builtin
metadata are required; unsupported qualifiers and types reject. Arbitrary
by-value uniforms, other builtins, larger grids and dynamic GEP indices remain
outside the runtime profile.

AddressSanitizer and UndefinedBehaviorSanitizer checks pass:

- 35,904 native LLVM cases across 1,122 scalar/vector shapes, compared through
  both execution APIs (71,808 complete interpreter-output comparisons). Inputs
  include high-bit noise and explicit floating zero/infinity/NaN/subnormal bits.
- 16,830 prepared binding refusals leave output untouched. Additional
  controls cover unsupported shapes, 65 arguments, dynamic GEP/inttoptr refusal,
  aliased value snapshots, bufferless functions, 256 masked branch/PHI inputs
  and 256 alternating poison/recovery calls.
- Eight existing checker programs and 23 focused legacy vector suites pass,
  including prepared execution, native vector memory and scalar-memory matrices.
- Both runtime hashing modes pass six builtin dispatches and 38 invalid builtin
  pipelines per mode, across two drained runtimes. Sparse/reordered metadata,
  output offsets, reference release, both dispatch selectors and padding pass.
  Fresh processes of the same verified executable also pass 80 existing vector
  and 16 prepared-reuse dispatches across the two hashing modes.

The initial negative address-space fixture used an integer with pointer-only
metadata, invalidating the entire AIR entry table. Its assertion then continued
into the broad test suite; that diagnostic process was terminated (143). A
second run retained the explicit error before correction. The corrected fixture
uses a pointer so entry parsing succeeds and builtin-specific rejection is
checked separately. Those attempts remain preserved; only `software-builtins-r3`
qualifies builtin behavior. No complete broad runtime-suite pass is claimed.

Evidence is retained at `/Users/alex/Library/Caches/vinix-ios/value-arguments-20261116-r1`; its verified archive is `/Users/alex/Library/Caches/vinix-ios/value-arguments-20261116-r1.tar.gz`. Complete typed inventory and archive
logical-byte/metadata comparison pass. Originals remain retained; no restoration
replay is claimed.

- Archive SHA-256: `f75e5fce4c637854412add3d0dcc9e08cd7f35c3ad9be57aa1b9fd2e1496405e`.
- Inventory SHA-256: `84644f4ea8a7fe6863759c93faa4de7b2935eb47d3408151360f2a715acaa212`.
- Committed source archive SHA-256: `5cae32be39e066f73cc108a0f8a90f92d3b0d32bd484e94f0a8f51ac1d2c6dfc`.

Final results are in `values-recovery-results`, `regression0` through
`regression7`, `legacy-focused`, `software-builtins-r3` and `vector-runtime`.
The bundle includes comparisons, IR/bitcode, generated C, binaries, commands/logs,
compiler/library identities and reviewed source hashes compared with the feature
commit. Reproduce with `tests/ios/air-memory-values.v LLVM_AS FRESH_EXTERNAL_DIR`
and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR builtins`, using the
repository module paths and retained captured host toolchain. Local dependencies
remain referenced; this is not a hermetic rebuild.

[Apple thread attributes](https://developer.apple.com/documentation/metal/creating-threads-and-threadgroups)
provide the position semantics. Only synthetic AIR fixtures execute here. LLVM
23.1.5 JIT code is uninstrumented, leak detection is disabled and retained heap
is unmeasured. This adds no GPU execution, rendering, guest launch or verified
Fortnite frame.
