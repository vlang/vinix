# Scalar integer execution checkpoint — 2026-11-05

`0605721503c033bbb203c97df915d97fb3585d54` adds a bounded V interpreter for
scalar integer functions in the decoded IR. Fortnite remains at **4/8 observed
launch gates**, last seen at the [GPU requirements alert](controller-discovery-checkpoint-20261104.md).
No rendered game frame, menu, login or playable match is verified. The gate
count is not an engineering completion percentage.

The supported profile covers i1 through i64 arithmetic, all integer predicates,
trunc/zext/sext, select, branches, simultaneous PHIs and return. It preserves
widths, wrapping and poison; division guards avoid host undefined behavior.
Selected undef, unsupported expressions, poison branches, nonzero instruction
flags, function attributes and unsupported instruction families reject. A
caller-supplied instruction budget bounds loops at up to one million steps.
Each invocation borrows its indexes and frees its three temporary arrays on
return or error. See [INTEGER.md](../../compat/ios/airbitcode/INTEGER.md).

Execution requires valid LLVM IR and matching immutable indexes. Preflight
checks profile shapes, ranges and types; it does not prove dominance or full
CFG/PHI validity. Memory, pointers, calls, floating point, vectors, intrinsics
and Metal execution remain outside this implementation. The production
interpreter uses no native function addresses and has no LLVM dependency.

Optimized and ASan/UBSan unit runs pass four groups: exact arithmetic and all
predicates, narrow/wide wrapping, scoped arguments/constants, both branch paths,
precise budgets, infinite-loop exhaustion, lazy select, poison returns,
unsupported flags/attributes and narrow argument/return masking. Existing
sanitized operand and body suites pass, including their ownership checks,
20/34 directed corruptions and 125/135 mutations respectively. Leak detection
is disabled; leaks were not measured.

The maintained V reference tool generates portable LLVM IR, assembles it,
independently parses it with LLVM and verifies it before MCJIT compilation.
Both optimized and sanitized runs compare **15,616 actual native-reference
calls** against the interpreter: 122 functions with 128 input triples each.
The functions cover arithmetic/comparisons at i1/i8/i16/i32/i64, extension casts,
a branch diamond, select and a loop with simultaneous swapping PHIs. Reference
division and shift inputs avoid undefined/poison execution. Nine guarded cases
and two poison results run only in the V interpreter. All four corrupted-result
controls reject. Source, bitcode, assembler status, target identity and every
comparison/step count are preserved. LLVM and its generated machine code are
not sanitizer-instrumented. This tool executes only its generated fixture.

The unit program cross-compiles and links as a static little-endian AArch64
Linux ELF and passes header inspection. It has not run in a guest. No native
AIR corpus scan, AIR shader execution, iOS app execution, GPU workload or new
Fortnite probe occurred in this checkpoint. The default Metal device remains nil.

Complete evidence is retained outside Git at:

`/Users/alex/Library/Caches/vinix-ios/air-integer-validation-20261105-r1/`

The bundle contains committed source, generated fixtures, binaries, logs,
identities and reproduction notes. Final binaries/results use `final`. Earlier
passes predate the last scope guard/fourth unit group. The initial target link
failure from a mistaken `crtendT.o` filename is retained; retrying with
`crtend.o` passes. Compiler, SDK, LLVM dependency, JIT and sanitizer runtime
closures are not sealed. Installed tool/library identities pass recheck.

The unchanged complete inventory checker passes. A full fresh restore under
`air-integer-restoration-20261105-r1/` matches every recorded path, byte, size,
type and permission. Restored unit and sanitized native-reference runs pass
again, including all 15,616 comparisons and guarded/control cases. Sibling
restore/replay logs preserve the results. Archive and inventory hashes remain
unchanged; these checks establish evidence integrity, not a game milestone.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-integer-validation-20261105-r1.inventory.json` | `0f8292508c1ae15c009610021adb4abae34877a198dc554a1ddb9d04cd26970c` |
| `air-integer-validation-20261105-r1.tar.zst` | `662698d9ab5f4df80b4bd1547157a7ac3ca06abd6d3526b22f1eef13d9321959` |
| `source.tar`, revision `060572150` | `32278601a55b55f77d4871054018a6601e0fec3f9bc21078b77c16f5a1ddf69d` |
| `unit-aarch64-final` | `c183a7ecd545fcf793b0715e2c482171d1f29022d145effff1939e499d3e870d` |

Global storage, remaining instruction/expression/intrinsic lowering, resource
and pipeline objects, command execution and presentation remain unfinished.
The prior game capture and historical auditor rejection are unchanged. This
checkpoint qualifies portable scalar IR execution only.
