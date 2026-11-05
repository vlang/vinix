# AIR global variable descriptors

After building matching immutable raw bytes, `Stream`, `IRModule` and
`IRConstantPools`, call `g := ir.global_variables(data, stream, pools)!`.
The result owns one `entries` array. Call `g.free()` once. Names borrow the raw
input's STRTAB bytes and must not be freed separately; retain that input while
using the descriptors. No global storage is allocated.

Each entry retains its original declaration value ID (`number`) and raw record.
Function, alias and ifunc declarations leave holes in these IDs and are not
variable entries. The array order follows GLOBALVAR records. `type_index` is
the storage element type. Legacy pointer headers unwrap their pointee/address
space; explicit headers supply storage type and address space separately. A
pointer stored in a global can have a different address space from the global.

`has_initializer` distinguishes definitions from external declarations. Present
initializers retain their original module value ID in `initializer_number`;
the on-disk encoding is that ID plus one. A pool constant also supplies its pool
index in `initializer`. Direct references to declarations retain -1 there and
require relocation. Pool-constant types must match the storage type. Direct
declaration references require pointer storage; full target type/address-space
and symbol resolution remain linker work.

`is_constant`, raw encoded `linkage`, explicit byte `alignment`, TLS mode and
`externally_initialized` are retained. Alignment 0 preserves the request for a
default; it does not assert an inferred alignment. Other nonzero optional fields
(section, visibility, unnamed address, DLL storage, comdat, attributes, preemption,
partition, sanitizer or code model) and unknown record extensions set
`opaque_properties`. Their raw operands stay in `Stream`. Linkage remains an
encoded value, without implementing interposition, merging or initialization.

`image := g.initializer_image(ir, stream, pools, layouts, entry_index)!` uses
`ir.type_layouts()` and the [constant-image layer](IMAGE.md) to materialize a
declared initializer template. It owns independent bytes/padding-mask arrays;
call `image.free()` once. An external declaration or direct declaration reference
returns an unavailable relocation image. Other unavailable constants retain
their existing reasons. A complete image is a template, including for TLS or
externally initialized globals; it does not establish initialized program state.
Those storage, threading and initialization rules still need implementation.

This is a bounded module-v2 profile. It checks name extents/NULs/duplicates,
including collisions with function names, while allowing anonymous globals.
Limits: 65,536 globals, 4,096 bytes per name and 4 MiB of combined global name
references. Existing declaration/type/constant limits apply. Initializer bounds,
module scope, storage categories, address-space width, explicit alignment, TLS
mode and boolean initialization flags are checked. It is not a general global
property verifier. Unsized storage may be indexed; image availability remains
explicit. Matching parsed immutable indexes are required.

`globals_test.v` uses semantic fixtures for borrowed names, declaration-ID holes,
legacy/explicit types, address spaces, exact initializer IDs, images, anonymous
globals, flags and direct relocations. It checks 20 directed corruptions and
112 record/name bit mutations. The inspector `tests/ios/air-globals-inspect.v`
provides:

- `self-test LLVM_AS FRESH_EXTERNAL_DIR`: assemble little/big endian fixtures,
  compare original LLVM global properties/types and initializer bytes, and
  reject 11 corrupted descriptor/image controls.
- `corpus INPUT_DIR FRESH_EXTERNAL_DIR`: preserve every `module-*.bc`, folded
  initializer oracle IR and counts externally.

LLVM independently parses each original bitcode input. The checker compares
global order/count, names, recursive storage shapes, scalar widths, address
spaces, constant flag, initializer presence, explicit alignment, TLS/external
initialization flags and normalized linkage. Typed-pointer pointees are not
compared through LLVM's opaque-pointer API. Legacy linkage encodings can map to
the same LLVM linkage, so raw codes are not independently distinguished.

For complete images it copies LLVM's actual decoded initializer into a separate
constant-global oracle module, leaving the original shader module untouched.
TargetData checks sizes and queried padding masks; instcombine folds byte loads.
Every position is queried up to 16 bytes, otherwise positions 0,1,2,3,middle,
penultimate,last. Padding is checked for mask/chosen zero without equating LLVM's
unconstrained bits. Unresolved loads are counted and excluded. This qualifies
selected original initializer bytes, not every large-image byte, native value
IDs, opaque properties, symbol resolution, TLS behavior or shader execution.
No original or generated function executes or dereferences host/guest memory.

Build with the [README flags](README.md); the checker links Homebrew LLVM under
`/opt/homebrew/opt/llvm`, which is not sanitizer-built. Production descriptors and
images use V only. macOS framework inputs do not qualify Fortnite's packed
shaders or enable Metal capabilities.

References: [LLVM global records](https://llvm.org/docs/BitCodeFormat.html#module-code-globalvar-record)
and [LLVM reader](https://github.com/llvm/llvm-project/blob/main/llvm/lib/Bitcode/Reader/BitcodeReader.cpp).
