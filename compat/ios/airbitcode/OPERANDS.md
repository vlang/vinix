# Partial typed AIR instruction operands

After building `Stream`, `IRModule`, `IRConstantPools` and `IRFunctionBodies`
from the same immutable raw module, call
`p := ir.typed_operands(stream, pools, bodies)!`. Call `p.free()` once before
freeing the original indexes. Treat the returned indexes as immutable.

The program owns six arrays: instruction descriptors, typed value operands,
block targets, types, type references and aggregate/shuffle indexes. Original
type IDs remain unchanged.
Original type names are borrowed from `ir`, without cloning or freeing them.
Scalar/vector boolean types needed by comparisons are interned when absent from
the original table. `p.type_text(ir, index)!` renders original/synthetic types;
the caller owns and frees the returned string.
Pointer types needed by GEP/alloca are also interned, retaining address spaces
and the original module's typed or opaque pointer representation.

Instruction indexes match `bodies.instructions`. Every instruction has an
explicit status:

- `decoded`: this profile read the instruction and its operands have known,
  matching definition types.
- `opaque`: its instruction family has no operand decoder here. The raw record
  remains in `Stream`. Explicit call result signatures may still supply a type.
  This also covers calls with unimplemented bundles or fixed metadata/label/token
  arguments, even when ordinary calls in that family decode.
- `deferred`: decoding or type verification depends on an unknown producer type.
  Cast, PHI, alloca and explicit-load definitions may still have known result types.

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

Non-atomic load/store, alloca, GEP and extractvalue/insertvalue also decode.
Legacy implicit-pointee memory/GEP encodings remain supported where a typed
pointer supplies the missing element. Modern explicit load/GEP types also work
with opaque pointers. `source_type` retains the accessed data type, initial GEP
element, allocation element or aggregate container, depending on the family.
`indices` stores literal aggregate field paths; dynamic GEP indexes remain
typed value operands. Struct GEP indexes require materialized scalar i32
constants; array/vector indexes may be dynamic. Vector GEP bases/indexes must
have matching shapes. No byte offset is computed and GEP array offsets are not
treated as bounds checks.

The separate [GEP offset layer](GEP.md) builds scalar offset plans from decoded
instructions and ABI layouts. It does not change this decoder or implement
poison rules or memory access.

`alignment` is the explicitly encoded byte alignment, or 0 when the ABI default
is unresolved. The decoder does not infer size, padding, ABI alignment or pointer
width. The separate [type-layout layer](LAYOUT.md) supplies supported sizes,
padding, alignments and structure offsets without changing operand decoding.
`is_volatile` retains load/store volatility. Alloca's count is an absolute
value ID. Its packed alignment/flags and optional address space are retained;
the data-layout `A` component supplies a default allocation address space.
Mixed typed/opaque pointer tables are rejected for alloca rather than guessing
its result representation. With no original pointer types, allocas use opaque
pointers. Unsized/cyclic allocation/storage types are not
fully verified. Memory operations remain data descriptions, without execution.

SHUFFLEVEC reads two identically typed vector inputs and a constant vector mask
with i32 elements. `source_type` retains the input vector type; the result has
its element type and the mask's length/scalability. Its three value operands
retain input/input/mask IDs. The instruction's `indices` range contains normalized
mask lanes: an index into the concatenated inputs, or `~u32(0)` for poison/legacy
undef. Negative integer literals are rejected rather than treated as poison.
DATA, aggregate, zero, undef and poison masks are materialized. Constant-expression
masks defer without being evaluated, retaining the inferred result type. Source
types that remain unknown also defer. Deferred ranges are not consumable.

Scalable masks support zero/undef/poison splats only. The stored mask range is the
minimum lane pattern, repeated for the runtime vscale; it does not assert a fixed
runtime vector width. Mask lanes share the aggregate-index expansion budget.
No vector selection or instruction execution occurs here. The builder borrows
the immutable Stream while reading aggregate constants; the returned program
retains no additional Stream ownership.

Ordinary SWITCH records retain a relative condition ID followed by absolute
integer-constant case IDs in their value operand range. Their target range starts
with the default block, followed by each case destination in table order.
`source_type` retains the scalar integer type and the instruction has no result.
Case bits stay in the owning constant pools. Equal case values are rejected
even if they have different IDs or use implicit versus materialized zero. Shared
destinations are allowed. Wide cases compare canonical limbs without truncation.
Transient duplicate-check keys are cloned from borrowed pool bytes and freed.
A cumulative 4,194,304-word work cap includes the width of implicit zero cases.
The reverted legacy range encoding remains explicitly opaque. An unknown
condition type defers the ordinary switch; no branch is evaluated. Destination
bounds do not establish reachability, dominance or other CFG validity.

Explicit-type CALL records decode a scalar pointer callee, fixed arguments and
value/type-pair varargs. The operand range starts with the callee, then arguments
in source order. `call_signature` indexes the original function type;
`callee_function` indexes `ir.functions` for a direct function declaration,
otherwise it is -1. Function declaration pointers are recovered from their raw
records, retaining the original typed/opaque representation and explicit or
data-layout `P` program address space. Global variable records also supply their
pointer types: legacy records retain an encoded typed pointer; explicit-element
records retain their encoded address space and the original module's typed or
opaque pointer representation. With no original pointer types, explicit globals
use opaque pointers. Explicit globals in mixed pointer tables fail rather than
guess a representation. Aliases and ifuncs remain untyped. Initializer, linkage,
storage, name and attribute schemas are not verified or executed by this typing
step. Unsized/cyclic storage validation and global allocation remain future work.
The separate [global descriptor layer](GLOBALS.md) indexes names, declared
initializers and selected storage flags without changing this operand decoder.
Forward callee claims and fixed argument types undergo the final definition
check. An unknown callee or argument type causes deferral, preserving the known
result type. Void calls consume no result ID.

