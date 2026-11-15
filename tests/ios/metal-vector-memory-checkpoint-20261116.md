# Vector buffer memory checkpoint — 2026-11-16

Source revision: `c9b03edcc0f061f09287c7a2cdb1ff6830c491fa`.

The software Metal memory interpreter now loads and stores fixed vectors with
1..16 lanes: i8/i16/i24/i32/i40/i48/i56/i64, half and float. Loaded vectors
compose with existing vector operations. Transfers preserve little-endian raw
bits, including floating zeros, infinities, NaNs and subnormals. Loads capture
complete snapshots across overlapping buffer bindings. Stores validate every
lane before writing; poison or undef rejects the whole store while preserving
earlier instructions. Bounds, alignment, permissions, cold-block validation and
existing work/result limits apply. Vector GEP strides retain allocation padding.

AddressSanitizer and UndefinedBehaviorSanitizer checks pass:

- 32,768 independent byte round trips and every poison/undef/invalid lane
  position, including final-lane refusal without partial writes.
- 61,440 exact native LLVM comparisons across all 160 supported shapes: copies,
  bitwise inversions and overlapping snapshots, with explicit floating edge bits.
- 640 decoded poison/undef/freeze cases and 8,640 binding, step-budget, metadata
  and void-API refusals. Additional controls cover unsupported shapes, inactive
  blocks, address space 2, constant stores, explicit alignment, vector GEP
  stored/allocation sizes and the 4,096/4,097-result boundary.
- Five existing unit programs and the scalar-memory checker, including 16,896
  scalar copies. All 23 focused legacy vector control suites pass. Their former
  ordinary-vector-load rejection cases now use volatile vector loads.
- The focused Objective-C software backend passes in normal and deterministic
  Swift hashing modes: 40 deferred dispatches per mode across two drained
  runtimes, with 20 successful and 20 poison/undef failed commands per mode.
  This checks actual message-send ABI, pipeline creation, buffer bindings,
  deferred input reads, nonzero output offsets, untouched padding and error status.

Reproduction entry points are `air-memory-vector.v LLVM_AS FRESH_EXTERNAL_DIR`,
`vector-memory-regressions.v V_COMPILER LLVM_AS FRESH_EXTERNAL_DIR`, and
`metal-software-checks.v FRESH_EXTERNAL_DIR vector-memory`, under `tests/ios/`.
Use the relevant repository module paths; the host harness requires the retained
captured toolchain at `build/ios/fortnite/ns-calendar-checks/toolchain`. The full
`software` and `default` entry points remain available. The first broad host run
was deliberately terminated (143) because of its cost; no full runtime-suite
pass is claimed. The initial focused constant-extraction batch was too small
for its existing count assertion; the corrected runner preserves the complete
six-width batch and passes. Both diagnostic attempts remain in the bundle.

Evidence is retained at `/Users/alex/Library/Caches/vinix-ios/vector-memory-20261116-r1`; the verified archive is `/Users/alex/Library/Caches/vinix-ios/vector-memory-20261116-r1.tar.gz`. Complete
typed inventory and archive logical-byte/metadata comparison pass; originals
remain retained. This is integrity verification, without restoration replay.

- Archive SHA-256: `ca322d1467d79fff67a5e9022d339ab93d0fedaa09f0d52d932329e7b966e6af`.
- Inventory SHA-256: `2a4fa5acbf3d5f9d34a4c0be158acbe64b4d83035aee3609a05fe83e32da2bac`.
- Committed source archive SHA-256: `13822167ee39e4aef5e2ab80ef8aaf4a8a6606baf3b603175aebd25bc2d1189f`.

`reference-edges-results`, `legacy-focused-r2`, `regression0` through
`regression6`, and `software-focused` hold the successful final checks. The
bundle contains comparisons, IR/bitcode, generated C, binaries, commands/logs,
tool identities and reviewed source hashes checked against the feature commit.
Local toolchain/library dependencies remain referenced; the bundle is not a
standalone hermetic build. LLVM 23.1.5 JIT code is uninstrumented; leak detection
is disabled and retained heap is unmeasured. Production adds no per-access
allocation or execution array.

[LLVM memory semantics](https://llvm.org/docs/LangRef.html#memory-access-and-addressing-operations)
provide the native reference contract. Non-byte-aligned/scalable vectors, vector
arguments/returns and vector PHIs remain unsupported. Dispatch is still one
CPU invocation. No GPU commands, rendering, guest launch or Fortnite frame
is newly qualified.
