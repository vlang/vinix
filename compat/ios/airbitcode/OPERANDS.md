# Partial typed AIR instruction operands

After building `Stream`, `IRModule`, `IRConstantPools` and `IRFunctionBodies`
from the same immutable raw module, call
`p := ir.typed_operands(stream, pools, bodies)!`. Call `p.free()` once before
freeing the original indexes. Treat the returned indexes as immutable.

The program owns five arrays: instruction descriptors, typed value operands,
block targets, types and type references. Original type IDs remain unchanged.
Original type names are borrowed from `ir`, without cloning or freeing them.
Scalar/vector boolean types needed by comparisons are interned when absent from
the original table. `p.type_text(ir, index)!` renders original/synthetic types;
the caller owns and frees the returned string.

Instruction indexes match `bodies.instructions`. Every instruction has an
explicit status:

- `decoded`: this profile read the instruction and its operands have known,
  matching definition types.
- `opaque`: its instruction family has no operand decoder here. The raw record
  remains in `Stream`. Explicit call result signatures may still supply a type.
- `deferred`: decoding or type verification depends on an unknown producer type.
  Cast and PHI definitions may still have independently encoded result types.

`p.complete(bodies, scope)` checks that every instruction in an active function
has status `decoded`. A decoded consumer may use an independently known type of
an opaque/deferred producer; the function remains incomplete. Never treat an
incomplete function as fully decoded. Completeness is limited to this profile;
it does not establish dominance, executable LLVM IR, supported lowering or Metal
capabilities. Flags are retained as raw bits and have no execution semantics yet.

Supported families are integer/floating binary arithmetic, casts, scalar/vector
comparisons, old/vector select, extract/insert element, PHI, return, direct
branch, unreachable, floating negation and freeze. Arithmetic/cast/predicate
numbers, result types, value operands and selected flags are retained. Operand
ordering follows bitcode: select's true/false values precede its condition.
PHI value operands and predecessor targets have matching positions. Targets
are global indexes into `bodies.blocks`; value numbers remain scoped IDs.

Unsigned relative operands use the instruction's current value ID and u32 wrap
arithmetic. Forward value/type pairs consume an explicit type word. PHI uses a
separate signed-VBR delta convention, including forward loop references. Lookup
checks value scope/bounds. Casts/PHIs and explicit call results seed types before
decoding; a final pass checks forward type claims against known definitions.
Unknown definitions cause deferral rather than guessed types. Deferred operand
ranges must not be consumed as verified data.

The reader checks supported record arities, trailing fields, value type matches,
numeric opcode categories, integer/FP predicates, cast scalar/vector shapes and
width/category rules, vector index types, select condition shapes, PHI target
bounds/conflicting duplicate predecessors, branch condition types and return
types. Pointer casts retain address spaces. Numeric bitcasts compare total lane
width and scalability. This is a bounded strict profile, not an LLVM verifier.
Unsupported cast categories can fail even when another LLVM profile permits
them. No data-layout pointer width or address calculation is inferred.

Calls, memory operations, GEP, shuffle/aggregate operations, switches, exception
instructions and other families remain opaque. Constant expressions retain the
previous pool layer's opaque tags. This layer does not evaluate constants, prove
CFG/dominance/PHI predecessor relationships, verify every flag encoding, lower
instructions, submit Metal commands or render a frame.

Limits are 4,194,304 typed operands, 1,048,576 targets, original IR types plus at
most 262,146 additional types, and original type-reference capacity plus 262,144
references. The existing body/stream limits also apply. Boolean/vector interning
and scoped lookup avoid repeated type scans; passes are linear in instructions,
operands and targets, apart from bounded hash lookups. All owned arrays and
transient maps are released on success/error; borrowed type names stay owned
by the original IR module.

`operands_test.v` uses deliberate semantic fixtures for exact normalized IDs,
forward PHIs, synthetic boolean vectors, type-name ownership, malformed input
and mutations. The V inspector `tests/ios/air-operands-inspect.v` supports:

- `self-test LLVM_AS LLVM_DIS FRESH_EXTERNAL_DIR`: assemble portable LLVM fixture
  data, check three complete core function indexes plus explicit opaque/deferred
  functions, flags and forward PHI identity, and reject eight corrupted dumps
  or decoded indexes. These functions are format fixtures, not iOS apps.
- `corpus INPUT_DIR LLVM_DIS FRESH_EXTERNAL_DIR`: copy raw modules and independently
  disassemble them. Compare exact arithmetic/cast/predicate mnemonics and selected
  operand/result type spellings only for `decoded` instructions. Named type
  quoting is normalized. Function instruction counts still cover all statuses;
  native value IDs, operand values, branch/PHI edge identity, raw flags and opaque
  families are not compared to LLVM here. It expects LLVM's normal two-space
  primary-instruction format and ignores indented continuation lines.

Build with the [README flags](README.md); keep generated evidence outside Git.
Layouts follow [LLVM's reader](https://github.com/llvm/llvm-project/blob/main/llvm/lib/Bitcode/Reader/BitcodeReader.cpp)
and [opcode definitions](https://github.com/llvm/llvm-project/blob/main/llvm/include/llvm/Bitcode/LLVMBitCodes.h).
