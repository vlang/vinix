# Software Metal memory-call alignment — 2026-11-14

`0194f16ac74e5fbf55ac0fe1d817f64c90a132be` admits pointer `align N`
at bounded AIR memset, memmove and memcpy call sites. Destination and source
requirements combine with ordinary accesses in each binding's profile. The
virtual base alignment and binding offset satisfy the combined requirement;
each derived pointer offset independently satisfies its own call requirement.
Compensating binding offsets cannot rescue unaligned derived pointers.

Only alignment is admitted: power-of-two values 1 through 64 MiB, on the
destination and transfer source. Other slots/properties, including alignment
combined with noundef, nonnull or dereferenceable, reject before stores.
Scalar-call and declaration allowlists retain their exclusions. A fixed
sixteen-slot stack cache uses full attribute-set identities; collisions
revalidate. Scans share the existing cumulative declaration-work budget.
The cached profile owns no new array. Software Metal retains its separate
256-byte virtual base-alignment limit.

The [LLVM alignment attribute](https://llvm.org/docs/LangRef.html#parameter-attributes)
specifies a pointer alignment promise. This conservative interpreter profile
checks every block, including inactive and zero-length calls. Zero length
still adds no read/write usage and permits empty readonly bindings; it does
not waive alignment or existing GEP extents.

ASan/UBSan `tests/ios/air-memory-alignment.v` passes 16,169 native LLVM
comparisons. Its 252 main functions cover memset/memmove/memcpy, i32/i64
lengths, destination spaces 0/1 and source space 2, destination alignments
1..64 and independent source requirements. Native backing views are physically
256-byte aligned; binding offsets 0/64 exercise both bases. A 64-call mixed
body combines stronger/weaker requirements, asserts more than sixteen distinct
attribute sets and real cache-slot collisions, and executes 189 steps.
Nine direct zero-length bodies cover destination spaces 0/1/2, aligned empty
readonly bindings and poison fill bytes without evaluating them.

All 779 binding/compensating/zero controls, 252 short budgets and six
derived/untaken/combined-attribute guards pass before marker stores. Main
fill/transfer bodies execute exactly 24/41 steps. The complete LLVM module
is verified; rejection-only guard bodies are removed from native compilation
and `native-input.bc` is retained. Invalid alignments never execute natively.
Four memory-attribute unit groups cover all powers through 64 MiB and
slot/kind/group/order/duplicate/work-limit exclusions.

Sanitized regressions pass 25,970 memcpy, 42,546 memmove and 90,130 memset
native comparisons with their existing controls, totaling 174,815 with the
alignment suite. The old alignment exclusion fixtures now check unsupported
alignment plus noundef. Four scalar-intrinsic groups also pass, including
327,680 integer square-root inequalities. All 24 software Metal groups pass
in both Swift hash modes. Deferred fill, overlapping move and disjoint copy
kernels now carry explicit call alignment through the pipeline path; retained
resources, changed inputs after encoding and drained runtimes still pass.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-alignment-validation-20261114-r1.tar.zst`

The 188 MiB bundle retains final/preliminary binaries, generated fixtures,
results, build receipts, compiler snapshots, generated host C, LLVM headers,
selected identities and source.tar pinned to the feature revision. Preliminary
checker compilation and evidence-manifest failures remain in their receipts;
qualification uses `*-verified` binaries and the `software` host.
Decode with `zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

A completed fresh extraction replaced the original bundle path. The unchanged
maintained `tests/packages/wine-workspace-archive.v` checker matches all file
bytes, sizes, types, modes and link targets, including the root; selected
identities match. All eight restored runs pass: four reference suites, two
unit binaries and both host hash modes with separate output roots. Complete
bundle inventory and archive checksum match after replay. A fresh extraction
of `.replay.tar.zst` matches its complete inventory. Original expanded bundle
and replay trees remain alongside restored evidence.

The standalone compiler snapshot was saved after builds; the harness captured
its compiler before generation. External SDKs, assembler, library symlinks
and dylibs remain unsealed prerequisites. Native MCJIT code is not sanitizer
instrumented. Leak detection is disabled; retained heap was not measured.
The ordinary runner was not rebuilt. This remains single-thread CPU execution
of synthetic LLVM fixtures. No Apple-produced shader, GPU rendering,
presentation, Vinix guest, Fortnite frame or launch gate is newly verified.
Integrity checks do not replace historical launch auditors.

| Artifact | SHA-256 |
| --- | --- |
| Complete `.tar.zst` | `7798dd88c557ccfd523c0320bde853d742dc36d85799317803d58001d08fa9bf` |
| `.inventory.json` | `a7ff10d33fab51b9facb3318818d5a2b6e4e0af9a3daca9cbb2ef39675703173` |
| `.replay.tar.zst` | `2b0f7383230449f316325c9d4416811ec1d8d39153576bf034a1317b515fee94` |
| `.replay-inventory.json` | `9295d7f5f14e488cd87d38549b709d4f79fe75d83d5fa34f55b332af73f81925` |
| `source.tar`, revision `0194f16ac` | `222c8e755ab355a934e75e0ce0b9c6389f6f0fff8bd83b92b50052bd52e75734` |
