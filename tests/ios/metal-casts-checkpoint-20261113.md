# Software Metal scalar casts — 2026-11-13

`f47319ed7` adds scalar casts to bounded AIR memory execution and the opt-in
software Metal compute profile. Supported operations are integer truncation,
zero/sign extension across i1..i64, signed/unsigned integer conversions to and
from half/float, half/float precision changes and same-width integer/floating
bitcasts. Scalar and memory execution share validation and value helpers.
Preflight checks arity, types, width direction, flags and result slots. Pointer,
vector, aggregate, double and bfloat casts remain outside this profile. Each
cast costs one step. See
[MEMORY-EXECUTION.md](../../compat/ios/airbitcode/MEMORY-EXECUTION.md).

Normal and ASan/UBSan runs pass 210,112 defined native LLVM comparisons across
6,566 load/cast/store functions, 32 samples each. These include all 6,048 valid
integer width/operation combinations, 256 integer-to-floating functions,
256 floating-to-integer functions, four raw bitcasts and two precision changes.
Results match exact bits except four precision-conversion NaN-class matches
without payload/sign equality. Unused native narrow-integer padding is masked;
the interpreter must zero it. Checks cover destination sentinels, exact
four-step execution and insufficient budgets.

Eight interpreter controls cover NaN, infinity, unsigned-negative and signed
overflow conversions, poison input, undef input, unsupported pointer casts and
a computed poison value discarded by select. The first seven reject; the last
stores 17. The pointer cast follows a store but rejects during preflight before
that store runs. Invalid ordinary native floating-to-integer casts are never
executed by this checker.

The reference uses Homebrew LLVM 23.1.5 MCJIT with explicit optimization level 2
and FastISel disabled. An earlier run with unconfigured MCJIT disagreed on
`sext i1 true to i8` (native 1, expected 255). Its failure logs, function and
machine-code bytes, plus llc assembly, remain in the bundle. This observation
does not establish an upstream LLVM defect. Both final configured runs and the
restored run pass.

All 24 software Metal test groups pass with normal and deterministic Swift
hashing. New synthetic kernels exercise integer-to-float and float-to-integer
casts through pipeline creation, buffer offsets and deferred dispatch:
`-5 + 1.25` stores float -3.75, and `5.75 - 1.25` converts 4.5 to integer 4.
Sanitized regressions also pass all 16 integer/mixed unit groups (including
1,397,052 exhaustive small-width flag checks), 86,016 memory comparison/select
cases, 1,064,960 float32 conversion comparisons (843,042 values and 221,918
poison results), and 1,167,424 half conversion comparisons (4,624 NaN-class
results). Existing corruption, rounding, poison and lazy-select controls pass.
LLVM JIT-generated native reference code is not sanitizer-instrumented;
the interpreter and checkers are.

Evidence bundle:

`/Users/alex/Library/Caches/vinix-ios/air-memory-casts-validation-20261113-r1/`

The complete sibling archive was decoded and extracted to fresh `-restored`.
Saved source/compiler/header/executable identities match. All six restored
sanitizer suites pass again with fresh external fixtures, including the software
Metal host with normal hashing. The archive checksum passes afterward. Restore
receipts remain beside the bundle; original evidence is retained. The compiler
snapshot was saved after checks. The software harness retains its documented
compiler-preamble corrections. Toolchain library symlinks, SDKs, assembler and
dylibs remain external prerequisites; complete dependency closures are not
sealed. This is not a full typed-inventory audit. Leak detection is disabled;
runtime object drainage is checked, retained heap is not measured.

The ordinary runner was not rebuilt. Compute remains a bounded single-thread
CPU interpreter with valid LLVM IR as a precondition. Synthetic LLVM/AIR
fixtures do not establish compatibility with Apple compiler-produced kernels.
No GPU execution, presentation, Vinix guest, Fortnite frame or launch gate is
verified by this checkpoint.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `43daca22eb7b9ec388e3488addbd053b1fbad8f480c45a1ccd787e407c81518d` |
| `source.tar`, revision `f47319ed7` | `781a8b24482dd79091b854c0295604ede732c93fef29f1e09d38d305789841f5` |
