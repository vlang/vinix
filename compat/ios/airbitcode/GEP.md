# AIR GEP offset plans

After decoding typed operands and `layouts := p.type_layouts(ir)!`, call
`plan := p.gep_offset_plan(stream, pools, bodies, layouts, instruction_index)!`.
All inputs must come from the same immutable parsed module. This layer accepts
decoded GEP records (legacy codes 4/30 and modern code 43), scalar pointers and
scalar integer indexes. Pointer and pointer-index widths must be at most 64 bits.
Vector-shaped GEP results/indexes and unsized/scalable layouts fail explicitly.
This is a bounded arithmetic profile, not a general LLVM interpreter.

The plan owns one `terms` array. Call `plan.free()` once; it borrows no index or
module storage. Each term identifies an absolute index in `p.operands`, its
integer bit width and byte stride. Sequential indexes, including constant ones,
remain terms; the caller supplies their values. Structure indexes must resolve
to materialized scalar i32 constants in the original pool. Their byte offsets
are folded into `constant_offset`, modulo the pointer index width.

`plan.offset(values)!` takes one u64 per term in order. Supply the low 64 bits of
each scalar index. Bits above a narrow input width are ignored; narrower indexes
are sign-extended to the pointer index width and wider indexes are truncated.
High limbs of indexes wider than 64 bits cannot affect this profile's offsets.
Arithmetic wraps modulo the pointer index width. The result is an unsigned bit
pattern, including when the mathematical offset is negative.

`plan.address(base, values)!` adds that offset to the low index-width bits of a
numeric base, preserving its higher pointer bits and masking to the pointer
width. It does not form a host pointer or access memory. The first index uses
the source type's allocation stride. Array steps use element allocation stride;
vector element steps use packed store stride and require byte-addressable fixed
elements. Structure steps use the ABI field offsets, including packed fields.
Sequential indexes are not bounds checked, including zero-length arrays.

`flags` retains the original raw GEP flags. The arithmetic helpers do not enforce
inbounds/no-wrap poison rules, pointer provenance, object bounds, undefined or
poison operands, lifetimes or access permissions. A computed number does not
establish a valid LLVM result or a legal memory access. Consumers must implement
those semantics before using this plan for instruction execution. The plan does
not materialize constants, resolve runtime values, initialize globals or lower
memory instructions.

Input range/layout checks and existing type/operand limits apply. A plan has at
most one term per sequential index, bounded by the 4,194,304 typed-operand cap.
Output arrays are freed on failure. Layouts must match the complete original and
synthetic program type table; manually constructed or mutated index graphs are
not a supported production input. Treat plans as immutable after construction.

`gep_layout_test.v` uses semantic fixtures to check exact term identities, field
offsets, signs, truncation/wrapping, high pointer bits, packed and array/vector
strides, i128 low limbs, empty paths and unsupported/malformed inputs.
`tests/ios/air-gep-inspect.v` links the LLVM C API and offers:

- `self-test LLVM_AS FRESH_EXTERNAL_DIR`: assemble three portable LLVM profiles,
  compare 12 scalar plans and 72 numeric address probes, count three excluded
  vector-shaped GEPs and reject six corrupted plan controls.
- `corpus INPUT_DIR FRESH_EXTERNAL_DIR`: parse every `module-*.bc`, compare six
  substitutions for every scalar GEP, count excluded vector-shaped GEPs and keep
  raw modules, folded LLVM output and count receipts.

The checker reconstructs matching LLVM types from the decoded graph. It builds
flag-free constant GEPs with synthetic numeric bases/index values, then runs
LLVM's `instcombine` and compares the folded integer addresses. LLVM independently
calculates GEP arithmetic from its module data layout. Term operand identities
and widths are also checked against the decoded inputs. This comparison does
not independently qualify the type decoder, native operand identities, original
constant values, original flags, vector lanes, poison semantics or execution of
the original function. No generated function is executed or dereferences memory.
The production plan retains flags; only the arithmetic oracle strips them.

The checker currently uses Homebrew LLVM headers/library under
`/opt/homebrew/opt/llvm`; build with the [README flags](README.md). LLVM itself is
not sanitizer-built. macOS framework samples establish format/arithmetic
coverage, not Fortnite shader execution or Metal capability.

References: [LLVM GEP semantics](https://llvm.org/docs/LangRef.html#getelementptr-instruction),
[offset calculation](https://github.com/llvm/llvm-project/blob/main/llvm/lib/IR/Operator.cpp)
and [sequential stride rules](https://github.com/llvm/llvm-project/blob/main/llvm/include/llvm/IR/GetElementPtrTypeIterator.h).
