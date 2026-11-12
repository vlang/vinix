# Bounded scalar LLVM intrinsic calls

The [mixed scalar interpreter](BINARY32.md) supports ordinary direct CALLs to
these LLVM declarations for scalar half (`.f16`) and float (`.f32`):

| Intrinsic | Behavior |
| --- | --- |
| `llvm.fabs` | Clear only the sign bit; retain every NaN payload/quiet bit. |
| `llvm.copysign` | Copy only the second operand's sign bit onto the first. |
| `llvm.floor` / `llvm.ceil` | Round toward negative / positive infinity. |
| `llvm.trunc` | Round toward zero, retaining zero's sign. |
| `llvm.round` | Round to nearest integer, ties away from zero. |
| `llvm.roundeven` / `llvm.rint` / `llvm.nearbyint` | Round to nearest integer, ties to even in LLVM's default environment. |

Results keep the floating-point type. `scalar_intrinsics.v` manipulates integer
sign/exponent/fraction bits; no host FP instruction, environment, libm or LLVM
dependency participates in production. Signed zeros and infinities retain
their IEEE results. Rounding NaNs choose the existing preferred positive quiet
NaN; `fabs`/`copysign` preserve payload and signaling bits. Selected undef
errors and poison operands propagate. Dynamic/constrained FP environments,
exception flags and errno are not part of this profile.

Admission verifies the exact reserved name, scalar signature, arity, return/
argument types, direct declaration identity, external linkage, ordinary calling
convention and address space zero. The callee is checked against the constant
pool declaration record and is never read as a runtime pointer. Intrinsics
must be declarations. Calls require the plain explicit-type bitcode header,
zero fast-math flags and no call-site attribute list. Tail/notail/musttail,
indirect/defined/unknown callees, bundles, invoke/callbr and other precisions/
vector overloads reject, including in unvisited blocks. AIR-named intrinsics
are not aliases for these LLVM names.

Declaration attributes admit only function-level `nounwind`, `readnone`,
`readonly`, `speculatable`, `willreturn`, `nofree`, `nosync`, `nocallback`,
`nocreateundeforpoison` and `memory(none)` (bitcode memory versions 0/1/2).
Return/parameter, string/type, `strictfp`, other memory effects and unknown
attributes reject. Attribute-list/group scans share a 1,000,000 record/attribute
validation budget. An eighteen-entry fixed stack cache validates each admitted
declaration once per run and rejects duplicate reserved declarations. There
are no new owned execution arrays; the existing three temporary arrays and
their cleanup remain unchanged. Each intrinsic CALL costs one executed
instruction, without recursion or host function invocation. Valid LLVM IR and
matching immutable indexes remain preconditions; this is not a full verifier.
The integer-only entry point still rejects floating point and all calls.

`scalar_intrinsics_test.v` checks 28 exact bit/rounding/special-value patterns,
unsupported names/widths, canonical attributes, memory versions, and rejecting
memory/strictfp/string/return/parameter/missing/budget cases.

`tests/ios/air-scalar-intrinsics.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates
22 functions: nine primitives plus a chain and accumulation loop for each
precision. Half inputs cover all 65,536 encodings in every case. Float inputs
cover 32 fixed edges, 65,536 mixed-bit inputs and 65,536 signed midpoint/neighbor
inputs across exponents 0..22. It compares **2,163,040 results**: 2,140,055
bit-exact results and 22,985 rounding/arithmetic NaN-class cases. Non-math
operations preserve NaN bits exactly. Primitive CALL/return results cost two
instructions; the chain costs four. Nine rejecting fixtures, three poison
results, lazy select, budget/integer isolation, eight call-metadata corruptions,
two declaration-attribute corruptions, five result corruptions and six
distinguishing host-rounding controls pass. Native calls run only in the
default environment; LLVM/JIT/native code is not sanitizer-instrumented.

The host LLVM backend's half `copysign` quiets signaling NaNs: input `0x7c01`
with a negative sign produces `0xfe01` where the contract requires `0xfc01`.
The native observation and initial failing corpus are retained. This one case
uses a defined native LLVM integer bit-operation reference for all 65,536
inputs; the remaining 2,097,504 comparisons use native floating-point wrappers.
The reference does not relax payload checks or change production semantics.
IR/bitcode, every comparison, native diagnostic, assembler/JIT/fenv identities
and logs are preserved outside Git. The tool executes only its own fixture.

This executes a scalar prerequisite. It does not execute an AIR shader, create
a Metal device, submit GPU work or qualify an iOS application launch.

References: [LLVM fabs](https://llvm.org/docs/LangRef.html#llvm-fabs-intrinsic),
[copysign](https://llvm.org/docs/LangRef.html#llvm-copysign-intrinsic),
[rounding](https://llvm.org/docs/LangRef.html#llvm-roundeven-intrinsic),
[default environment](https://llvm.org/docs/LangRef.html#floating-point-environment),
[memory attribute decoding](https://github.com/llvm/llvm-project/blob/main/llvm/lib/Bitcode/Reader/BitcodeReader.cpp).
