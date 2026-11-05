# AIR call operand checkpoint — 2026-11-05

`4c5928ba030ddb4ecbc0949c4b12b35f4836ec4e` adds typed CALL operands after the
[memory/aggregate decoder](air-memory-checkpoint-20261105.md). Fortnite remains
at **4/8 observed launch gates**, last seen at the
[Apple family 3 GPU requirements alert](controller-discovery-checkpoint-20261104.md).
No rendered game frame, menu, login or playable match is verified. The gate count
is not an engineering completion percentage.

Ordinary explicit-type calls retain the callee, fixed/vararg value operands,
signature, direct function identity, attribute-list ID, packed header, calling
convention and optional fast-math flags. Function declaration pointers preserve
typed/opaque representation and explicit/default program address spaces.
Forward callee claims and argument types use the existing final definition check.
Void calls consume no result ID. Two transient declaration tables are freed;
the returned program still owns six arrays and borrows original type names.

Bundled calls and fixed metadata/label/token arguments remain opaque; invoke and
callbr remain opaque. The body index now records bundle presence so later layers
cannot silently drop it. Unknown callee/argument types defer the call while
preserving known result types. Other global declarations remain untyped.
Attributes, tail legality, convention compatibility and intrinsic behavior are
unverified. Recognizing an AIR intrinsic supplies no execution semantics.
See [API, ownership and limits](../../compat/ios/airbitcode/OPERANDS.md).

Optimized and ASan/UBSan unit runs pass four call groups, including direct/
indirect/void/vararg calls, exact scoped IDs, typed/opaque declarations, program/
explicit address spaces, CC/attributes/tail/FMF, forward claims and unsupported
states. All 19 directed malformed cases and 365 operand/header mutations pass.
Existing core, memory and body sanitizer regressions pass. Leak detection is
disabled; leaks were not measured.

The V inspector independently assembles a valid portable LLVM call fixture.
Normal and sanitized runs check seven decoded instructions, two opaque calls,
zero deferred entries, one complete function index and eight rejected evidence
corruptions. Coverage includes indirect calls, nested vector varargs, void IDs,
flags and bundled/metadata states. The core fixture now has 29 decoded entries,
zero opaque/deferred entries and five complete function indexes; the memory
fixture has 12 decoded entries and three complete indexes. Both original
eight-control sets pass under sanitizers. No fixture was executed as a shader.

All 430 copied native modules pass the final sanitized LLVM comparison. The new
call comparison checks direct callee names, argument counts/types and return
types or vararg signatures. Specific legacy lifetime/memory intrinsic upgrades
are normalized in LLVM's disassembly only; original AIR operands stay intact.
Existing exact opcode, selected type and memory-field checks remain. Native
value/indirect-callee identities, CFG edges, raw flags/attributes, ABI layout and
opaque families are outside this comparison. Text parsing requires normal LLVM
indentation and named @/% callees. All three outer runs and 430 disassembler
subprocess statuses are zero.

| Copied native corpus | Modules | Decoded | Opaque | Deferred | Complete function indexes |
| --- | ---: | ---: | ---: | ---: | ---: |
| Contacts | 1 | 29 | 0 | 0 | 1 |
| MetalFX | 90 | 70,015 | 1,166 | 5,688 | 27 |
| SceneKit | 339 | 24,481 | 2,484 | 5,692 | 183 |
| Total | 430 | 94,525 | 3,650 | 11,380 | 211 |

All 109,555 previously indexed instructions are accounted for. Added argument
checks move some former opaque calls to deferred when their definitions remain
unknown. Complete function indexes describe this partial decoding profile;
they do not establish valid or executable shaders. These are macOS framework
samples; Fortnite's packed shaders remain untested. The call unit program links
as a static little-endian AArch64 Linux ELF and passes header inspection. It has
not run in a guest.

Complete evidence is retained outside Git at:

`/Users/alex/Library/Caches/vinix-ios/air-calls-validation-20261105-r1/`

The bundle contains committed source, native libraries/raw modules, LLVM outputs
and statuses, generated fixtures, host/target binaries, build logs, intermediate
failures, tool/input identities and reproduction notes. Final inspectors and
fixtures/corpora use `final`; unit files are `unit-normal-final` and `unit-asan`.
Compiler/SDK closures are not sealed. The unchanged complete inventory checker
passes. A full fresh restore under `air-calls-restoration-20261105-r1/` matches
all recorded paths, bytes, sizes, types and permissions. Its optimized unit and
sanitized call fixture with eight corruption controls pass again. Archive and
receipt hashes remain unchanged after restoration.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-calls-validation-20261105-r1.inventory.json` | `dbe2ab1211cf72b9a5d7fc25642298e7f71e52315b802f539dfe43d567338894` |
| `air-calls-validation-20261105-r1.tar.zst` | `c5571d357ad764447e34bf79653e5996d79bc094b3d475d99b9ce03c8488a468` |
| `source.tar`, revision `4c5928ba0` | `dea83463fa4b962fe6b3c5e62b0e5ce52ac95ccd92e93d50c13314a9e184c0ef` |
| `unit-aarch64` | `a9babc65ad5cb0e5bf4dde4b7591aa1d2ae2f88440c3ddd8c3d3ff6681c9fb74` |

No runtime Metal capability changed and no new Fortnite probe was run. The
default Metal device remains nil. Atomic/control families, ABI layout,
expression/instruction/intrinsic lowering, resource/pipeline objects, command
execution and presentation still require implementation. The prior game capture
and historical auditor rejection are unchanged. This checkpoint does not qualify
shader execution or another game launch milestone.
