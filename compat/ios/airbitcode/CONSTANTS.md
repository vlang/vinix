# AIR constant pools and value IDs

Call `pools := ir.constant_pools(stream)!` after constructing `stream` with
`parse(data)` and `ir` with `stream.ir_module(data)`. All three must refer to the
same immutable input. The new index owns five arrays; call `pools.free()` once.
It does not free the IR module, stream or input. Record/type indexes refer back
to those original indexes, so retain them while interpreting the result.

Scope 0 is the module. A function's scope is its IR function index plus 1;
declarations have inactive function scopes. `module_values` counts raw module
declarations and module constants. A definition's arguments follow that prefix,
then its local constants. Different functions may reuse the same numeric IDs.
`pools.lookup(scope, number)!` distinguishes raw declarations, arguments and
constants in O(1). Instruction-result IDs are outside this index and produce
an error. A declaration's raw record is retained; its type and other fields
are not inferred by this layer.

Each constant retains its declared type, scope, value ID, source record and
explicit kind. SETTYPE state resets per pool, with indexed i32 as the implicit
default. Signed-VBR integers decode to exact two's-complement bits, including
LLVM's special INT64_MIN encoding. Wide integers are zero-extended to the
record's bit width and mask unused high bits. Integer/FP vector splats store
one lane. Half, bfloat, float, double, x86_fp80, fp128 and ppc_fp128 bit patterns
are preserved without host floating-point conversion. Integer scalar records
wider than 64 bits require the wide encoding in this strict profile.

`words` contains little-endian integer/FP limbs, DATA element bit patterns or
string bytes (including a CSTRING's implicit terminator). NULL/undef/poison
and aggregate references have no expanded words. `scalar_bits(index)!` returns
one numeric scalar/lane of at most 64 bits, or numeric zero for a NULL constant.
It rejects aggregates, data sequences, wide scalars, undef, poison and opaque
expressions; these are never silently converted to zero.

Aggregate counts, in-scope value bounds, constant element types and references
to arguments are checked. A declaration reference must occupy a pointer element;
full declaration type matching and aggregate-cycle validation remain future work.
Known constant expressions, inline assembly and related value-producing records
retain an explicit `opaque` kind and source record. Their operands and semantics
are not verified or evaluated. Unknown record codes fail. This is a pool index,
not an LLVM verifier, expression evaluator or shader executor.

One constant block per scope is supported. Constants after function instructions
and declarations after module constants are rejected. Limits are 262,144
constants/declarations, 4,194,304 decoded 64-bit words, and 262,144 copied argument
type references. Existing stream/type/function limits apply. Record buckets
avoid rescanning the stream per function: work is linear in records, blocks,
scopes, arguments, decoded words and aggregate operands. Large zero aggregates
are represented without expanding their elements.

`constants_test.v` uses deliberate semantic fixtures for exact bit patterns,
value scope isolation, forward references, 26 directed corruptions, 768 scalar
bit mutations, resource caps and 512 scopes using implicit i32. These are not
executable shaders. The maintained V tool `tests/ios/air-constants-inspect.v`
provides independent encoded-input validation:

- `inspect FILE.bc` prints typed pool/word/opaque counts.
- `self-test LLVM_AS LLVM_BCANALYZER FRESH_EXTERNAL_DIR` generates portable LLVM
  IR fixture data, assembles it with LLVM, checks 15 known literal bit patterns,
  five non-scalar tags, argument/local IDs and an independent trace inventory,
  then rejects eight corrupted inventories. The fixture includes NaN payloads,
  negative zero, 65/128/130-bit integers, embedded NULs, aggregate references and
  an unevaluated GEP expression. The portable fixture is not an iOS application.
- `corpus INPUT_DIR LLVM_DIS LLVM_BCANALYZER FRESH_EXTERNAL_DIR` copies every
  `module-*.bc`, runs both independent LLVM tools, and compares declaration
  counts, SETTYPE state, constant code/order and module/local value IDs against
  LLVM's raw bitcode trace. It preserves each raw stream, disassembly, trace and
  exit status. This inventory comparison does not independently evaluate every
  native literal or opaque expression; exact bit semantics have separate tests.

Build with the same frozen V toolchain and normal/sanitizer flags documented in
[README.md](README.md). Keep generated inputs, binaries and results outside Git.
The native corpus consists of copied macOS framework AIR; Fortnite's packed
shaders have not been covered. Metal's default device remains unavailable.
The [metadata layer](METADATA.md) links classic AIR entry points to stages and
bindings; the [body index](BODIES.md) adds instruction-result IDs and block
boundaries. Constant expression lowering, typed operand/instruction decoding
and the actual execution backend remain future work.

Format reference: [LLVM's constant reader](https://github.com/llvm/llvm-project/blob/main/llvm/lib/Bitcode/Reader/BitcodeReader.cpp).
