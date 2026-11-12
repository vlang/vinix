# Software Metal constant buffer indexing — 2026-11-13

`7287d3247` adds forward constant GEPs to AIR memory execution and the opt-in
software Metal compute path. Array, packed/unpacked structure and fixed
byte-addressable vector elements can be selected, including chains of earlier
GEP results. Pointers remain a binding identity and checked byte offset;
they never become AIR-supplied host addresses or scalar machine values.

The profile requires explicit little-endian data layouts, 64-bit pointer/index
widths and defined nonnegative i1..i64 index literals. Source allocation sizes,
strides, multiplication and accumulated offsets are bounded by 64 MiB.
Known inbounds/nusw/nuw flags are accepted within this nonwrapping profile;
unknown bits reject. All intermediate/unused derived pointers must fit the
binding extent. One-past pointers are allowed; dereferences require more bytes.
Access alignment is checked for both binding and derived offsets. An owned
per-instruction access table is freed with the profile. GEPs cost one step.
See [MEMORY-EXECUTION.md](../../compat/ios/airbitcode/MEMORY-EXECUTION.md).

Normal and ASan/UBSan checks pass 59,520 native LLVM copy comparisons across
465 functions, with 128 byte-pattern samples each. Coverage includes i1..i64,
half/float, six GEP flag forms, chained pointers, packed/unpacked structure
padding and vector-element versus array allocation stride. Narrow integer high
padding bits are masked in the native reference; the interpreter must zero
them. Whole destination buffers and five/six-step budgets are checked.
Nine preflight guards cover negative, poison, undef, wide, overflowing and
dynamic indexes, misalignment, unused one-past extents and one-past
dereferencing. Rejections preserve earlier store destinations. Additional
controls reject absent/unsupported pointer layouts and unknown flags, and
accept the decoded legacy inbounds mask.

MCJIT uses its native host data layout for execution; the fixture's explicit
scalar/pointer layout matches the referenced host types. The resulting native
layout is retained. This is not native execution of arbitrary target layouts.
Final results are in `normal-complete.log` and `asan-complete.log`; the earlier
MCJIT layout-compatibility failure remains in the bundle. LLVM-generated native
code is not sanitizer-instrumented; the interpreter/checkers are.

All 23 software Metal groups pass ASan/UBSan with normal and deterministic
Swift hashing. An indexed integer kernel observes writes after encoding,
combines GEP and binding offsets, preserves neighboring bytes and rejects a
derived out-of-bounds binding before recording. The existing 16,896 copy and
107,776 arithmetic regressions pass under sanitizers, as do the three GEP
offset-planner groups and their 18 rejection controls. The ordinary runner was
not rebuilt for this opt-in change.

Evidence bundle:

`/Users/alex/Library/Caches/vinix-ios/air-memory-gep-validation-20261113-r1/`

Its sibling archive was decoded and fully extracted to fresh `-restored`.
Saved source/compiler/header/executable identities match. Restored sanitizer
executables pass all five suites again, using fresh external fixtures; the
archive checksum passes afterward. Restore receipts remain beside the bundle.
The current compiler snapshot was saved after checks. The software harness
retains its documented compiler-preamble corrections; toolchain library
symlinks, SDKs, assembler and dylibs remain external prerequisites. Complete
dependency closures are not sealed. This is not a full typed-inventory audit.

This remains a single-thread CPU compute profile. Dynamic/negative indexing,
branches, general LLVM attributes, builtins, vector values, texture operations
and GPU execution remain unsupported. Valid LLVM IR remains a precondition.
The Metal compiler CLI is unavailable here; fixtures are synthetic LLVM/AIR,
not Apple compiler-produced Metal libraries. Leak detection is disabled;
runtime object drainage is checked, retained heap is not measured. No guest,
native Metal kernel, Fortnite frame or new launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `50ffa4a371b19f6cb13c62c88267093e483053a960975ddd81851ce198a61e83` |
| `source.tar`, revision `7287d3247` | `b55b88d0f2fe9dda33dee53d31ab8d9f2cd86706cb8a7aa21c3ec3d08f3723a2` |
