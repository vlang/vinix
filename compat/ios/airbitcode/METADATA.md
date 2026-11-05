# AIR entry metadata

After `parse(data)`, `stream.ir_module(data)` and `ir.constant_pools(stream)`,
call `md := ir.module_metadata(data, stream, pools)!`, then
`entries := md.air_entries(ir, pools)!`. All inputs must describe the same
immutable raw module. This layer reflects classic `air.vertex`, `air.fragment`
and `air.kernel` roots; it does not lower their ABI or execute shaders.

`IRMetadata` owns its node, edge and named-root arrays and all string bytes.
Call `md.free()` once. String bytes are copied from the input, including embedded
NULs. Tuple edges use normalized metadata IDs, with -1 for null. Named-root
operands use the bitcode's direct numbering; nullable tuple operands use its
one-based numbering before normalization. Forward references and cycles are
retained without recursive expansion. `tuple()` and `text()` return borrowed
data; do not free them. `integer()` accepts an integer constant of at most
64 bits, returning its original bits without sign extension.

Only one module-level metadata block is indexed. Function-local blocks remain
in `Stream`. String tables, old strings, typed values, ordinary/distinct tuples
and named roots are decoded. Known debug and legacy allocating records retain
opaque node slots; their internal schemas/references are not verified. Known
non-allocating attachment/index records remain opaque in `Stream`. Unknown
record codes fail rather than silently shifting metadata IDs.

`AIREntries` owns two flat arrays; call `entries.free()` once, before freeing
`md`. Argument strings borrow `md`. Other indexes refer to `md`, `ir`, `pools`
and `stream`, so retain those while interpreting reflection. Each entry resolves
to a unique defined function, with exactly one input descriptor per fixed
parameter. Variadic shader signatures are rejected. Argument indices are
unique, may appear out of order, and select the corresponding signature type.
Kernels require an empty output tuple and a void return type.

The reflected fields are argument semantic/name/type name, location range,
address space, size/alignment, buffer size, access mode and unused flag. Known
fields reject duplicates and malformed values; an address-space attribute must
match a pointer parameter. `has_*` flags distinguish absent values from zero.
Access flags are independent of the semantic and do not establish resource
compatibility. Output descriptors remain raw tuples.

Conditional arguments retain their predicate tuple without evaluating it.
Structure layout, fragment linkage/interpolation, extra entry operands (such as
tessellation metadata) and unknown attribute tails remain raw. Unknown tails
are not skipped by guessing their arity. `opaque_attributes` indicates retained
entry/argument fields outside this profile. It is not a capability flag; even
an entry without opaque attributes still needs ABI and instruction lowering.
Additional stage roots remain available in `md` and are not advertised as
classic entries. No runtime Metal capability changes.

Limits are 262,144 metadata nodes, 1,048,576 edges, 65,536 named roots, 4 MiB of
copied text and 65,536 bytes per string/name. Entry expansion is bounded by the
IR layer's 262,144-reference limit. Cleanup runs on success and error. Limits
bound decoded storage independently of compression; opaque node internals are
not validated by this layer.

`metadata_test.v` covers ID conventions, owned strings and borrowed reflection,
stages, binding fields, malformed graphs/properties, resource boundaries,
mutations and opaque tails. `tests/ios/air-metadata-inspect.v` supports:

- `inspect FILE.bc`: decode metadata and print reflected entries/arguments.
- `compare FILE.bc LLVM.ll`: compare classic-stage rooted graphs with independent
  `llvm-dis` output, including tuple shape/distinctness, string bytes, integer
  bits, symbols/address spaces and nulls. Metadata IDs may differ. Debug/legacy
  opaque nodes and unsupported value types inside these roots fail comparison.
  Other named roots and unreferenced nodes are outside this comparison.
- `corpus INPUT_DIR LLVM_DIS FRESH_EXTERNAL_DIR`: copy raw streams, retain LLVM
  disassembly/logs/statuses, and compare each module. It does not test packed
  Fortnite shaders, instruction execution or native Metal pipeline reflection.
- `self-test LLVM_AS LLVM_DIS FRESH_EXTERNAL_DIR`: assemble portable LLVM fixture
  data, check known reflection for all three stages and reject eleven corrupted
  LLVM graphs. Includes conditional globals, escaped/NUL bytes and null/cycles.

Use the [bitstream README's build flags](README.md). Retain evidence outside Git.
The numeric record definitions and reference rules follow
[LLVMBitCodes.h](https://github.com/llvm/llvm-project/blob/main/llvm/include/llvm/Bitcode/LLVMBitCodes.h)
and [MetadataLoader.cpp](https://github.com/llvm/llvm-project/blob/main/llvm/lib/Bitcode/Reader/MetadataLoader.cpp).
