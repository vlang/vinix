# AIR global pointer typing checkpoint — 2026-11-05

`00a362cd343969fe3edc2c36a35b1b6a7bf13da0` resolves global variable pointer
types after the [switch decoder](air-switch-checkpoint-20261105.md). This removes
all 3,765 deferred instructions from the retained native corpus. Fortnite remains
at **4/8 observed launch gates**, last seen at the
[Apple family 3 GPU requirements alert](controller-discovery-checkpoint-20261104.md).
No rendered game frame, menu, login or playable match is verified. The gate count
is not an engineering completion percentage.

The diagnostic found 2,783 loads, 826 stores, 149 GEPs, four casts and three calls
deferred before this change. Global variable records now provide pointer types
to dependent instructions. Legacy records retain an encoded typed pointer;
explicit-element records retain address spaces and the original typed/opaque
pointer representation. No-pointer tables use opaque pointers; mixed tables
reject explicit globals rather than guess. Aliases and ifuncs remain untyped.
Initializer, storage, linkage, name and attribute schemas are unverified and no
global initialization occurs. The program still owns six arrays; original type
names remain borrowed. See [API and limits](../../compat/ios/airbitcode/OPERANDS.md).

Optimized and ASan/UBSan unit runs pass four groups, covering pointer profiles,
exact IDs, address spaces, dependent accesses and preserved alias/ifunc deferral.
All ten directed malformed cases and 285 declaration/operand mutations pass.
Existing call and memory sanitizer suites also pass. Leak detection is disabled;
leaks were not measured.

The V inspector independently assembles a valid portable LLVM global fixture.
Normal and sanitized runs verify eight decoded entries, one deferred alias
access and one complete function index. Scalar/array/pointer globals, accessed
types/address spaces, exact declaration IDs and eight corrupted dump/index
controls pass. The five existing core/memory/call/shuffle/switch LLVM fixtures
and their five eight-control sets pass under sanitizers. No fixture was executed
as a shader or iOS application.

All 430 copied native modules pass the final sanitized LLVM comparison, covering
all 109,555 indexed instructions with no opaque or deferred entries. The separate
diagnostic confirms those totals without invoking LLVM. All three outer corpus
runs and 430 disassembler subprocess statuses are zero.

| Copied native corpus | Modules | Decoded | Opaque | Deferred | Complete function indexes |
| --- | ---: | ---: | ---: | ---: | ---: |
| Contacts | 1 | 29 | 0 | 0 | 1 |
| MetalFX | 90 | 76,869 | 0 | 0 | 284 |
| SceneKit | 339 | 32,657 | 0 | 0 | 536 |
| Total | 430 | 109,555 | 0 | 0 | 821 |

Completeness describes this partial decoding profile, not fully verified or
executable shaders. Selected opcode/type/memory/call/shuffle/switch comparisons
retain their documented limits. Global initializer values, ABI layout, general
native operand identities, branch/PHI edges, flags/attributes, other instruction
families and execution remain unqualified. These are macOS framework samples;
Fortnite's packed shaders remain untested. The unit program cross-compiles/links
as a static little-endian AArch64 Linux ELF and passes header inspection. It has
not run in a guest.

Complete evidence is retained outside Git at:

`/Users/alex/Library/Caches/vinix-ios/air-definition-validation-20261105-r1/`

It includes committed source, native libraries/raw modules, LLVM outputs/statuses,
fixtures, binaries, build/run logs, the preliminary deferral diagnostic, tool/input
identities and reproduction notes. Final corpora use `final`; unit files are
`unit-normal`/`unit-asan`, inspectors are `inspect-normal-final`/`inspect-asan`, and
the final diagnostic is `deferred-after`. Compiler/SDK closures are not sealed.

The unchanged complete inventory checker passes. A full fresh restore under
`air-definition-restoration-20261105-r1/` matches every recorded path, byte, size,
type and permission. Its optimized unit and sanitized global fixture with all
eight corruption controls pass again. Archive and receipt hashes remain
unchanged after restoration.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-definition-validation-20261105-r1.inventory.json` | `8198a2f7f34bebe5c9f949637b6106a14d1d7775c5e77da63865b6c6ad08616e` |
| `air-definition-validation-20261105-r1.tar.zst` | `007042d2fbd9f2fda185f4a1a735c56c2a78b65b177f897591e5d2661529b9cf` |
| `source.tar`, revision `00a362cd3` | `9268576c7d06bc1eb1f6e912453986ad35b52425433f9c664ac985dc29d78250` |
| `unit-aarch64` | `3c15edb43ecda9a628f829dfded1fbb5c8f94aeffec2ad9f4d0dc86b3d76d870` |

No runtime Metal capability changed and no new Fortnite probe was run. The
default Metal device remains nil. Remaining work includes ABI layout, global
initialization, expression/instruction/intrinsic lowering, resource/pipeline
objects, command execution and presentation. The prior game capture and
historical auditor rejection are unchanged. This checkpoint does not qualify
shader execution or another game launch milestone.
