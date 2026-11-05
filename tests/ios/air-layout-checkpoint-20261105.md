# AIR ABI layout checkpoint — 2026-11-05

`383dc92092009ebc5f7e9349f1f2dbb43ea66d1b` adds fixed type sizes, ABI/preferred
alignment, array stride and structure field offsets after
[global pointer typing](air-global-types-checkpoint-20261105.md). This prepares
shader memory addressing. Fortnite remains at **4/8 observed launch gates**,
last seen at the [GPU requirements alert](controller-discovery-checkpoint-20261104.md).
No rendered game frame, menu, login or playable match is verified. The gate count
is not an engineering completion percentage.

The bounded data-layout parser handles pointer address spaces/index widths,
integer/FP/vector alignment, aggregate alignment and validated size-neutral
hints. Original and synthetic type tables expose bit/store/allocation sizes and
packed/ordinary field offsets. Unsized and unsupported types have explicit
statuses; no fallback size is supplied. Scalable vectors remain unsupported.
Arithmetic overflow and work limits fail explicitly. Ownership and limits are
documented in [LAYOUT.md](../../compat/ios/airbitcode/LAYOUT.md).

Optimized and ASan/UBSan unit runs pass four groups, including recursive pointer
structures, sub-byte/nonstandard integer widths, zero sizes, overrides and
pointer/index widths. Thirty invalid/unsupported profiles, array/padding/
multiplication overflow, depth rejection and 200 layout byte mutations pass.
Leak detection is disabled; leaks were not measured.

The V inspector uses LLVM TargetData to independently calculate all five size/
alignment fields, structure offsets and byte order. Four layout profiles verify
96 fixed type layouts and 24 field offsets in both builds. All eight corruption
controls fail: changed bit/store/allocation size, ABI/preferred alignment, field
offset, field count and endianness. The oracle reconstructs LLVM types from the
already indexed graph; it qualifies layout arithmetic, not the type decoder
independently. Pointer index widths and excluded-status classification are not
independently checked through the C API. LLVM itself is not sanitizer-built.

All 430 copied native modules pass the final sanitized comparison:

| Native corpus | Modules | Fixed layouts | Field offsets | Unsized/unsupported excluded |
| --- | ---: | ---: | ---: | ---: |
| Contacts | 1 | 19 | 2 | 12 |
| MetalFX | 90 | 4,109 | 1,160 | 1,584 |
| SceneKit | 339 | 10,024 | 3,889 | 3,662 |
| Total | 430 | 14,152 | 5,051 | 5,258 |

All three corpus statuses are zero. The checker invokes LLVM's C API directly,
without disassembler subprocesses. These are macOS framework samples; Fortnite's
packed shaders remain untested. The unit program cross-compiles and links as a
static little-endian AArch64 Linux ELF and passes header inspection. It has not
run in a guest. No shader or iOS application was executed by these checks.

Complete evidence is retained outside Git at:

`/Users/alex/Library/Caches/vinix-ios/air-layout-validation-20261105-r1/`

It includes committed source, original libraries/raw modules, LLVM comparison
receipts, fixtures, binaries, build/run logs, tool identities and reproduction
notes. Final corpora use `final`; final binaries are `unit-normal-final`,
`unit-asan`, `inspect-normal-final` and `inspect-asan`. Preliminary compiler
errors/warnings and smaller passing fixtures remain preserved. Compiler, SDK,
LLVM dependency and sanitizer-runtime closures are not sealed. The installed
LLVM library is pinned in the bundle's `identities.sha256`.

The unchanged complete inventory checker passes. An initial extraction failed
with disk exhaustion; that partial tree remains at
`air-layout-restoration-20261105-r1/`. A full fresh restore under
`air-layout-restoration-20261105-r2/` matches every recorded path, byte, size,
type and permission. Its optimized unit and sanitized LLVM fixture pass again,
including all eight controls. Sibling restoration logs/notes preserve the
results. Archive and inventory hashes remain unchanged after replay.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-layout-validation-20261105-r1.inventory.json` | `340c5545531fa7ed0dbf31c73e326b9e18bf7da88d4aa67371cc2ce12f7329b4` |
| `air-layout-validation-20261105-r1.tar.zst` | `05b6c3793788abd31959ae88ea17806336d03f881f77e828f07c6179d54e75b0` |
| `source.tar`, revision `383dc9209` | `123b1bddaec743dd48dc5fb8545510d50fcea6ff4bf501dee63b9f0165a98960` |
| `unit-aarch64` | `b6416acea42958306251572ab7ad2bf0dfa3cb4ad612e8bea4bdd6b2a5f8c271` |

No runtime Metal capability changed and no new Fortnite probe was run. The
default Metal device remains nil. GEP byte offsets, global initialization,
expression/instruction/intrinsic lowering, resource/pipeline objects, command
execution and presentation remain unfinished. The previous game capture and
historical auditor rejection are unchanged. This checkpoint does not qualify
shader execution or another game launch milestone.
