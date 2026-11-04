# AIR type and function index

After `stream := airbitcode.parse(data)!`, call `ir := stream.ir_module(data)!`
to index a single LLVM module version 2. This adds a semantic layer to the raw
bitstream reader: module strings, types and type references, function names and
signatures, declaration flags and function body/block counts. Bodies pair with
non-declaration functions in module order. Record and body-block indexes refer
to the original `Stream`, for later instruction decoding.

The input must be the same immutable bytes used by `parse`. Function names borrow
its STRTAB blob. The IR index owns its three arrays, module text and identified
struct names. Call `ir.free()` once; `stream.free()` and input cleanup remain
separate. Do not construct or mutate indexes manually in production code.

Supported type records are the scalar LLVM primitives (void, float, double,
label, half, x86_fp80, fp128, ppc_fp128, metadata, x86_mmx, token, bfloat,
x86_amx), integers, typed and opaque pointers, arrays, fixed/scalable vectors,
anonymous/identified structs, opaque identified structs and modern function
types. Integer widths, address spaces, dimensions, packed/vararg flags, operand
counts, reference bounds and element/return/argument categories are checked.
Only identified structs can be forward referenced. Duplicate struct/function
names, dangling struct names, malformed STRTAB ranges, missing/extra bodies and
invalid DECLAREBLOCKS records are rejected. Unsupported type records and module
versions fail explicitly. This is a strict profile, not a general LLVM reader.

Limits: 65,536 types/functions, 262,144 type references, 4 MiB combined text/name
work, 64 KiB per module/type text field, 4 KiB per function name, and 65,536 basic
blocks per function. The underlying bitstream input/output limits still apply.
`ir.type_text(type_index)!` produces LLVM type text for inspection with opaque
pointer spelling. Original pointee references remain in the type index.
Formatting is limited to 64 KiB, depth 64 and 65,536 visits. It stops at identified
struct names, so recursive types need not be expanded.
The returned text is owned by the caller; free it when using `-gc none`.

Constants, attributes, metadata links, instruction operands, symbol value IDs,
control flow and data-layout size/alignment rules remain opaque or unverified.
Calling convention and linkage fields are retained as encoded numbers. The
index does not establish that a module is executable, select AIR entry points,
translate a shader or enable Metal capabilities.

`ir_test.v` uses deliberate semantic record fixtures for precise corruptions;
these are not standalone executable bitcode. It checks recursive types, legacy
and opaque pointers, signatures, packed/scalable types, name escaping, ownership,
48 directed corruptions, 6,400 operand bit mutations and expansion/render limits.
Real encoded modules are separately checked by `tests/ios/air-ir-inspect.v`:

- `inspect FILE.bc` prints type/function counts and decoded signatures.
- `compare FILE.bc LLVM.ll` compares every function name, opaque-pointer signature,
  declaration flag and basic-block count plus triple, data layout and source name
  against an independent `llvm-dis` result. It does not compare instructions,
  attributes or original typed-pointer pointees. Function order can change when
  LLVM upgrades intrinsic declarations, so the comparison uses a bijection of
  names rather than list positions.
- `corpus INPUT_DIR LLVM_DIS FRESH_EXTERNAL_DIR` compares every `module-*.bc`,
  preserving each raw input, LLVM disassembly, log and exit status externally.
- `negative-controls CONTACTS.bc CONTACTS.ll` compares the Contacts fixture and
  rejects 12 changed headers/signatures/names/declarations/block counts/traces.

LLVM 23 changes typed-pointer memory intrinsic suffixes and the legacy two-argument
lifetime declarations. The inspector explicitly accounts for those changes;
lifetime adaptation requires the original `void(i64, i8 addrspace(N)*)` prototype
and the matching pointer suffix. The decoded AIR index keeps its original
signatures and names. Other unhandled upgrades fail comparison. The current
corpus covers copied macOS frameworks; Fortnite's packed shaders remain untested.

See LLVM's [type and module format](https://llvm.org/docs/BitCodeFormat.html),
[bitcode reader](https://github.com/llvm/llvm-project/blob/main/llvm/lib/Bitcode/Reader/BitcodeReader.cpp)
and [intrinsic upgrades](https://github.com/llvm/llvm-project/blob/main/llvm/lib/IR/AutoUpgrade.cpp).
