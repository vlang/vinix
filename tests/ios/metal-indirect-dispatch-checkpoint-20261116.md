# Indirect compute dispatch checkpoint — 2026-11-16

Source revision: `03858fe3f05ed3fd5e01624b2bb36f157d033a9b`.

Software Metal implements
`dispatchThreadgroupsWithIndirectBuffer:indirectBufferOffset:threadsPerThreadgroup:`.
Encoding retains a same-device buffer, checks a four-byte-aligned 12-byte range,
and snapshots group dimensions and ordinary pipeline/buffer bindings. Execution
reads three UInt32 group counts after earlier commands, copying them once to
a fixed stack array confirmed in generated C. A zero axis skips execution.
Nonzero counts pass existing volume and instruction budgets before any writes;
output addresses still prevalidate across every invocation. Invalid counts fail
the command. Encoding checks at least one group even for eventual zero grids.

The shared recording helper preserves direct-dispatch snapshots. The indirect
reference is independently retained once per recorded command and released once
on disposal, including error/zero work. Encoder indirect fields stay zero. No
execution values persist into another dispatch. Retained heap is unmeasured.

AddressSanitizer and UndefinedBehaviorSanitizer checks pass on macOS ARM64 in
normal and deterministic hashing, each with two drained runtimes:

- 40 nonempty indirect dispatches cover 55,192 invocations. Counts supplied
  after encoding by CPU writes, preceding blits and preceding compute dispatches
  produce exact flattened 3D outputs with preserved prefix/suffix padding.
  Maximum 4,096-invocation work and output offset snapshots pass.
- Twelve zero-axis grids complete without writes, including huge unused axes.
  Twelve deferred volume/bounds failures preserve all dispatch output bytes.
  Twenty-four encoding refusals cover six offset/range/nil/group cases.
  Caller buffer references are released before commit.
- Existing builtin, direct grid, multidimensional grid, computed-index, size/
  image-readback, group-coordinate, vector-memory and prepared-reuse checks pass
  in fresh processes of the same executable in both hashing modes.

Evidence: `/Users/alex/Library/Caches/vinix-ios/indirect-dispatch-20261116-r1`.
Verified archive: `/Users/alex/Library/Caches/vinix-ios/indirect-dispatch-20261116-r1.tar.gz`.
Complete typed inventory and archive logical-content/metadata comparison pass.
Originals remain retained; no restoration replay is claimed.

- Archive SHA-256: `16147d3eec1244038d2b5ed030302a9e9d6cea4c2a5dfd560a8902cca004f49d`.
- Inventory SHA-256: `6cb4ecaed8bd5e5c1653853792906800783b718b96f92e02837e7cd939d97d7f`.
- Committed source archive SHA-256: `9c23cd9419592ac7b356a4916c2622adfe1fcf903c66736f9a1146d81d9cb1b1`.

`software-indirect` preserves the qualifying executable, generated C, IR/bitcode,
comparisons and command logs. The bundle also contains regressions, tool hashes,
ownership review and source hashes compared with the feature commit. Reproduce
with `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR indirect` using the
repository module path and retained captured toolchain. Local dependencies remain
referenced; this is not a hermetic rebuild. Leak detection is disabled. No full
broad runtime suite, GPU rendering, guest launch or new Fortnite frame is verified.
Indirect command buffers and indirect dispatchThreads remain unsupported.

The argument layout follows [Apple’s indirect dispatch documentation](https://developer.apple.com/documentation/metal/mtldispatchthreadgroupsindirectarguments).
