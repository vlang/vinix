# Scalar zero-count checkpoint — 2026-11-12

`e49c603fd` adds `llvm.ctlz.i1..i64` and `llvm.cttz.i1..i64`. They return exact
leading/trailing zero counts. Zero input with a false constant i1 flag returns
the width; a true flag produces poison. Input bits are masked first; poison
propagates and selected undef errors. Strict direct-call/name/width/signature/
flag admission remains. Parameter two's exact `immarg` policy is passed explicitly
from admission to attribute validation, and each call's immediate is checked
independently of cached attributes. The bounded unsigned implementation uses
no host builtin, LLVM, FP or new allocation. Untagged evaluators reject these
operations. See [the contract and checker](../../compat/ios/airbitcode/SCALAR-ZERO-COUNTS.md)
and [LLVM semantics](https://llvm.org/docs/LangRef.html#llvm-ctlz-intrinsic).

Normal and ASan/UBSan runs each pass **1,329,400 exact value/tag comparisons**
across 256 operation/width/flag primitives: **1,329,226 defined and 174 poison**.
Coverage exhausts i1..i16 and supplies 4,096 wide mixed-bit patterns per case,
plus edge and single-set/single-clear-bit inputs with high-bit noise. Native
wrappers compute the expected poison tag independently, substituting one before
a true-flag zero call; false-flag zero calls still use zero. No native poison
payload is consumed. Type, width, steps and poison tags remain exact checks.

Controls pass for 128 poisoned inputs, 128 undef rejections, 256 budget/integer-
API rejections, 256 mixed-flag results, 128 invalid flags following cached
attributes, fourteen metadata corruptions, twenty-four malformed flags, twelve
result corruptions (including lost poison), and two invalid flags in dead blocks.
Sanitized units pass **1,310,712 standard-library comparisons**, including 128
poison results, explicit zero boundaries and name/width/arity/tagged-evaluator
guards. All widths, both flag values and narrow exhaustive inputs are included.

Sanitized regressions pass 743,134 exact bit-intrinsic comparisons, 2,400,256
exact FP-classification comparisons and 19,208,896 math comparisons (17,718,326
exact and 1,490,570 arithmetic NaN-class cases checking Vinix's preferred NaNs),
with their controls and 2,560 native legacy-extrema diagnostics. Mixed/intrinsic/
bit/FP-class/FMA units pass their existing cases and attribute-budget guards.
Separate full arithmetic/conversion/FMA/integer-execution LLVM suites were not
rerun. LLVM/JIT/native code is not sanitizer-instrumented, leak detection is
disabled and retained allocation was not measured.

Generated C confirms a 360-entry declaration cache, two attribute-group IDs
and by-value admission/result tuples use fixed storage. Five independent
64-width integer ranges follow forty floating-overload slots. The existing
three owned execution arrays and cleanup remain. Mixed scalar units link as a
static little-endian AArch64 Linux ELF and pass header checks; no guest ran.

Complete evidence is retained outside Git:

`/Users/alex/Library/Caches/vinix-ios/air-zero-count-validation-20261112-r1/`

It contains source, every fixture/bitcode/comparison, binaries, generated C,
identities, logs and reproduction notes. Selected V/LLVM hashes match the
pre-build receipt; full compiler/SDK/LLVM/JIT/fenv/sanitizer dependency closures
are not sealed. Existing usize FFI warnings remain. The unchanged complete
typed inventory checker passes for the original and fresh restore under
`air-zero-count-restoration-20261112-r1/`, matching every path, byte, size, type
and permission. Full decoding/extraction exit zero. Restored sanitizer zero-
count units and all 1,329,400 comparisons pass again with their controls;
restored mixed/intrinsic/bit/FP-class/FMA units also pass. Post-replay inventory
and selected identity checks pass. Receipts remain beside the bundles.

No AIR shader, iOS app, GPU command or new Fortnite probe ran. The default Metal
device stub still returns nil; no new frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| Inventory JSON beside bundle | `f2e9481bea9cd90a8f64035aecdcfb541131155ed50f26c165a223ae2f9299cf` |
| Complete `.tar.zst` beside bundle | `9e4d126ce2a3d6b7f618beaef2e81a938c677b1cd7fee827b31fd1a50bb04aa8` |
| `source.tar`, revision `e49c603fd` | `0789986ce8d89262ba8fd126c10a7fb4bd327408db3660ae9b62b822287d49c3` |
