# Software Metal modern number reduction checkpoint — 2026-11-16

Source revision: `563118a4bf44212aeaf2a0d9a919621fa56f7d0e`.

The AIR interpreter executes ordinary direct
`llvm.vector.reduce.fminimumnum.vNf16/f32` and `fmaximumnum` calls for fixed
1..16-lane half/float vectors. Both NaN classes are ignored when a numeric lane
exists, with -0 below +0, following the [LLVM comparison
contract](https://llvm.org/docs/LangRef.html#int-vector-reduce-fminimumnum).
Multiple all-NaN lanes produce the preferred quiet NaN; a single lane preserves
its raw encoding. The existing scalar helpers and fixed reduction fold provide
these semantics. All executed lanes remain observable: poison propagates and
undef rejects eagerly, including after an earlier NaN or poison. Existing
source/result freeze behavior applies. Mixed, void and ordinary/prepared
memory APIs accept the calls; integer-only execution and floating address
dependencies remain excluded. Calls use N+1 validation work units and no
vector construction slot. Declaration/type/attribute and shared bounds remain
enforced; fast-math, scalable vectors and wider formats remain excluded.

The installed LLVM recognizes scalar minimumnum/maximumnum, but returns zero
intrinsic IDs for the modern vector reductions. The checker records that
capability and JITs a separate module containing recognized scalar folds only.
Synthetic modern vector declarations exercise the interpreter's parser,
validation and dispatch. This does not claim native execution or verifier
recognition of the vector reduction intrinsics in this LLVM installation.

`tests/ios/air-vector-modern-number-reduction.v` passes with ASan/UBSan:

- 272,384 raw-input comparisons against native scalar folds and an independent
  integer-ordering oracle: 271,588 exact non-NaN values and 796 NaN-class
  comparisons. Signaling NaNs reach the native reference unchanged. Native
  NaN payload/sign differences are allowed; interpreter bytes must match its
  explicit choice. Native references replace indeterminate lanes with defined
  values; interpreter poison/undef/freeze checks remain separate.
- 64 operation/format/count shapes, 10,240 directed cases and 262,144 sweep
  samples. Directed results comprise 8,704 exact/frozen values, 512 poison
  stores and 1,024 strict undef failures. Scalar and both memory APIs check
  every byte, marker ordering, shifted bindings, nonmutating validation and
  reused plans. The sweep covers every half encoding and deterministic float
  patterns with two zero lanes.
- All 10,240 short budgets fail before writes; 64 integer-only controls reject.
  Eighty-two controls cover vector arguments/loads/composition, discarded/cold
  states, metadata/type/name guards, floating address exclusions, 4,096 versus
  4,097 constructions and exactly 1,000,000 versus 1,000,001 validation work
  units in memory/void APIs. Scalar reduction results consume no vector slots.

The modern unit suite passes 4,194,304 independent encoding checks across
both formats, operations and every lane count, including all half encodings,
raw NaNs, upper-bit masks and source snapshots; 1,148 poison/undef lane and
mixed-state checks; and 200 directed NaN/signed-zero permutations and eager
state checks. Legacy number, NaN-propagating minimum/maximum, ordered sum/product,
integer reduction and rounding units pass. All 34,752 cache identities are
distinct. The 64 new identities preserve existing keys and add 512 stack
bytes per declaration cache, keeping modern and legacy declarations separate.

Full regressions pass 272,384 legacy number reductions with quieted native
inputs, 272,384 NaN-propagating min/max native/oracle values, 272,384 ordered
sum/product intrinsic/scalar-chain comparisons and 40,032 integer reduction
native/oracle values, with 82, 82, 161 and 119 controls respectively. Address,
carry-less multiply and scalar/vector bitcast address controls pass 150, 650
and 67 checks. Computed-index passes 26,029 native exact cases, 50,771 prewrite
refusals and 4,096 coordinate cases; prepared memory passes 28,928 byte
comparisons and 3,314 recovery/bounds/budget/metadata controls. Former modern
name refusal fixtures now check unsupported fmaxnum; positive modern coverage
lives in the new checker. Other full matrices were not repeated.

Fresh normal and deterministic software Metal processes each pass 106 geometry
dispatches, 144 shader images, 244,854 checked invocations, 106 rejected
pipelines and two prewrite bounds failures. The new image reduces
`<signaling NaN, x, y>` with both operations, subtracts minimum from maximum
and incorporates the span in its red channel. Tests cover queued dispatch,
RGBA8 buffer/texture readback, padding, both dispatch selectors, clipped groups,
repeated commits and two drained runtimes per process.

Generated checker and host C retain fixed by-value sources and accumulators.
No new dynamic arrays or substrings occur in the reduction wrapper, parser or
cache-key helper. The checker contains both declaration caches; the focused
host contains its used memory cache. Existing ownership, SSA slots, errors and
free paths are reused; no evaluator kind, node field, escaping pointer or
lifetime extension is added. Heap retention was not measured, leak detection
was disabled and native JIT code was not sanitizer instrumented. Broad runtime
and kernel/guest builds were not repeated. One initial edit-generator
interpolation diagnostic is retained; its correction preceded test execution.
All qualified checker, unit, regression and host runs pass.

This is CPU software Metal evidence. Native GPU execution, guest/Fortnite
launch gates, a Fortnite frame and complete Metal support remain unverified.

## Retained evidence

Canonical original workspace (retained in place):
`/Users/alex/Library/Caches/vinix-ios/vector-modern-number-reduction-20261116-r1`.

Complete archive:
`/Users/alex/Library/Caches/vinix-ios/vector-modern-number-reduction-20261116-r1.tar.gz`

- Archive SHA-256: `735b29aba8bd39930efdbdeccdbdff23e860fd6bad680bac00491eb1c7fd1a3e`.
- Complete typed inventory: sibling `.inventory.json`, SHA-256 `e60bc8e50f3d46d296e225c56e420ca2bba13c670855f23957cc1eeff7004faa`.
- Source snapshot: workspace `source.tar`, SHA-256 `039088002be40ca3ad533a35f76e42cc0ac54c0d5e43e49b9ffb95bc3b53d9fa`.

Inventory and archive checks compare every path, type, mode, link, size and
logical file hash, including root mode. Originals remain retained. This records
integrity without claiming restoration replay or authorizing deletion.
Commands, source revision, compiler/executable identities, LLVM capabilities,
target/features, generated C and sanitizer logs are in the bundle. Sealing
commands/statuses are siblings outside the sealed workspace.