`attribute_set` retains the uninterpreted attribute-list ID, `flags` retains the
packed call header, `calling_convention` extracts its convention and
`fast_math_flags` retains its optional FMF word. Attribute contents, tail-call
legality, convention compatibility and intrinsic implementations are unverified.
Explicit signatures may reinterpret typed pointers; their historical pointee
signatures are not required to match. Bundled calls and calls with fixed
metadata/label/token parameters remain opaque. INVOKE/CALLBR stay opaque.
Metadata varargs are outside the supported value/type profile and may fail.
Recognizing an AIR or LLVM intrinsic does not provide execution semantics.

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

Atomic memory operations, exception
instructions and other families remain opaque. Constant expressions retain the
previous pool layer's opaque tags. This layer does not evaluate constants, prove
CFG/dominance/PHI predecessor relationships, verify every flag encoding, lower
instructions, submit Metal commands or render a frame.

Limits are 4,194,304 typed operands, 1,048,576 targets, 327,682 total types and
524,288 total type references. Aggregate paths and shuffle masks share a separate
1,048,576-index cap. The
existing body/stream limits also apply. Boolean/vector/pointer interning
and scoped lookup avoid repeated type scans; passes are linear in instructions,
operands and targets, apart from bounded hash lookups. All owned arrays and
transient maps are released on success/error; borrowed type names stay owned
by the original IR module.

`operands_test.v` uses deliberate semantic fixtures for exact normalized IDs,
forward PHIs, synthetic boolean vectors, type-name ownership, malformed input
and mutations. The V inspector `tests/ios/air-operands-inspect.v` supports:

- `self-test LLVM_AS LLVM_DIS FRESH_EXTERNAL_DIR`: assemble portable LLVM fixture
  data, check five complete function indexes, an ordinary call, flags and
  forward PHI identity, and reject eight corrupted dumps
  or decoded indexes. These functions are format fixtures, not iOS apps.
- `memory-self-test LLVM_AS LLVM_DIS FRESH_EXTERNAL_DIR`: assemble memory fixture
  data with three complete function indexes, scalar/vector GEP, aliasing accesses,
  alloca A5, aggregate paths, explicit alignment/volatility and eight corruption
  controls. It does not execute the fixture.
- `call-self-test LLVM_AS LLVM_DIS FRESH_EXTERNAL_DIR`: independently assemble
  direct/indirect/void/vararg calls, CC/tail/FMF fields and unsupported bundled/
  metadata calls; reject eight corrupted dumps or decoded indexes. Its call
  comparison checks exact direct callee names, argument count/types and return
  type or vararg signature. Specific legacy lifetime/memory intrinsic upgrades
  are normalized for LLVM's disassembly only; original AIR operands stay intact.
  Indirect value identities, raw call flags/attributes and intrinsic behavior
  are not compared. The text comparator requires a named @/% callee.
- `shuffle-self-test LLVM_AS LLVM_DIS FRESH_EXTERNAL_DIR`: independently assemble
  fixed/pointer/scalable vectors, width-changing permutations and zero/undef/
  poison masks. Compare both input types, mask type, every normalized mask lane
  and inferred result shape; reject eight corrupted dumps or indexes. Input
  value identities and vector execution remain unqualified.
- `switch-self-test LLVM_AS LLVM_DIS FRESH_EXTERNAL_DIR`: independently assemble
  signed/boolean/i128 cases, shared targets, empty tables and quoted labels.
  Compare exact case bits and default/case destinations using LLVM's printed
  block order; reject eight corrupted dumps/indexes. The independent decimal
  parser supports widths up to 4096 bits. Condition value identity and switch
  execution are outside the comparison. Other operand comparisons retain their
  documented limits; branch/PHI edges are not compared by this switch checker.
- `global-self-test LLVM_AS LLVM_DIS FRESH_EXTERNAL_DIR`: independently assemble
  scalar/array/pointer globals across address spaces and an unsupported alias.
  Check accessed types/address spaces, exact declaration IDs, preserved alias
  deferral and eight corrupted dump/index controls. Initializer values and global
  execution are outside this comparison.
- `corpus INPUT_DIR LLVM_DIS FRESH_EXTERNAL_DIR`: copy raw modules and independently
  disassemble them. Compare exact arithmetic/cast/predicate mnemonics and selected
  operand/result type spellings only for `decoded` instructions. Named type
  quoting is normalized. Function instruction counts still cover all statuses;
  native value IDs, operand values, branch/PHI edge identity, raw flags and opaque
  families are not compared to LLVM here. It expects LLVM's normal two-space
  primary-instruction format and ignores indented continuation lines.
  For decoded memory forms it additionally compares source/base pointer type
  spellings, explicit alignment, volatility, alloca address space and literal
  aggregate indexes. GEP byte offsets, native value identities and layout
  calculations remain outside that comparison.

Build with the [README flags](README.md); keep generated evidence outside Git.
`tests/ios/air-operands-deferred.v CORPUS_DIR [...]` diagnoses remaining deferred
records and prints per-opcode counts plus a total, without invoking LLVM or
qualifying execution. It accepts the same copied `module-*.bc` inputs.
Layouts follow [LLVM's reader](https://github.com/llvm/llvm-project/blob/main/llvm/lib/Bitcode/Reader/BitcodeReader.cpp)
and [opcode definitions](https://github.com/llvm/llvm-project/blob/main/llvm/include/llvm/Bitcode/LLVMBitCodes.h).
