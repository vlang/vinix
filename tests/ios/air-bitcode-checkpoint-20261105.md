# AIR bitstream reader checkpoint — 2026-11-05

`31febe97c165b1f2182f09be2fd5846e3bc7a530` adds the V module
`compat/ios/airbitcode`, synthetic fixtures and `air-bitcode-inspect.v`.
It decodes the LLVM bitstream inside AIR modules indexed by the existing
[MTLB reader](metallib-reader-checkpoint-20261104.md). This is a prerequisite
for shader translation, without changing the game's runtime behavior.

Fortnite's latest observed boundary remains the
[unsupported Apple family 3 GPU alert](controller-discovery-checkpoint-20261104.md).
Progress is **4/8 observed launch gates**: load/bind, `+load`, initialization
and application entry. No game frame, menu, login or playable match is verified.
This fraction counts milestones; it is not an engineering completion percentage
or a reliable time estimate. Advertising remains skipped in the existing probe.

The reader handles fixed fields, 64-bit VBR values, literal/Char6/array/blob
abbreviations, local definitions and BLOCKINFO inheritance. It preserves unknown
block/record IDs and validates framing, block word extents, END_BLOCK placement,
widths, overflow and abbreviation scope. It also decodes METADATA_STRINGS length
tables into borrowed byte ranges. Three flat output arrays are owned by the
stream; blobs borrow immutable caller-owned input. Transient arenas and output
on failure are explicitly freed. Input, depth, output expansion and reference
work have independent limits; see the [module API](../../compat/ios/airbitcode/README.md).

Normal optimized and ASan/UBSan fixture runs pass five groups: scalar encodings,
zero-width values and empty/ordinary blobs; inherited abbreviations and nested
scope restoration; malformed grammar/framing/widths and integer overflow;
metadata tables and resource caps; 19 rejected prefixes and 160 single-bit
mutations with immutable input and bounded successful indexes. A signature-only
stream is structurally valid, without establishing any LLVM module semantics.
Sanitizer runs use `detect_leaks=0`; they are not leak measurements.

The final sanitized inspector verifies each MTLB's module hashes, extracts every
unique raw stream, invokes LLVM 23.1.0's independent bitcode analyzer and compares
all block IDs/scopes/code widths/word lengths, record codes, scalar operands,
ordinary blob bytes and decoded metadata strings. LLVM's text does not expose
the metadata length-table encoding or padding, which are not compared bytewise.
All 430 LLVM subprocess statuses and three corpus runs are zero.

| Copied macOS library | Modules | Records | Scalar operands |
| --- | ---: | ---: | ---: |
| Contacts | 1 | 233 | 1,825 |
| MetalFX | 90 | 124,786 | 588,852 |
| SceneKit | 339 | 127,629 | 871,265 |
| Total | 430 | 252,648 | 1,461,942 |

The inputs have the same hashes pinned in the MTLB checkpoint. They are native
macOS 27.2 framework samples, not Fortnite's packed shaders. Both normal and
sanitized oracle self-checks reject all 12 controls: changed block ID, size,
width, record code, operand, metadata count/string and blob bytes; wrong closing
block; missing/extra record; and truncated trace. The portable fixture program
cross-compiles and links to a static little-endian AArch64 Linux ELF and passes
header inspection; it has not been executed in a guest.

Validation is preserved at:

`/Users/alex/Library/Caches/vinix-ios/air-bitcode-validation-20261105-r1/`

The complete bundle contains committed source, copied inputs, raw modules,
independent LLVM traces/statuses, final and intermediate binaries/results,
build logs, AArch64 generated C/ELF, tool identities and reproduction notes.
Final inspector artifacts are named `inspect-*-final`, `*-corpus-final` and
`negative-*-final.log`; final units are `unit` and `unit-asan-r2`.
Compiler/SDK closures are not sealed by this validation.

The typed inventory passes rechecking. The complete bundle was archived and
restored into fresh `air-bitcode-restoration-20261105-r1/` under the same cache
root. The restored bundle matches every inventoried path, byte, size, type and
permission. Its normal unit binary and sanitized 12-control oracle check pass
again. The archive and inventory remain beside the original bundle.

| Artifact | SHA-256 |
| --- | --- |
| `air-bitcode-validation-20261105-r1.inventory.json` | `2bb0980cba628220e75c0ed3f289bc4e42ea3033e15432b2c36afdf43919220e` |
| `air-bitcode-validation-20261105-r1.tar.zst` | `2c8c8993e68f93f8cdc1a0ad297a6dac67c769513a574e68e188bfb062d3df26` |
| `source.tar`, revision `31febe97c` | `b395951c6f03f818687ce374d8b13c5b080a0de1e238d97cc17f0daefad35f15` |
| `unit-aarch64` | `dda9f02d42dfc6bb9e44724981e5510696ac32f55fedf90493f7d9cabd2d3bd7` |

No new Fortnite probe was run for this standalone parser. The runtime's default
Metal device still returns nil: LLVM IR types/references and AIR instructions,
shader translation, GPU resources/pipelines, command execution and presentation
remain to be implemented. The prior game capture and its historical auditor
rejection are unchanged. This evidence qualifies bitstream-format comparisons,
not shader execution or a new launch milestone.
