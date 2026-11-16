# Software compute grids checkpoint — 2026-11-16

Source revision: `41bc6c99f5874e69b9422cf245c515575bc94783`.

Software Metal executes nonempty one-dimensional grids of up to 4,096
invocations, with 1..256 threads per group. Height/depth must be one.
`dispatchThreads` uses the exact thread count, including partial final groups;
`dispatchThreadgroups` checks the group-count product before multiplying.
Zero/multidimensional/oversized shapes and products beyond the invocation or
1,000,000 conservative instruction-step budget reject during encoding.
The pipeline reports maximum group size 256 and execution width one.

Grid-position builtins receive `x` or `(x,0,0)`; local indices receive the
position within the current group. Their words occupy distinct borrowed slices
of one owned four-word temporary, freed on every dispatch exit. Dispatch
snapshots now retain geometry alongside the existing pipeline/buffer/offset
references; their ownership and release paths remain unchanged.

At commit, every invocation's bindings and indexed addresses validate before
this dispatch writes, including cold blocks and the last partial group. Address
failures leave this dispatch's output untouched. Invocations then run serially
in increasing grid position with fresh interpreter scratch. Arithmetic poison
may leave earlier invocation writes visible; earlier commands can also have
written. Larger/multidimensional grids, computed SSA indices, barriers,
threadgroup memory, GPU concurrency and rendering remain unsupported.

AddressSanitizer and UndefinedBehaviorSanitizer checks pass on macOS ARM64:

- Both hashing modes each complete 338 dispatches covering 172,358 successful
  invocations, for totals of 676 and 344,716. Exact output and untouched padding
  checks cover scalar/reordered arguments, uint3 coordinates, local-index reset,
  both selectors, partial/maximal grids, geometry/offset snapshots, deferred
  buffer reads and two drained runtimes per mode.
- Each mode checks six cold-address/alignment/poison command failures, 102
  geometry/budget controls and five fresh-process encoding refusals, including
  hostile u64 dimensions, product bounds and the exact instruction budget.
  Cold/alignment failures preserve all output; poison preserves only earlier
  successful invocation writes.
- Fresh processes of the same verified executable pass 12 existing builtin
  dispatches, 76 invalid builtin pipelines, 80 existing vector dispatches and
  16 prepared-pipeline reuse dispatches across both hashing modes.
- The indexed-memory checker passes 37,788 exact native LLVM cases, 15,460
  refusals and its boundary controls. Prepared memory passes 28,928 byte
  comparisons and 3,314 changing-input/budget/recovery controls.

Only `software-grids-r4` qualifies the final grid fixture. Initial V generation
rejected an immutable assignment and reserved identifier; the next attempt
exposed the captured compiler dropping an indirect-call cast for a conditional
selector expression. A V helper now passes evaluated arguments through the
existing typed ABI cast. A third attempt correctly refused excessive work but
failed its expected diagnostic, which omitted one word. All failed logs and
generated output remain preserved.

Evidence is retained at `/Users/alex/Library/Caches/vinix-ios/compute-grids-20261116-r1`;
its verified archive is `/Users/alex/Library/Caches/vinix-ios/compute-grids-20261116-r1.tar.gz`.
Complete typed inventory and archive logical-content/metadata comparison pass.
Originals remain retained; no restoration replay is claimed.

- Archive SHA-256: `62c252df6988b7bedfd2751fd264fd4c4c779331ec89c85a9ba4463456081607`.
- Inventory SHA-256: `d0005e97a841d4901a03149823fc36620ded5246e76bc9c331d0bb82d9eb14c4`.
- Committed source archive SHA-256: `b014bcd58e4152f5b09e4363e6e3f2700903752cfe51e6e63361870b17704db3`.

The bundle contains comparison rows, synthetic AIR fixtures, generated C,
commands/logs, tool/executable identities, ownership review and reviewed source
hashes checked against the feature commit. Reproduce with
`tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR grids` using repository
module paths and the retained captured toolchain. Local dependencies remain
referenced; this is not a hermetic rebuild. Leak detection is disabled, retained
heap is unmeasured and native LLVM JIT code is uninstrumented. No complete broad
runtime-suite pass or new GPU/guest/Fortnite frame is verified.

[Apple's grid-size documentation](https://developer.apple.com/documentation/metal/calculating-threadgroup-and-grid-sizes)
defines full/partial threadgroups. These checks exercise synthetic AIR on the
CPU and do not establish native GPU execution or parallel-memory ordering.
