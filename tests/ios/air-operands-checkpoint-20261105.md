# Partial typed AIR operand checkpoint — 2026-11-05

`9675980c2045fa5da3fef09bc67ee3c368d0eb99` adds a partial typed operand decoder
after the [body/value-ID index](air-bodies-checkpoint-20261105.md). It decodes core
arithmetic and control-flow records while retaining explicit unsupported states.
Fortnite remains at **4/8 observed launch gates**, last seen at the
[Apple family 3 GPU requirements alert](controller-discovery-checkpoint-20261104.md).
No rendered game frame, menu, login or playable match is verified; the gate count
is not an engineering completion percentage.

`ir.typed_operands(stream, pools, bodies)` reads integer/FP binary operations,
casts, comparisons, selects, vector element operations, PHIs, direct branches,
returns, unreachable, floating negation and freeze. It retains exact opcode/
predicate numbers, raw flags, result types, normalized scoped value IDs and
block targets. Unsigned relative IDs and signed-VBR PHI deltas remain distinct.
Explicit definition types seed the index; a final pass verifies forward type
claims. Synthetic scalar/vector boolean types are interned when necessary.

Every instruction is `decoded`, `opaque` or `deferred`. Unknown producer types
cause deferral. Explicit call return signatures may provide types while call
operands remain opaque. A function is complete for this profile only when all
instructions decode; consumers must check that status. Completeness does not
qualify LLVM dominance/CFG semantics, every flag encoding, lowering or execution.
Five arrays have explicit cleanup; original type names remain borrowed from
the owning IR module. See [API, ownership and limits](../../compat/ios/airbitcode/OPERANDS.md).

Optimized and ASan/UBSan unit runs pass five groups, including borrowed-name
ownership, exact normalized IDs, forward PHIs, synthetic boolean vectors,
opaque/deferred dependencies, 20 targeted corruptions and 125 operand mutations.
The existing body sanitizer regression also passes. Leak detection is disabled;
these checks do not measure leaks.

The maintained V inspector assembles portable LLVM fixture data with LLVM 23.1.0.
Normal and sanitized runs check 25 decoded instructions, two opaque instructions,
two deferred instructions and three complete core function indexes. Coverage
includes scalar/vector/FP operations, casts, comparisons, select, freeze, flags
and signed forward PHI identity. All eight corrupted-dump/index controls are
rejected. The fixture functions were not executed as shaders or iOS applications.

The final sanitized corpus independently disassembles all 430 copied modules.
For decoded instructions, its comparison checks exact arithmetic/cast/predicate
mnemonics and selected operand/result type spellings. It normalizes identified
type-name quoting. All function instruction counts are checked, including opaque
and deferred entries. Native value IDs/values, branch/PHI edge identities, raw
flags and opaque families are outside this comparison. The comparator expects
LLVM's normal instruction indentation and ignores continuation lines.
All three outer runs and 430 LLVM subprocess statuses are zero.

| Copied native corpus | Modules | Decoded | Opaque | Deferred | Complete function indexes |
| --- | ---: | ---: | ---: | ---: | ---: |
| Contacts | 1 | 17 | 12 | 0 | 0 |
| MetalFX | 90 | 42,111 | 21,198 | 13,560 | 0 |
| SceneKit | 339 | 11,432 | 14,068 | 7,157 | 8 |
| Total | 430 | 53,560 | 35,278 | 20,717 | 8 |

The statuses account for all 109,555 previously indexed instructions. These are
macOS framework samples; Fortnite's packed shaders remain untested. The final
unit program cross-compiles/links as a static little-endian AArch64 Linux ELF
and passes header inspection. It has not run in a guest.

Complete evidence is retained outside Git at:

`/Users/alex/Library/Caches/vinix-ios/air-operands-validation-20261105-r1/`

It includes committed source, native libraries/raw streams, LLVM disassemblies
and statuses, generated fixtures, host/target binaries, build logs, intermediate
attempts, source/tool identities and reproduction notes. Final sanitizer artifacts
and corpora use `final`; `unit-normal`, `inspect-normal` and `llvm-fixture-normal`
are also final. Compiler/SDK closures are not sealed.
The complete typed inventory passes rechecking. A fresh archive restoration under
`air-operands-restoration-20261105-r1/` matches every recorded path, byte, size,
type and permission. Its optimized unit program and sanitized LLVM fixture with
all eight corruption controls pass again. Archive and receipt hashes remain
unchanged after restoration.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-operands-validation-20261105-r1.inventory.json` | `98e35d9edd4974c40ca9a3edf093db8c80c4c337bc79c1847b308fb5d92e3c0d` |
| `air-operands-validation-20261105-r1.tar.zst` | `5d25a4a1a53aa4cf32bf75807f02335b31b7af66f75bb9e08dcd6a5626d6b5ff` |
| `source.tar`, revision `9675980c2` | `65b86b25bcde510bc004f8ff16267b49029f8be55bd232a79e50e71adc4fa4c4` |
| `unit-aarch64` | `6b2d0e94e38f40fd94679c2155ac972814d0cc5c3fec81cc4187d2de0b1dc3d6` |

No runtime Metal capability changed and no new Fortnite probe was run. The
default Metal device remains nil. Memory/GEP/call/aggregate and other operand
families, expression/instruction lowering, resource/pipeline objects, command
execution and presentation remain to be implemented. The prior game capture
and its historical auditor rejection are unchanged. This checkpoint does not
qualify shader execution or another game launch milestone.
