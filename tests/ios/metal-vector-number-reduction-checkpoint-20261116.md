# Software Metal number-preferring reduction checkpoint — 2026-11-16

Source revision: `c4e25153a71b32ddd052d2801da9dbd6f5996057`.

The AIR interpreter executes ordinary direct `llvm.vector.reduce.fmin` and
`fmax` calls for fixed 1..16-lane half/float vectors. Numeric extrema ignore
NaNs when a number is available and order -0 below +0. A fixed left fold uses
the existing scalar minnum/maxnum policy: signaling NaNs are treated as quiet.
This chooses a permitted refinement of the [LLVM reduction and scalar
comparison contracts](https://llvm.org/docs/LangRef.html#int-vector-reduce-fmin).
Multiple all-NaN lanes produce the preferred quiet NaN; a single lane preserves
its raw bits. Poison propagates, executed undef rejects eagerly, and existing
source/result freeze behavior applies. Mixed, void and ordinary/prepared
memory APIs accept the calls; integer-only execution and floating address
dependencies remain excluded. Calls cost N+1 validation work units and no
vector construction slot. Existing declaration, type, attribute and shared
limits remain enforced. Fast-math, scalable/wider formats and newer
fminimumnum/fmaximumnum reduction names remain excluded.

The sanitized maintained checker passes 64 operation/format/count shapes,
10,240 directed cases and 262,144 sweep samples. Directed results comprise
8,704 exact/frozen values, 512 poison stores and 1,024 strict undef failures.
Scalar and both memory APIs check bytes, markers, shifted bindings,
nonmutating validation and reused prepared plans. All 10,240 short budgets
reject before writes; 64 integer-only controls reject floating bodies.
Eighty-two controls cover vector arguments/loads, composition, discarded/cold
states, metadata/type/name guards, floating address exclusions, 4,096 versus
4,097 vector constructions and exactly 1,000,000 versus 1,000,001 lane-work
units in memory/void APIs. Scalar results add no vector storage slots.

All 272,384 native LLVM comparisons pass: 271,588 exact non-NaN values and
796 NaN-class comparisons. Native references execute defined replacement
inputs with signaling NaNs quieted first; interpreter inputs retain their raw
encodings. This verifies the chosen quiet-NaN refinement, not agreement with
every legal native result for raw signaling NaNs. Native NaN payload/sign
differences are permitted; interpreter bytes must match its chosen oracle.
The sweep covers every half encoding and deterministic float patterns with
two zero lanes, including NaNs that become numeric zero under these reductions.

The final unit suite passes 4,194,304 independent NaN-skipping ordered-key
values across both formats, operations and every lane count, including all
half encodings, upper-bit masks and source snapshots. Another 1,148 checks
cover every poison/undef lane and eager mixed states. Two hundred directed
checks permute quiet/signaling NaNs, numeric extrema and signed zeros, and
verify that earlier NaN/poison does not hide later undef. Rounding, floating
minimum/maximum, sequential sum/product and integer reduction units pass.
All 34,688 declaration cache identities are distinct; 64 appended identities
preserve existing keys and add 512 stack bytes per cache.

Full regressions pass 272,384 floating minimum/maximum native/oracle values,
272,384 ordered sum/product LLVM intrinsic/scalar-chain comparisons and
40,032 integer reduction native/oracle values, with 82, 161 and 119 controls
respectively. Integer reduction address, carry-less multiply and scalar/vector
bitcast address controls pass 150, 650 and 67 checks. Computed-index regression
passes 26,029 native exact cases, 50,771 prewrite refusals and 4,096 vector
coordinate cases; prepared memory passes 28,928 byte comparisons and 3,314
changing-input/recovery/bounds/budget/metadata controls. Other full matrices
were not repeated. The former fmin refusal fixture now checks unsupported
fminimumnum instead, while positive fmin coverage lives in the new checker.

Fresh normal and deterministic software Metal processes each pass 106 geometry
dispatches, 136 shader images, 235,978 checked invocations, 106 rejected
pipelines and two prewrite bounds failures. The new image reduces
`<quiet NaN, x, y>` with both operations and sums the extrema into its red
channel. Tests cover queued dispatch, buffer/texture RGBA8 readback, padding,
both dispatch selectors, clipped groups, repeated commits and two drained
runtimes per process.

Generated checker and host C retain fixed by-value vector sources and scalar
accumulators, using existing scalar comparison and ownership paths. No new
arrays occur in the reduction wrapper or canonical-name parser. The checker
contains two declaration caches and the focused host its used memory cache.
No evaluator kind, node field, escaping pointer, lifetime extension or free
path is added. Existing allocations and error paths remain. Heap retention
was not measured, leak detection was disabled, and native JIT code was not
sanitizer instrumented. Broad runtime and kernel/guest builds were not repeated.
All qualified runs pass; initial and expanded unit artifacts are retained.

This is CPU software Metal evidence. Native GPU execution, guest/Fortnite
launch gates, a Fortnite frame and complete Metal support remain unverified.

## Retained evidence

Canonical original workspace (retained in place):
`/Users/alex/Library/Caches/vinix-ios/vector-number-reduction-20261116-r1`.

Complete archive:
`/Users/alex/Library/Caches/vinix-ios/vector-number-reduction-20261116-r1.tar.gz`

- Archive SHA-256: `46d9477878f5ee3808c0dd3c6aa65a6a4aee101d62f602506e29b00e55ec5a2e`.
- Complete typed inventory: sibling `.inventory.json`, SHA-256 `e5a118b49ede1aa177518e2352c9bd398a827f711217447b4c8017091f60866c`.
- Source snapshot: workspace `source.tar`, SHA-256 `93f9e75908e77202f0a5f168201826516324e356b81181be21a7cafdb169bab6`.

Inventory and archive checks compare the complete workspace's paths, types,
modes, links, sizes and logical file hashes, including root mode. Originals
remain retained; this records integrity without claiming restoration replay
or authorizing deletion. Commands, source revision, compiler/executable
identities, LLVM target/features, generated C and sanitizer logs are in the
bundle. Sealing commands/statuses are siblings outside the sealed workspace.
