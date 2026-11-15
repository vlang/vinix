# Scalar integer absolute value

The mixed scalar interpreter accepts `llvm.abs.iN(iN, i1)` for every N from
1 through 64, returning iN. The second argument must be a constant boolean.
For the minimum signed value, a false flag returns the original minimum bits;
a true flag produces poison. Every other input returns its absolute magnitude.
This includes i1, whose only negative value is also its minimum. Input poison
propagates; selected undef errors. The integer-only API retains its no-call
profile for scalar intrinsic calls. CALL/return takes two executed instructions.

Production masks the input to its declared width and uses unsigned modular
negation when the sign bit is set. It never negates a host signed minimum,
including INT64_MIN. No host builtin, LLVM, FP or new allocation participates
in numerical evaluation. Untagged and unary integer evaluators reject abs.

The [direct-call profile](SCALAR-INTRINSICS.md) checks canonical names, exact
width/signature/arity, direct external declaration identity, calling convention,
default pointer address space and explicit-type CALL header. Fast-math/tail
flags and call-site attributes reject. Harmless function-level declaration
attributes retain their whitelist. Parameter two alone may have the exact enum
`immarg` attribute. Every call checks its constant i1 independently of attribute
caching, including in unvisited blocks. Dynamic, SSA, declaration, poison,
undef, splat, opaque, mistyped and nonboolean flag encodings reject. In this
scalar profile, wider integers, malformed decimal suffixes and AIR aliases reject.
Valid LLVM IR and matching immutable indexes remain preconditions.

The fixed stack cache has 1384 entries: forty floating-overload slots and twenty-one
independent 64-width integer ranges. Abs uses its own range. The shared
1,000,000-work attribute limit, fixed two-ID attribute storage and existing
three owned execution arrays/cleanup remain. Retained allocation is not measured.

`scalar_integer_abs_test.v` passes **655,356** independent signed-magnitude
comparisons (sixteen poison cases), plus idempotence, every width's minimum
under both flags, zero and strict name/width/arity/evaluator guards. Every
i1..i16 bit pattern is exhausted under both flags; wider widths receive 4,096
patterns each. The reference safely reconstructs signed values and handles
each minimum before signed negation, independently of production's arithmetic.

`tests/ios/air-integer-abs.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates
and LLVM-verifies 128 primitive functions across all widths and both flags.
It compares **656,892 exact value/tag results**, including **87 poison cases**.
Every i1..i16 bit pattern is exhausted; wider widths receive 4,096 mixed-bit
values. Twelve edge values per function include zero, +/-1, signed minima and
neighbors, maximum patterns, alternating bits and byte patterns. Incoming high
bits test argument truncation before the minimum comparison.

The native value wrapper substitutes zero before a call that would produce
poison; a separate native function returns an explicit minimum/flag poison tag.
No invalid native abs result is consumed, and no result bit is reserved for
tagging. Defined values, poison, result kind/width and exact instruction count
are compared. Poison payload bits are ignored.

Controls check 64 input-poison results, 64 undef rejections, 128 budget/integer-
API rejections, 128 mixed-flag results, 64 cached nonconstant-flag rejections,
seven metadata corruptions, twelve flag corruptions, six result corruptions and
one malformed flag in a dead block. Mixed functions reuse the same declaration
under both flags, with minimum and zero inputs, in exactly four instructions.
Only generated fixtures execute. LLVM/JIT/native code is not sanitizer-
instrumented. Complete IR/bitcode, every comparison, binaries, identities and
logs belong in external bundles.

`tests/ios/air-integer-abs-regressions.v EXTERNAL_BUNDLE_DIR` is the local
pinned-toolchain V batch for the shared-profile sanitizer regressions. Its
header records the required environment; output children must be fresh.

This is scalar execution groundwork. No AIR shader, Metal device, GPU command
or application launch is qualified.

## Vector integer absolute value

Ordinary direct `llvm.abs.vNiW(<N x iW>, i1)` calls support fixed 1..16-lane
integer vectors at widths i1..i64. Result and first argument types must match.
The constant boolean flag is scalar and applies to every lane. For signed
minimum inputs, false preserves the minimum bits and true produces poison.
Other inputs return the absolute magnitude. i1 and i64 follow the same rule.
The scalar evaluator supplies masked unsigned modular negation without signed
overflow, a host builtin or a new normal-path allocation.

Input poison propagates per lane; any undef source lane fails even if discarded.
Source/result freezes select zero for indeterminate lanes. Results are independent
snapshots. Both scalar APIs, void and memory execution admit these vector calls;
floating producers still require mixed execution. Integer-only scalar calls
retain their existing restrictions.

Canonical names, exact shapes/signatures, ordinary call flags, calling convention,
external declaration identity and every source are checked. Only parameter two
may carry the exact enum immarg attribute. Its i1 constant is validated on every
call, including declaration-cache hits and cold blocks. Nonconstant arguments,
SSA results, poison/undef flags and nonboolean pool words reject before writes.
Return/first-argument attributes, other second-argument attributes, vector flags,
i65/wider lanes, vector arguments/returns/PHIs/loads/stores, scalable/oversized
vectors and AIR aliases remain outside this profile.

Slots 10944..11967 add 1,024 distinct width/count identities, taking the shared
stack cache to 16,064 entries with the further 4,096 saturating-add/sub slots.
Flags share an identity but retain independent meanings. Each call costs one
instruction, two lane counts of profiling work and
one construction slot. The 4,096-result and 1,000,000-work caps remain unchanged.

`vector_integer_abs_test.v` checks 2,065,472 independent value/poison results,
using safe signed reconstruction and handling each minimum before signed negation.
It exhausts all i1..i16 bit patterns under both flags and checks wider patterns,
every shape, boundaries, high-bit noise and snapshots. Another 208,896 lane-state
checks cover poison/undef/freezes. The shared cache test covers all 16,064 keys.
Older units use unsupported vector saturating-shift name guards.

`tests/ios/air-vector-abs.v LLVM_AS FRESH_EXTERNAL_DIR` generates the decoded
reference matrix, bulk narrow exhaustion/wide patterns, call-local flag/cache
controls and exact shared limits through four APIs. Native calls consume only
defined extracted results with canonical padding; the VM also receives high-bit
noise. True-flag minimum inputs in the defined bulk sweep use zero; independent
matrix/unit cases retain minimum-poison checks. Source fixtures and comparison
tables are gzip-compressed after each module, immediately decoded and checked
against their original SHA-256, with both checksums retained. Historical checkers
remain unchanged. Native JIT is uninstrumented and retained heap is unmeasured.

The software Metal fixture exercises 240 dispatches across 128 kernels per
runtime: 180 complete and 60 fail as expected. It covers both flags, i1/i64,
source/result freezes, poison/undef, discarded results, snapshots, chains sharing
a declaration under different flags, deferred inputs, sparse bindings and output
guards. Tail, i65 and nonconstant-flag pipelines reject. This is CPU software
execution; GPU rendering and application launch remain unqualified.

The nonconstant-flag fixture assembles with an ordinary `test.abs.v1i32`
declaration, then changes its one string-table name to `llvm.abs.v1i32` before
building the synthetic library. LLVM otherwise rejects that malformed call
before the backend can exercise its own refusal. The rename changes no body or
valid kernel; the decoded-reference controls independently repair each flag
before testing rejection through all four execution APIs.

Reference: [LLVM abs semantics](https://llvm.org/docs/LangRef.html#llvm-abs-intrinsic).
