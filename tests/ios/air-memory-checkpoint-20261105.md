# AIR memory and aggregate operand checkpoint — 2026-11-05

`c5ceba3d104618e9af072812544fc55e8df7d32e` extends the
[partial typed operand decoder](air-operands-checkpoint-20261105.md) with
non-atomic load/store, alloca, legacy/modern GEP and extractvalue/insertvalue.
Fortnite remains at **4/8 observed launch gates**, last seen at the
[Apple family 3 GPU requirements alert](controller-discovery-checkpoint-20261104.md).
No rendered game frame, menu, login or playable match is verified; the gate count
is not an engineering completion percentage.

Descriptors retain accessed/source types, explicit byte alignment, volatility,
allocation address spaces and literal aggregate paths. Alloca count IDs are
absolute. Its optional address space overrides the data-layout `A` default.
Pointer interning preserves typed/opaque representation, address spaces and
vector shapes. Mixed pointer tables explicitly reject alloca rather than guess.
Legacy implicit-pointee forms require an available typed pointer. The program
owns six arrays; original type names remain borrowed from the owning IR module.
See [API, ownership and limits](../../compat/ios/airbitcode/OPERANDS.md).

Instructions retain `decoded`, `opaque` and `deferred` states. Function
completeness only describes this decoder profile. It does not establish LLVM
validity, dominance, supported lowering or execution. Alignment 0 leaves the ABI
default unresolved. Size, padding, pointer width, GEP byte offsets and memory
access are unimplemented. Unsized/cyclic storage types are not fully verified.
Calls, atomics, shuffle, switches and other families remain opaque.

Optimized and ASan/UBSan memory unit runs pass four groups, including explicit/
legacy forms, absolute count IDs, typed/opaque pointers, vector GEP, aggregate
paths, default/explicit address spaces, unresolved/maximum alignment,
26 directed malformed cases and 125 operand mutations. All five existing core
sanitizer groups also pass. Leak detection is disabled; leaks were not measured.

The V inspector independently assembles a portable LLVM memory fixture. Normal
and sanitized runs check 12 decoded instructions, zero opaque/deferred entries,
three complete function indexes and eight rejected evidence corruptions.
Coverage includes scalar/vector GEP, aliasing accesses, volatile load/store,
explicit alloca AS5, alignment and aggregate paths. A semantic unit fixture
separately checks default A5. The expanded existing core fixture passes under
sanitizers with 28 decoded instructions, one opaque entry, zero deferred entries,
four complete function indexes and its eight corruption controls. No fixture
was executed as a shader or iOS application.

All 430 copied native modules pass the final sanitized LLVM comparison. It checks
instruction counts for every status, and exact opcode/selected type spellings
for decoded instructions. Memory forms additionally compare source/base pointer
types, explicit alignment, volatility, alloca address space and literal aggregate
paths. Native value IDs/values, branch/PHI identities, dynamic GEP edges/offsets,
raw flags, ABI layout and opaque families remain outside this comparison.
The comparator expects normal LLVM instruction indentation. All three outer
runs and 430 disassembler subprocess statuses are zero.

| Copied native corpus | Modules | Decoded | Opaque | Deferred | Complete function indexes |
| --- | ---: | ---: | ---: | ---: | ---: |
| Contacts | 1 | 20 | 9 | 0 | 0 |
| MetalFX | 90 | 63,137 | 8,862 | 4,870 | 1 |
| SceneKit | 339 | 21,017 | 6,574 | 5,066 | 21 |
| Total | 430 | 84,174 | 15,445 | 9,936 | 22 |

These statuses account for all 109,555 previously indexed instructions. Samples
come from macOS frameworks; Fortnite's packed shaders remain untested. The final
memory unit program cross-compiles/links as a static little-endian AArch64 Linux
ELF and passes header inspection. It has not run in a guest.

Complete evidence is retained outside Git at:

`/Users/alex/Library/Caches/vinix-ios/air-memory-validation-20261105-r1/`

It contains committed source, native libraries/raw streams, LLVM disassemblies
and statuses, generated fixtures, host/target binaries, build logs, intermediate
attempts, source/tool identities and reproduction notes. Final sanitized files
and corpora use `final`, except `core-regression-asan-checked`; optimized files
are `unit-normal`, `inspect-normal` and `memory-fixture-normal`. Compiler/SDK
closures are not sealed. The unchanged complete typed inventory checker passes.
A fresh full archive restore under `air-memory-restoration-20261105-r1/` matches
every recorded path, byte, size, type and permission. Its optimized unit program
and sanitized memory fixture with all eight corruption controls pass again.
Archive and receipt hashes remain unchanged after restoration.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-memory-validation-20261105-r1.inventory.json` | `cf0ded69599fbb520ada209469470de353394d5d49582d1b7173ed5c10ea777b` |
| `air-memory-validation-20261105-r1.tar.zst` | `06d83b750acb8cac3c0701ece83620049b3cafca35da8e09fd3fd808d78e18bc` |
| `source.tar`, revision `c5ceba3d1` | `6dda55920e660f273e036ca6ca57271ac5662321086096e1dff54ae47a40786c` |
| `unit-aarch64` | `000653f14ff2ac12852e156dc93cd929f2b56e87923e36cfb1be9e153d982e4a` |

No runtime Metal capability changed and no new Fortnite probe was run. The
default Metal device remains nil. Remaining work includes call/atomic operands,
ABI layout, expression/instruction lowering, resource/pipeline objects, command
execution and presentation. The prior game capture and its historical auditor
rejection are unchanged. This checkpoint does not qualify shader execution or
another game launch milestone.
