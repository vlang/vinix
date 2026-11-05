# AIR instruction/value and block checkpoint — 2026-11-05

`112c94f9d030c74b122133356ec2edd527b6d23d` adds structural AIR function-body
indexing after the [entry metadata layer](air-metadata-checkpoint-20261105.md).
It assigns instruction result IDs and basic-block ranges for later typed operand
decoding. Fortnite remains at **4/8 observed launch gates**, last seen at the
[Apple family 3 GPU requirements alert](controller-discovery-checkpoint-20261104.md).
No rendered game frame, menu, login or playable match is verified. The gate count
is not an engineering completion percentage.

`ir.function_bodies(stream, pools)` indexes instructions, scopes, terminated
blocks and result lookups. IDs follow module values, arguments and local
constants; different function scopes reuse numeric IDs independently. Void calls
consume no result ID. Explicit CALL/INVOKE/CALLBR types determine return presence,
with their different flag/destination layouts retained correctly. Non-void
invoke/callbr and catchswitch can both terminate a block and produce a result.
Auxiliary metadata, debug and bundle records consume no instruction/value slots.
Unknown/reserved codes and implicit call types fail rather than shifting IDs.

Checks cover declared/completed block agreement, instruction placement, PHI
grouping, direct branch arity/targets, call prefixes and minimum operand counts.
Four arrays have explicit cleanup; record buckets keep traversal linear. Result
types other than explicit call signatures, typed operands/references, arithmetic
opcode semantics, most CFG edges, dominance, callee compatibility and execution
remain outside this layer. See [API and limits](../../compat/ios/airbitcode/BODIES.md).

Optimized and ASan/UBSan unit runs pass four groups, including 34 directed
malformed cases and 135 scalar operand mutations. Coverage includes pooled value
lookup, local ID reuse, void/value/FMF calls, auxiliary records, terminating
results, block cap and declaration isolation. The metadata sanitizer regression
also passes all seven existing groups. Leak detection is disabled; these runs
do not measure leaks.

The maintained V inspector assembles portable LLVM fixture data with LLVM 23.1.0.
Normal and sanitized runs check 15 instructions, six results and nine blocks,
covering bundled/void/value calls, invoke, callbr, PHI, switch, landingpad and
resume. All ten corrupted-dump/index controls are rejected. The fixture checks
data format and indexing, not an executable iOS shader.

Final sanitized corpus runs independently disassemble every copied raw module.
The comparison checks opcode families, result presence, terminators, per-block
instruction extents, sequential IDs after the existing pooled prefix and result
lookups. It does not compare operands, exact arithmetic opcodes or result types,
or independently derive the raw pooled prefix. It relies on LLVM's standard
primary-instruction indentation and ignores continuation lines. All three outer
runs and 430 LLVM subprocess statuses are zero.

| Copied native corpus | Modules | Instructions | Result IDs | Blocks |
| --- | ---: | ---: | ---: | ---: |
| Contacts | 1 | 29 | 24 | 4 |
| MetalFX | 90 | 76,869 | 65,615 | 7,389 |
| SceneKit | 339 | 32,657 | 28,244 | 2,711 |
| Total | 430 | 109,555 | 93,883 | 10,104 |

These are macOS framework AIR samples from the previous pinned extraction.
Fortnite's packed shaders remain untested. The final unit program also
cross-compiles/links as a static little-endian AArch64 Linux ELF and passes
header inspection; it has not run in a guest.

Complete evidence is retained outside Git at:

`/Users/alex/Library/Caches/vinix-ios/air-bodies-validation-20261105-r1/`

It includes committed source, native libraries/raw streams, LLVM disassemblies
and statuses, generated fixtures, host/target binaries, build logs, intermediate
attempts, source/tool identities and reproduction notes. Final corpora and most
final binaries have `final` in their names; `inspect-normal` and its
`llvm-fixture-normal` run are also final. Compiler/SDK closures are not sealed.
The complete typed inventory passes rechecking. A fresh archive restoration under
`air-bodies-restoration-20261105-r1/` matches every recorded path, byte, size,
type and permission. Its optimized unit program and sanitized LLVM fixture with
all ten corruption controls pass again. Archive and receipt hashes remain
unchanged after restoration.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-bodies-validation-20261105-r1.inventory.json` | `89c7f17e7ecebb329025acaae85dba23f4eea9de5cf3ee262f49554b00f4e34a` |
| `air-bodies-validation-20261105-r1.tar.zst` | `8e83ee1b7b167d4ced3330add1ad00f51d9da9058d8e4beee508af2ed8b718ae` |
| `source.tar`, revision `112c94f9d` | `58797f630e003da3e35070b65ddd3ddfa3af15131b02eb8be44e54b491b95f3d` |
| `unit-aarch64-final` | `6915c5f8628c36e9602092d9a9183dc728fea7599c489bb4c3f913f4114f6a11` |

No runtime Metal capability changed and no new Fortnite probe was run. The
default Metal device remains nil. Typed operand/instruction decoding, expression
and instruction lowering, resource/pipeline objects, command execution and
presentation remain to be implemented. The earlier game capture and historical
auditor rejection are unchanged. This checkpoint does not qualify shader
execution or another game launch milestone.
