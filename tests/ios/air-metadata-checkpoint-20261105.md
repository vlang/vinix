# AIR entry metadata checkpoint — 2026-11-05

`2d041b961e9bc3423df58f7f9383956a584aa26b` adds module metadata and classic AIR
entry reflection after the [constant/value-ID decoder](air-constants-checkpoint-20261105.md).
It links shader definitions to vertex, fragment or kernel stages and typed input
bindings. Fortnite remains at **4/8 observed launch gates**, last seen at the
[Apple family 3 GPU requirement alert](controller-discovery-checkpoint-20261104.md).
No rendered game frame, menu, login or playable match is verified; the gate count
is not an engineering completion percentage.

`ir.module_metadata(data, stream, pools)` owns a bounded metadata graph with
strings, typed values, ordinary/distinct tuples and named roots. It normalizes
the two reference-numbering conventions, preserves nulls/forward references and
cycles, and retains known debug/legacy slots as opaque. Function-local metadata
is isolated. `md.air_entries(ir, pools)` resolves unique defined functions,
checks fixed input arity/indexes, and reflects semantic/name/type, location
ranges, pointer address spaces, size/alignment, buffer size, access and unused
flags. Strings borrow the owning metadata graph. Cleanup is explicit on success
and error; struct appends avoid implicit V string clones.

Conditional predicates, structure layouts, fragment linkage/interpolation,
tessellation/extra entry operands and unknown attribute tails remain raw. Unknown
attribute arities are not guessed. Output ABI and additional stages are not
lowered. Known debug node internals and declaration schemas are not fully
verified. See [API, ownership and limits](../../compat/ios/airbitcode/METADATA.md).

Optimized and ASan/UBSan unit runs pass seven groups, including 44 directed
malformed cases, 1,045 scalar operand mutations and exact node/edge/text resource
boundaries. Existing bitstream, type/signature and constant regression suites
also pass under sanitizers. Leak detection is disabled; these checks do not
measure leaks.

The maintained V inspector assembles portable LLVM fixture data and independently
disassembles it with LLVM 23.1.0. Normal and sanitized self-tests check three
stages, four typed inputs and known binding fields, including escaped/NUL bytes,
a conditional global and null/cyclic metadata. All eleven corrupted-evidence
controls are rejected, including a split distinct cycle with matching values.
This fixture is data-format input, not an iOS application.

The final sanitized native corpus independently runs `llvm-dis` for every copied
raw module. Classic-stage rooted graphs match across numbering differences:
tuple arity, reference identity/distinctness, string bytes, integer bits, symbols,
address spaces and nulls. Other named roots and unreferenced nodes are outside
this comparison; it does not qualify native Metal pipeline reflection or every
reflected argument's ABI. All three outer runs and 430 LLVM subprocess statuses
are zero.

| Copied native corpus | Modules | Indexed metadata nodes | Classic entries | Arguments |
| --- | ---: | ---: | ---: | ---: |
| Contacts | 1 | 64 | 1 | 3 |
| MetalFX | 90 | 11,173 | 90 | 869 |
| SceneKit | 339 | 32,538 | 337 | 1,630 |
| Total | 430 | 43,775 | 428 | 2,502 |

These are macOS framework AIR samples from the previous pinned extraction.
Fortnite's packed shaders remain untested. The final unit program also
cross-compiles/links as a static little-endian AArch64 Linux ELF and passes
header inspection; that binary has not been executed in a guest.

Complete evidence is retained outside Git at:

`/Users/alex/Library/Caches/vinix-ios/air-metadata-validation-20261105-r1/`

It contains committed source, copied native libraries/raw streams, independent
LLVM disassemblies/logs/statuses, generated fixtures, host/target binaries,
build logs, intermediate failures, tool identities and reproduction notes.
Final inspector artifacts/corpus trees use `final`; final unit artifacts are
`unit-normal` and `unit-asan-r4`. Compiler/SDK closures are not sealed.
The complete typed inventory passes rechecking. A fresh archive restoration under
`air-metadata-restoration-20261105-r1/` matches every recorded path, byte, size,
type and permission. Its optimized unit program and sanitized LLVM fixture with
all eleven corruption controls pass again. Archive and receipt hashes are
unchanged after restoration.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-metadata-validation-20261105-r1.inventory.json` | `b474bba850807ab3a66bc549b6865b1dada9170090209e9e0a61bff5b0415d38` |
| `air-metadata-validation-20261105-r1.tar.zst` | `4b16d6e1a741208e871c9b81b8a6f59ad6cd6376e59737ea80ee453d9eb1a071` |
| `source.tar`, revision `2d041b961` | `40a36410e0f16b94a7b45e8310128d30dba630fe95d32e409dca869302554caf` |
| `unit-aarch64` | `b18887c1707241b558bf605292b18155346e97d81b5d45d2b590e345d9a86253` |

No runtime Metal capability changed and no new Fortnite probe was run. The
default Metal device remains nil. Instruction-result IDs, expression/instruction
lowering, resource/pipeline objects, command execution and presentation remain
to be implemented. The earlier game capture and its historical auditor rejection
are unchanged. This checkpoint does not qualify shader execution or a new game
launch milestone.
