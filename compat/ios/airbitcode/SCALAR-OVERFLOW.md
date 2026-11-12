# Bounded integer overflow pairs

The mixed scalar API accepts `llvm.sadd.with.overflow.iN`,
`llvm.uadd.with.overflow.iN`, `llvm.ssub.with.overflow.iN`,
`llvm.usub.with.overflow.iN`, `llvm.smul.with.overflow.iN` and
`llvm.umul.with.overflow.iN` for every i1..i64 width. Arguments are matching
scalar iN values. The return is exactly a literal, unpacked `{iN, i1}`:
the wrapped N-bit arithmetic result followed by the overflow flag.
See [LLVM's contract](https://llvm.org/docs/LangRef.html#arithmetic-with-overflow-intrinsics).

The CALL result can be consumed only by `extractvalue` with one literal index,
zero for the arithmetic value or one for the flag. Extracted scalars can use
ordinary arithmetic, freeze, control flow and PHIs. Input poison propagates
through both extracted fields; undef operands still error. Overflow sets the
flag without poisoning either field. No valid data bit is reserved for a tag,
including at i64. CALL, extraction and every other visited instruction each
consume a step under the existing budget.

Aggregate arguments, returns, constants, select/PHIs, freeze and insertvalue
remain outside this profile. The integer-only API continues rejecting calls
and aggregate extraction. All blocks are preflighted, including unvisited
ones. Direct-call identity, canonical name/width, signature, flags, calling
convention and attributes use the existing strict policy. Each of the six
new families has an independent 64-width declaration-cache range; the fixed
stack cache now holds 1,768 entries. Duplicate declarations and malformed
second calls cannot bypass validation through caching.

Production reuses the unsigned bit-pattern ALU for wrapping arithmetic and
its NUW/NSW checks for overflow. The latter's poison flag becomes the pair's
overflow bit, while a separate wrapped evaluation retains the arithmetic
value. The runtime value adds overflow and aggregate booleans, preserving
the existing 16-byte value layout. A dedicated reader requires a known pair
slot; ordinary scalar reads reject pair tags. Extraction clears that aggregate
tag and preserves poison. There is no new valid-path allocation, LLVM runtime
dependency or host signed arithmetic. The three existing owned arrays and
cleanup remain; no retained-allocation measurement is implied.

`scalar_overflow_test.v` compares all i1..i8 input pairs for all six families
against independent widened signed/unsigned arithmetic: 524,280 exact pairs.
Twelve i64 boundaries and name/width/arity/evaluator/layout guards are included.

`tests/ios/air-overflow.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates
portable fixtures, assembles/verifies them independently, and invokes native
LLVM MCJIT wrappers through raw i64 arguments. Both fields are compared
separately at every width: 1,955,832 exact pairs / 3,911,664 extracted fields.
All i1..i8 pairs are exhausted; wider widths receive 4,096 mixed pairs and a
twelve-by-twelve edge matrix. Incoming high bits exercise masking. No native
poison result is consumed. Interpreter controls check both fields' input
poison/undef handling, budgets, integer API isolation, freezing extracted
poison, strict metadata/layout/type/name checks and corrupted results,
including a lost overflow bit. Native two-call branch/PHI functions reuse
declarations and check both value paths and their exact steps. Source,
bitcode, every pair comparison, assembler status and JIT identity go to the
fresh external directory. This does not execute AIR shaders or GPU commands.
