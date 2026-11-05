# AIR switch operand checkpoint — 2026-11-05

`77d634ed7affe17a9dbb380805ead484e37f3fe0` adds ordinary switch decoding after
the [vector shuffle layer](air-shuffle-checkpoint-20261105.md). Fortnite remains
at **4/8 observed launch gates**, last seen at the
[Apple family 3 GPU requirements alert](controller-discovery-checkpoint-20261104.md).
No rendered game frame, menu, login or playable match is verified. The gate count
is not an engineering completion percentage.

Switches retain their scalar integer type, relative condition ID, absolute
constant case IDs and ordered default/case destinations. Wide case bits remain
in the owning constant pools. Duplicate values are rejected across distinct IDs
and implicit/materialized zero; shared destinations and empty tables are allowed.
Transient duplicate keys clone borrowed pool bytes and are freed after each
switch. Generated C confirms the map's clone/free callbacks. A cumulative
4,194,304-word work cap includes implicit zero widths. The program still owns six
arrays and borrows original type names. See [API and limits](../../compat/ios/airbitcode/OPERANDS.md).

Unknown condition definitions defer the switch. The reverted legacy range
encoding remains explicitly opaque. Decoding does not evaluate conditions or
establish CFG reachability, dominance, LLVM validity or supported lowering.

Optimized and ASan/UBSan unit runs pass four groups, including exact scoped IDs,
default/case ordering, i128 literals, shared targets, empty tables and unsupported
states. All 18 directed malformed cases, the cumulative budget rejection and
93 record/limb mutations pass. The existing core sanitizer suite also passes.
Leak detection is disabled; leaks were not measured.

The V inspector independently assembles a valid portable LLVM fixture. Normal
and sanitized runs verify 13 decoded instructions, zero opaque/deferred entries
and four complete function indexes. Coverage includes signed/boolean/i128 cases,
empty tables, shared targets and quoted labels containing semicolons. All eight
corrupted dump/index controls are rejected. Existing core, memory, call and
shuffle LLVM fixtures and their four eight-control sets pass under sanitizers.
No fixture was executed as a shader or iOS application.

The expanded oracle compares exact switch case bits and every default/case
destination using independently read LLVM block order. Its separate decimal
parser supports comparison widths up to 4096 bits. Native cases include i8/i16/
i32; fixtures include i1/i32/i128. Existing opcode/type/memory/call/shuffle checks
remain. Condition value identities, branch/PHI edges, flags/attributes, ABI
layout, opaque families and execution remain outside the comparison. Normal
LLVM instruction layout is required. All three final sanitized outer runs and
430 disassembler subprocess statuses are zero.

| Copied native corpus | Modules | Decoded | Opaque | Deferred | Complete function indexes |
| --- | ---: | ---: | ---: | ---: | ---: |
| Contacts | 1 | 29 | 0 | 0 | 1 |
| MetalFX | 90 | 74,472 | 0 | 2,397 | 67 |
| SceneKit | 339 | 31,289 | 0 | 1,368 | 438 |
| Total | 430 | 105,790 | 0 | 3,765 | 506 |

All 109,555 previously indexed instructions are accounted for. Zero opaque
instructions applies to these samples; other LLVM families remain unsupported.
Complete function indexes describe this partial profile, not executable shaders.
These are macOS framework samples; Fortnite's packed shaders remain untested.
The switch unit program links as a static little-endian AArch64 Linux ELF and
passes header inspection. It has not run in a guest.

Complete evidence is retained outside Git at:

`/Users/alex/Library/Caches/vinix-ios/air-switch-validation-20261105-r1/`

It contains committed source, native libraries/raw modules, LLVM outputs/statuses,
fixtures, binaries, build/run logs, tool/input identities and reproduction notes.
Corpora use `final`; unit/inspector files use `normal`/`asan`, as do the fixtures.
Compiler/SDK closures are not sealed. The unchanged complete inventory checker
passes. A fresh full restore under `air-switch-restoration-20261105-r1/` matches
all recorded paths, bytes, sizes, types and permissions. Its optimized unit and
sanitized switch fixture with eight corruption controls pass again. Archive and
receipt hashes remain unchanged after restoration.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-switch-validation-20261105-r1.inventory.json` | `05f290eee77fe8e1a988115e23214229d15ba6373adf719b212647f429ed0336` |
| `air-switch-validation-20261105-r1.tar.zst` | `ed18a6c4f8dfa674196203d3d3d0833fd75e7fd05acb255f7600fa7f9bc633f0` |
| `source.tar`, revision `77d634ed7` | `103a58d8dcdc8dbac86455f4bf85c78dae38ecc43aa527fed8c4076a5a39c793` |
| `unit-aarch64` | `ed3eeae589faf085f5b765bf644b9357f4f2e3573487c1aaf544dc48ef87f236` |

No runtime Metal capability changed and no new Fortnite probe was run. The
default Metal device remains nil. Remaining work includes deferred definitions,
unsupported opcode families, ABI layout, expression/instruction/intrinsic
lowering, resource/pipeline objects, command execution and presentation. The prior
game capture and historical auditor rejection are unchanged. This checkpoint
does not qualify shader execution or another game launch milestone.
