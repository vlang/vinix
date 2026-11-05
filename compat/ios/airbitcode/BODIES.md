# AIR function body structure and result IDs

After constructing `Stream`, `IRModule` and `IRConstantPools` from the same
immutable input, call `bodies := ir.function_bodies(stream, pools)!`.
The index owns four arrays; call `bodies.free()` once. It borrows no strings.
Keep the original indexes alive when following its scope, type and record IDs.
This is a structural index, not an LLVM verifier or instruction translator.
The separate [partial typed operand decoder](OPERANDS.md) adds a checked core
subset while explicitly retaining opaque/deferred instructions.

`scopes` uses the existing convention: scope 0 is the module, and function index
plus 1 is its local scope. Module/declaration body scopes are inactive.
Each active scope has contiguous ranges of instructions, blocks and result
indexes. `base_id` follows module values, arguments and function-local constants.
Only non-void instructions consume a value ID. An instruction's `next_value`
stores the current ID even if it has no result; relative value operands use that
base. Block IDs form an independent local sequence starting at zero.

`instructions` retains the original record index, scope, global block index,
current value ID, result-presence flag and terminator flag. `call_signature`
identifies an explicit CALL/INVOKE/CALLBR function type. Other result types and
all instruction operands remain in the raw stream. No instruction is executable
merely because it appears here.

`blocks` stores local block numbers and contiguous instruction ranges, including
each block's terminator. `results` maps a scope's sequential result IDs to
instruction indexes. `bodies.lookup(pools, scope, number)!` returns either an
existing pooled value (declaration/argument/constant) or an instruction index.
The pooled field is defined only for `.pooled`, and the instruction field only
for `.instruction`. Lookups reject invalid, inactive and out-of-range scopes/IDs;
function-local numeric IDs can be reused independently.

The reader checks DECLAREBLOCKS agreement, complete terminated block counts,
instruction placement, PHI grouping, direct branch arity/target bounds, bundle
prefix consumption, explicit call type indexes/return types/minimum operand
counts and selected auxiliary-record shapes. CALL fast-math flags shift the
explicit type position; INVOKE and CALLBR have different destination/type
layouts. Void calls consume no result ID, while non-void invoke/callbr and
catchswitch instructions have results despite terminating a block.

Debug locations/records, block-address users and operand bundles consume neither
instruction nor value IDs. Their raw records remain in `Stream`; debug schemas,
bundle arguments/tag IDs and block-address references are not verified. Nested
constant, metadata, attachment and symbol-table blocks are not instructions.
`has_operand_bundles` records whether prefixes attach to each call consumer so
later decoding cannot silently discard them.

Known LLVM instruction codes through the LLVM 23 profile are classified by
result/terminator behavior. Reserved/unknown codes and implicit call types fail
explicitly, since guessing would shift all subsequent IDs. Non-call operand
schemas, exact arithmetic opcodes, operand types/references, callee compatibility,
CFG edges beyond direct branch targets, dominance, return types and exception
semantics are not fully verified. Calls with forward operands or varargs can
carry extra type operands; these stay raw. This index does not advertise shader
or Metal capabilities.

Limits are 262,144 instructions and 262,144 blocks across the module. A parsed
function has at most 65,536 blocks from the existing IR layer. Result IDs must
fit in 32 bits. Scope record buckets keep traversal linear in blocks, records,
functions and instructions. Transient buckets and owned arrays are freed on
success/error. Existing bitstream/type/constant limits still apply.

`bodies_test.v` covers scopes, calls, FMF, auxiliary records, terminating results,
malformed structure and mutations using deliberate semantic fixtures.
`tests/ios/air-bodies-inspect.v` has two modes:

- `corpus INPUT_DIR LLVM_DIS FRESH_EXTERNAL_DIR` copies `module-*.bc`, independently
  runs LLVM disassembly and compares instruction opcode families, result presence,
  terminators, per-block instruction extents, sequential IDs starting after the
  pooled prefix, and result lookup. It does not compare operands, exact numeric
  arithmetic opcodes or result types. Named instruction text does not expose raw
  bitcode IDs independently of the pooled prefix.
- `self-test LLVM_AS LLVM_DIS FRESH_EXTERNAL_DIR` assembles portable LLVM fixture
  data with void/value/bundled calls, invoke, callbr, PHI, switch, landingpad and
  resume. It checks known totals and rejects ten corrupted dumps/indexes.

The textual comparison accepts LLVM's normal two-space primary-instruction
format and ignores indented switch/EH/invoke/callbr continuation lines. Its
instruction-count and block checks still require every primary instruction.
It is a regression comparator, not a general LLVM assembly parser.

Build flags and toolchain requirements are in [README.md](README.md). Keep raw
inputs and evidence outside Git. Record layouts and value numbering follow
[LLVMBitCodes.h](https://github.com/llvm/llvm-project/blob/main/llvm/include/llvm/Bitcode/LLVMBitCodes.h)
and [BitcodeReader.cpp](https://github.com/llvm/llvm-project/blob/main/llvm/lib/Bitcode/Reader/BitcodeReader.cpp).
