# AIR vector shuffle checkpoint — 2026-11-05

`bb1d786a66164ae05e3753fb90149f9775216eca` adds typed shuffle operands and
constant masks after the [call decoder](air-calls-checkpoint-20261105.md).
Fortnite remains at **4/8 observed launch gates**, last seen at the
[Apple family 3 GPU requirements alert](controller-discovery-checkpoint-20261104.md).
No rendered game frame, menu, login or playable match is verified. The gate count
is not an engineering completion percentage.

SHUFFLEVEC retains both input value IDs/types, the constant mask ID, the input
vector type and the inferred result type. DATA/aggregate/zero/undef/poison masks
become normalized lane indexes into the two inputs; `~u32(0)` represents poison
or legacy undef. Negative integer literals and out-of-range lanes are rejected.
Scalable masks support zero/undef/poison splats only; stored lanes represent the
minimum pattern, not a fixed runtime width. Constant expressions remain deferred
without evaluation. Deferred expansion rolls back its operand/index ranges.

Masks share the bounded aggregate-index arena. The program still owns six arrays
and borrows original type names; the builder temporarily borrows the immutable
Stream to read aggregate constants. Generated C confirms this assignment does
not clone the Stream arrays. See [API, ownership and limits](../../compat/ios/airbitcode/OPERANDS.md).
This profile does not execute vector selection or establish LLVM validity.

Optimized and ASan/UBSan unit runs pass four groups, including fixed/scalable
shapes, exact IDs, width changes, forward claims, opaque dependencies and mask
rollback. Fourteen directed malformed cases, the expansion-budget rejection and
75 operand/aggregate mutations pass. Existing core and call sanitizer suites
also pass; their unknown-producer fixtures now use still-opaque VAARG. Leak
detection is disabled; leaks were not measured.

The V inspector independently assembles a valid portable LLVM shuffle fixture.
Normal and sanitized runs verify ten decoded instructions, zero opaque/deferred
entries and five complete function indexes. It covers fixed/pointer/scalable
vectors, width changes and zero/undef/poison masks. Both input types, mask type,
every normalized lane and inferred result shape are checked. All eight corrupted
dump/index controls are rejected. Existing core, memory and call LLVM fixtures
and their three eight-control sets pass under sanitizers. No fixture was
executed as a shader or iOS application.

All 430 copied native modules pass the expanded sanitized LLVM comparison.
Existing opcode, selected type, memory and call checks remain. Native value/input
identities, CFG edges, raw flags/attributes, ABI layout and opaque families remain
outside the comparison. It expects normal LLVM instruction indentation. All
three outer runs and 430 disassembler subprocess statuses are zero.

| Copied native corpus | Modules | Decoded | Opaque | Deferred | Complete function indexes |
| --- | ---: | ---: | ---: | ---: | ---: |
| Contacts | 1 | 29 | 0 | 0 | 1 |
| MetalFX | 90 | 74,452 | 20 | 2,397 | 67 |
| SceneKit | 339 | 31,214 | 75 | 1,368 | 397 |
| Total | 430 | 105,695 | 95 | 3,765 | 465 |

The statuses account for all 109,555 previously indexed instructions. Complete
function indexes describe this partial decoder; they do not qualify executable
shaders. Samples come from macOS frameworks; Fortnite's packed shaders remain
untested. The shuffle unit program cross-compiles/links as a static little-endian
AArch64 Linux ELF and passes header inspection. It has not run in a guest.

Complete evidence is retained outside Git at:

`/Users/alex/Library/Caches/vinix-ios/air-shuffle-validation-20261105-r1/`

It contains committed source, native libraries/raw modules, LLVM outputs/statuses,
fixtures, binaries, build/run logs, tool/input identities and reproduction notes.
Final corpora use `final`; unit files are `unit-normal`/`unit-asan`, inspectors
are `inspect-normal`/`inspect-asan` and fixtures use `normal`/`asan`. An early
attempt to start SceneKit before its inspector build finished is preserved;
the completed final run passes. Compiler/SDK closures are not sealed.

The unchanged complete inventory checker passes. A fresh full archive restore
under `air-shuffle-restoration-20261105-r1/` matches every recorded path, byte,
size, type and permission. Its optimized unit program and sanitized shuffle
fixture with all eight corruption controls pass again. Archive and receipt
hashes remain unchanged after restoration.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-shuffle-validation-20261105-r1.inventory.json` | `43c5828fdc54ac09f29a0ede7a7dcd2382eb2afaf0e3a482693d0b6bd74c7b78` |
| `air-shuffle-validation-20261105-r1.tar.zst` | `e834f4b8ae395765b39969253fc27db9e3e50b47efbdcea11b76243dbb6b1329` |
| `source.tar`, revision `bb1d786a6` | `e2948748ecc4018e8330449b349b5d1f1828c1ff16dab122bde112616de72fb2` |
| `unit-aarch64` | `983a4209af7f93317b6d22052dff1a2a816f1178ea1867021ea96c44fe527f68` |

No runtime Metal capability changed and no new Fortnite probe was run. The
default Metal device remains nil. Atomic/control families, ABI layout,
expression/instruction/intrinsic lowering, resource/pipeline objects, command
execution and presentation still need implementation. The prior game capture
and historical auditor rejection are unchanged. This checkpoint does not qualify
shader execution or another game launch milestone.
