# AIR type layout

`l := ir.type_layouts()!` computes sizes and alignments for the original type
table using the module's data-layout string. After typed operand decoding,
`l := p.type_layouts(ir)!` includes synthetic types as well. Entry indexes match
the corresponding type table. Both APIs require the existing immutable, parsed
indexes; they do not validate an arbitrary manually constructed type graph.

The result owns two arrays, `entries` and `field_offsets`, and borrows no data.
Call `l.free()` once. Each entry has an explicit status:

- `fixed`: sizes and alignments are available, including zero-sized aggregates.
- `unsized`: opaque, void, function, label, metadata or token type, a by-value
  cycle, or an aggregate containing such a type.
- `unsupported`: scalable vectors, x86 MMX/AMX types, or aggregates containing
  an unsupported type. No runtime vscale is assumed.

Consume size/alignment fields only for `fixed` entries. `size_bits` retains
non-byte scalar/vector widths. `store_size` is rounded up to whole bytes;
`alloc_size` additionally includes ABI padding and supplies array stride.
`abi_alignment` and `preferred_alignment` are bytes. Fixed structures reference
their field offsets through `fields_start`/`fields_count`; offsets are relative
to the structure. Packed structures use byte field alignment but still consume
each field's allocation size. Aggregate ABI alignment can further pad allocation
without changing the structure's stored size. Preferred aggregate alignment
uses field ABI alignment, rather than each field's preferred alignment.

Pointers retain their address space's width, ABI/preferred alignment and
`pointer_index_bits`. Unspecified address spaces inherit the default pointer
specification. Pointer layout does not require a sized pointee, so recursive
pointer structures work. Arrays use element allocation stride. Fixed vectors
pack element bits and use an explicit vector alignment or natural power-of-two
alignment; this includes sub-byte integers and non-byte pointer widths.

`d := airbitcode.parse_data_layout(text)!` exposes the layout profile separately.
It owns four specification arrays; call `d.free()` once. Treat its arrays as
immutable, preserving the sorted specifications and mandatory default pointer.
`d.pointer_layout(space)` returns a value. The default profile is little endian,
64-bit pointers aligned to eight bytes, LLVM integer/FP defaults and aggregate
ABI/preferred alignment of one/eight bytes. In particular, default i64 ABI
alignment is four bytes and preferred alignment is eight. Integer alignment
uses the next wider specification, falling back to the widest. FP/vector
specifications match exactly, otherwise using natural alignment.

The parser accepts `e`/`E`, `p[AS]:size:abi[:preferred[:index]]`, `i`/`f`/`v`
alignment specifications and `a:abi[:preferred]`. Repeated specs use the last
value. It validates size-neutral `n`, `A`/`P`/`G`, `S`, `m` and `Fi`/`Fn` hints.
These hints are not retained or used to place objects or implement calling
conventions. Unknown semantics, including non-integral pointer extensions and
legacy `a0` spelling, fail explicitly. This is a bounded profile, not a general
LLVM data-layout parser or verifier.

Limits: 64 KiB of layout text, 4,096 components/specifications per category,
24-bit numeric widths/address spaces, power-of-two byte alignments encoded in
at most 65,535 bits, 327,682 types, 524,288 type references, 262,144 output field
offsets and recursion depth 64. All size arithmetic checks u64 overflow.
Malformed specifications, reference ranges, overflows and work limits return
errors with owned arenas released. Status values are not fallback sizes.

`type_layout_test.v` uses semantic fixtures for exact sizes, padding, packed and
recursive structures, pointer/index widths, overrides, status propagation,
malformed profiles, overflow, depth and mutations. The V checker
`tests/ios/air-layout-inspect.v` links LLVM's C API and offers:

- `self-test FRESH_EXTERNAL_DIR`: compare 96 fixed type layouts and 24 field
  offsets across four profiles; reject eight changed layout results.
- `corpus INPUT_DIR FRESH_EXTERNAL_DIR`: copy each `module-*.bc`, parse it with
  Vinix, and compare all fixed type layouts and structure field offsets.

The checker constructs matching LLVM types from the already indexed graph.
LLVM TargetData independently computes bit/store/allocation sizes, ABI/preferred
alignments and field offsets. It also checks byte order. This qualifies the
layout calculation, not the type decoder independently. Unsized/unsupported
entries are counted and excluded; pointer index width is unit-tested but not
independently compared through the C API. LLVM itself is not sanitizer-built.
The checker currently uses Homebrew LLVM headers/library under
`/opt/homebrew/opt/llvm`; build with the [README flags](README.md).

This layer does not compute GEP byte offsets, allocate globals/buffers, enforce
load/store alignment, evaluate instructions, lower shaders or enable Metal
capabilities. The typed operand decoder retains its existing behavior. Native
macOS samples provide layout coverage; Fortnite's packed shaders remain untested.

References: [LLVM data layout](https://llvm.org/docs/LangRef.html#data-layout),
[implementation](https://github.com/llvm/llvm-project/blob/main/llvm/lib/IR/DataLayout.cpp)
and [TargetData C API](https://llvm.org/doxygen/group__LLVMCTarget.html).
