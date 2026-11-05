# AIR constant memory images

After building matching immutable `Stream`, `IRModule`, `IRConstantPools` and
`layouts := ir.type_layouts()!`, call
`image := pools.constant_image(ir, stream, layouts, constant_index)!`.
The image owns two arrays, `bytes` and `value_mask`; call `image.free()` once.
It borrows no module/index data. Original type IDs/layouts are required, without
the typed program's additional synthetic types.

`status == .complete` supplies allocation-sized bytes. Scalar numeric values use
the module byte order, preserving literal integer/FP bits without host floating
point conversion. Arrays use element allocation stride; fixed vectors pack
byte-sized elements using store stride. Structures use ABI field offsets,
including packed structures. Strings include their decoded terminator. Scalar
splats and aggregate references expand with scoped constant IDs. Empty aggregates
remain complete with zero bytes.

`value_mask` is allocation-sized: `0xff` marks value bytes and `0` marks ABI
padding. Padding is deterministically filled with zero in `bytes`, but its value
is unconstrained by LLVM. Do not treat those bytes as prescribed literal bits.
The mask covers scalar allocation padding, vector tail padding and recursive
aggregate padding. This profile requires byte-aligned values; it does not
describe individual bits within a partially defined byte.

Supported scalar values are byte-aligned integers, half/bfloat/float/double,
IEEE fp128 and null pointers. Fixed arrays, vectors and structures may contain
those types. Non-byte integer/vector elements, x86_fp80/ppc_fp128, scalable and
unsized types are unavailable, including zero values in unsupported shapes.
Zero-length arrays need no element bytes. Non-null pointers require relocation
or expression support and are not guessed.

`status == .unavailable` returns both arrays empty and a reason: `undef`, `poison`,
`expression`, `relocation` or `unsupported`. A nested unavailable value makes
the entire image unavailable; partial bytes are discarded. Expressions remain
opaque, pointer declarations remain unresolved, and undef/poison are never
silently replaced with zero. Reasons describe the first unavailable dependency
encountered, not every dependency in an aggregate.

Malformed index/range/type references, constant cycles and exceeded budgets
return errors. Limits are 8 MiB per image array, depth 64 and 1,048,576 combined
type/value expansion visits. Existing stream/type/pool limits apply. These APIs
require parsed immutable indexes, not arbitrary manually constructed graphs.
Both output arrays are released on failure or unavailability. Successful arrays
are independent of their input indexes; the caller frees them once.

`constant_image_test.v` checks exact little/big endian bytes, i24/i128, NaN
payloads, signed zero, bfloat/fp128 bits, ordinary/packed fields, array/vector
strides and padding masks, null/string/empty values, unavailable dependencies,
malformed ranges and byte/expansion/depth limits. Semantic fixtures deliberately
exercise normalized layouts; they are not executable shaders.

The V tool `tests/ios/air-image-inspect.v` uses LLVM's C API:

- `self-test LLVM_AS FRESH_EXTERNAL_DIR` assembles little/big endian fixtures,
  materializes their constants, checks selected value bytes and padding masks,
  and rejects four corrupted byte/endian/size/mask controls.
- `corpus INPUT_DIR FRESH_EXTERNAL_DIR` copies every `module-*.bc`, preserving
  folded LLVM IR and image/byte/availability counts per module.
- `inspect FILE.bc EXTERNAL_FOLDED_LL` diagnoses one module; choose a fresh
  external output path.

The oracle reconstructs matching LLVM types/constants from the already decoded
graph/pool. LLVM TargetData independently checks allocation size and queried
payload/padding classification. LLVM `instcombine` folds byte loads from constant
globals and compares the resulting bytes. Images up to 16 bytes query every
position; larger images query positions 0, 1, 2, 3, middle, penultimate and last.
Padding queries check the mask and chosen zero, without comparing LLVM's free
choice of padding bits. Nonconstant folded results are counted as unresolved
and excluded from byte qualification. Always inspect these coverage counts.

The oracle does not independently decode native type/literal bits, compare every
byte of large images or qualify relocation, undef/poison, expression evaluation
or shader execution. No generated function executes or dereferences host memory.
LLVM itself is not sanitizer-built. Build using the [README flags](README.md);
the inspector currently links Homebrew LLVM under `/opt/homebrew/opt/llvm`.
Production materialization uses V only and does not depend on LLVM.

An image is data for future initialization/lowering. It does not allocate guest
globals, enforce pointer provenance, execute load/store instructions or enable
Metal capabilities. Fortnite's packed shaders remain untested.

References: [LLVM constants and memory](https://llvm.org/docs/LangRef.html#constants)
and [LLVM constant load folding](https://github.com/llvm/llvm-project/blob/main/llvm/lib/Analysis/ConstantFolding.cpp).
