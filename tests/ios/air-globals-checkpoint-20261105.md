# AIR global descriptor checkpoint — 2026-11-05

`c62725e0cf3290b80a5c21c74eb32fda565d27d0` links global declarations to their
storage types, names, flags and [initializer images](air-image-checkpoint-20261105.md).
Fortnite remains at **4/8 observed launch gates**, last seen at the
[GPU requirements alert](controller-discovery-checkpoint-20261104.md). No rendered
game frame, menu, login or playable match is verified. The gate count is not an
engineering completion percentage.

Descriptors preserve original declaration IDs, including function/alias/ifunc
holes, legacy/explicit storage types, address spaces, constant flag, initializer
IDs, raw linkage, explicit alignment, TLS and external initialization flags.
Names borrow immutable input bytes. Other properties remain explicitly opaque.
Matching module constant initializers can produce independent bytes/padding-mask
templates. External declarations, relocations and unavailable values do not
produce guessed storage. No global allocation, linking or TLS execution occurs.
See [GLOBALS.md](../../compat/ios/airbitcode/GLOBALS.md) for ownership and limits.

Optimized and ASan/UBSan unit runs pass four groups, including borrowed names,
exact declaration/initializer IDs, anonymous globals, direct relocations and
flags. All 20 directed corruptions and 112 record/name mutations pass. Existing
sanitized image and declaration-operand suites pass their original checks,
including 285 declaration/operand mutations. Leak detection is disabled; leaks
were not measured.

The inspector independently parses original raw modules with LLVM's bitcode
reader. It compares global order/count, names, recursive storage shapes, scalar
widths, address spaces, constant flag, initializer presence, explicit alignment,
TLS/external-init flags and normalized linkage. Original LLVM initializer values
are copied into a separate oracle module; TargetData checks sizes/masks and
instcombine folds byte loads. Original shader modules remain untouched, and no
original or generated function executes or accesses host/guest memory.

Little/big endian fixtures each verify ten globals, nine definitions, five
complete templates, five unavailable images, 21 selected value bytes and seven
padding queries, with zero unresolved loads. Both normal and sanitized runs
reject all 11 descriptor/image corruptions. All assembler statuses are zero.

All 430 copied native modules pass the final sanitized comparison:

| Native corpus | Modules | Globals/definitions | Complete templates | Unavailable | Value bytes compared | Padding queries |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Contacts | 1 | 0 | 0 | 0 | 0 | 0 |
| MetalFX | 90 | 740 | 204 | 536 | 1,527 | 0 |
| SceneKit | 339 | 1,353 | 653 | 700 | 3,146 | 122 |
| Total | 430 | 2,093 | 857 | 1,236 | 4,673 | 122 |

All three corpus statuses are zero, with zero unresolved loads. Images up to
16 bytes query every position; larger images query seven positions. Padding
classification/chosen zero is checked without comparing LLVM's unconstrained
bits. Native numeric initializer IDs, legacy pointees erased by LLVM, every byte
of large images, opaque properties, symbol resolution and TLS behavior remain
unqualified. Legacy linkage codes may normalize to the same LLVM kind. Exact
original IDs have separate unit checks. LLVM itself is not sanitizer-built.
These are macOS framework samples; Fortnite's packed shaders remain untested.

The unit program cross-compiles and links as a static little-endian AArch64
Linux ELF and passes header inspection. It has not run in a guest. No new
Fortnite probe or runtime Metal capability change occurred.

Complete evidence is retained outside Git at:

`/Users/alex/Library/Caches/vinix-ios/air-globals-validation-20261105-r1/`

The bundle contains committed source, original libraries/raw modules, folded
LLVM IR, counts, fixtures, binaries, logs, identities and reproduction notes.
Final binaries, fixtures and corpora use `final`. The initial private-array-push
compile error and preliminary shadow warning remain preserved with earlier
passing results. Compiler, SDK, LLVM dependency and sanitizer runtime closures
are not sealed. Installed tool/library identities pass recheck.

The unchanged complete inventory checker passes. A full fresh restore under
`air-globals-restoration-20261105-r1/` matches every recorded path, byte, size,
type and permission. Restored unit and sanitized LLVM fixtures pass again,
including all 11 controls. Sibling restore/replay logs preserve the results;
archive and inventory hashes remain unchanged.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-globals-validation-20261105-r1.inventory.json` | `547dc0e7b66b196b2fb01ec037dd5d607d806339ea1893c08d6006ed2bfcd911` |
| `air-globals-validation-20261105-r1.tar.zst` | `b3c293a403aa385e75e48033f917307e93a5e7732de0d40f2d7b89934e8998ef` |
| `source.tar`, revision `c62725e0c` | `25e9f512e0a14669172c3285cb6f436c1e70438feb2a495dfa1c02cb335274f8` |
| `unit-aarch64` | `3a8a78315b62020ff87ddf9c4af758511dc7b5ddbfa3a3767d0133ed01706b3d` |

The default Metal device remains nil. Initializer images remain templates even
for TLS or externally initialized definitions; they do not establish program
state. Global allocation/linking, expression/instruction/intrinsic lowering,
resource/pipeline objects, command execution and presentation remain unfinished.
The prior game capture and historical auditor rejection are unchanged. This
checkpoint does not qualify shader execution or another game launch milestone.
