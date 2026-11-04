# AIR constant/value-ID checkpoint — 2026-11-05

`0ca7dbd3845e6baceaefcac342b48edb3b1716c2` adds typed constant pools and scoped
value-ID lookup to `compat/ios/airbitcode`, following the
[type/function index](air-ir-checkpoint-20261105.md). It supplies exact literal
bits and module/argument/local-constant identities for future metadata and
instruction decoding. Fortnite remains at **4/8 observed launch gates**, last
seen at the [Apple family 3 GPU requirement alert](controller-discovery-checkpoint-20261104.md).
No game frame, menu, login or playable match is verified; the gate count is not
an engineering completion percentage.

`ir.constant_pools(stream)` indexes module declarations, module constants,
arguments and definition-local constants. Each function has a distinct scope;
identical numeric local IDs resolve independently. It checks SETTYPE state,
scope/order, supported literal schemas, aggregate counts/reference bounds and
constant element types. Signed-VBR integers, wide limbs, integer/FP splats,
floating bit patterns, DATA sequences and strings decode without host FP
conversion. Numeric zero, undef, poison, aggregates and known opaque expressions
retain distinct tags. Scalar reads reject unsupported/non-scalar values.
Nonuniform vector data is distinguished from uniform literals.

Five arrays have explicit cleanup. Record buckets keep traversal linear;
constants/declarations, argument references and expanded words have independent
limits. Large zero aggregates do not expand. See the [API and limits](../../compat/ios/airbitcode/CONSTANTS.md).
Declaration schemas, instruction-result IDs, full expression/aggregate-graph
verification and expression evaluation remain outside this layer.

Normal optimized and ASan/UBSan unit runs pass five groups: value scopes and
forward references; 24 exact bit/shape cases; 26 directed corruptions plus
resource limits; 768 scalar-bit mutations with bounded results; and 512 isolated
scopes using implicit i32. The existing type/signature sanitizer regression also
passes. Leak detection is disabled; these runs do not measure leaks.

The maintained V inspector generates portable LLVM IR fixture data and uses
LLVM 23.1.0 to assemble it. Both normal and sanitized self-tests verify 15 known
literal bit patterns, five non-scalar tags, argument/local IDs and eight rejected
inventory corruptions. Coverage includes NaN payloads, negative zero,
65/128/130-bit integers, embedded NULs, huge zero aggregates and an explicitly
unevaluated GEP expression. These are data-format fixtures, not iOS applications.

The final sanitized native corpus independently runs `llvm-dis` and
`llvm-bcanalyzer` for every copied raw module. Its trace comparison checks
module declaration counts, SETTYPE state, constant code/order, function scopes
and value IDs. All three corpus runs and 860 LLVM process statuses are zero.
This inventory comparison does not independently evaluate every native literal
or opaque expression; exact literal semantics have separate fixture tests.

| Copied native corpus | Modules | Constants | Decoded words | Opaque expressions |
| --- | ---: | ---: | ---: | ---: |
| Contacts | 1 | 18 | 15 | 0 |
| MetalFX | 90 | 8,595 | 7,557 | 138 |
| SceneKit | 339 | 15,183 | 13,530 | 370 |
| Total | 430 | 23,796 | 21,102 | 508 |

These are macOS framework AIR samples from the previous checksum-pinned
extraction. Fortnite's packed shaders remain untested. The portable unit program
also cross-compiles/links as a static little-endian AArch64 Linux ELF and passes
header inspection. That target binary has not been executed in a guest.

Complete evidence is retained outside Git at:

`/Users/alex/Library/Caches/vinix-ios/air-constants-validation-20261105-r1/`

It contains committed source, copied native libraries/raw streams, complete LLVM
traces/disassemblies/statuses, generated LLVM fixtures, host/target binaries,
build logs, intermediate checks, tool identities and reproduction notes. Final
source host artifacts/corpus trees use `checked` in their names. Compiler/SDK
closures are not sealed. The typed inventory passes rechecking. A fresh complete
archive restoration under `air-constants-restoration-20261105-r1/` matches every
recorded path, byte, size, type and permission. Its normal unit binary and
sanitized LLVM-generated fixture/eight-control check pass again.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-constants-validation-20261105-r1.inventory.json` | `47b678965e31e31649258256b9beb157457afc69bee926284debb72af730c5ff` |
| `air-constants-validation-20261105-r1.tar.zst` | `fc07a96a7c606a4342151f543b4b1eaf9a9b4d607b1fb5493471d08a41a1eb57` |
| `source.tar`, revision `0ca7dbd38` | `019f039b6bf1ec0bd1adee110cade9fb1d4ab7b705e2693e6fcaeed2d6361a5e` |
| `unit-aarch64` | `69d816decf9b981b3ad6fe1d902c0309bd6593184ab6842c52672f8633692982` |

No runtime capability changed and no new Fortnite probe was run. Metal's default
device remains nil. Entry-point metadata, instruction-result IDs, expression and
instruction lowering, resource/pipeline objects, command execution and
presentation remain to be implemented. Advertising and the previous capture's
historical auditor rejection are unchanged. This checkpoint does not qualify
shader execution or another game launch milestone.
