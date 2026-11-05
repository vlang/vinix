# AIR constant image checkpoint — 2026-11-05

`6aba5afba1cad13b98e1d687e19b49d4de77c1fa` adds ABI-shaped constant bytes and
padding masks after [scalar GEP addressing](air-gep-checkpoint-20261105.md).
Fortnite remains at **4/8 observed launch gates**, last seen at the
[GPU requirements alert](controller-discovery-checkpoint-20261104.md). No rendered
game frame, menu, login or playable match is verified. The gate count is not an
engineering completion percentage.

The V materializer preserves supported integer/FP bits and byte order, array
allocation/vector store stride, ordinary/packed field offsets, splats, strings,
null and empty values. It owns two arrays: allocation-sized bytes and a mask
distinguishing value bytes from unconstrained ABI padding. Padding is chosen as
zero without claiming LLVM prescribes those bits. Unsupported shapes, expressions,
relocations, undef and poison return no partial image. Depth, expansion and byte
budgets fail explicitly. See [IMAGE.md](../../compat/ios/airbitcode/IMAGE.md).

Optimized and ASan/UBSan unit runs pass four groups: exact little/big endian
bytes and masks, i24/i128, NaN payloads, signed zero, bfloat/fp128, aggregate
padding/strides, null/string/empty values, eleven unavailable/malformed/budget
cases and a separate depth rejection. Existing sanitized constant-pool and ABI
layout suites pass their original corruption/mutation checks. Leak detection
is disabled; leaks were not measured.

The LLVM inspector assembles little/big endian fixtures. Each profile has 15
complete images and six unavailable roots. All 71 queried value bytes match,
33 queried padding positions have the expected mask/chosen zero, and no load
remains unresolved. All four byte/endian/size/mask corruption controls reject in
both optimized and sanitized runs. Assembler statuses are zero.

All 430 copied native modules pass the final sanitized comparison:

| Native corpus | Modules | Complete images | Unavailable roots | Value bytes compared | Padding queries |
| --- | ---: | ---: | ---: | ---: | ---: |
| Contacts | 1 | 16 | 2 | 80 | 0 |
| MetalFX | 90 | 6,837 | 1,758 | 34,359 | 756 |
| SceneKit | 339 | 12,351 | 2,832 | 71,705 | 2,274 |
| Total | 430 | 19,204 | 4,592 | 106,144 | 3,030 |

All 23,796 roots are accounted for. Unavailable outcomes, including propagated
dependencies, are undef 1,780, poison 1,523, expression 549, relocation 178 and
unsupported 562. All three corpus statuses are zero; unresolved load count is
zero. Complete images occupy 112,515 bytes per output array.

The oracle reconstructs matching LLVM types/constants from the decoded graph
and pool. TargetData independently checks allocation sizes and queried padding
classification; `instcombine` folds loads from constant globals to compare
value bytes. Images up to 16 bytes query every position; larger images query
seven positions. Therefore 3,341 allocation positions are unsampled. Padding
queries do not compare LLVM's freely chosen bits. This does not independently
qualify native literal decoding, all bytes of large images, expressions or
execution. LLVM itself is not sanitizer-built. No generated function executes
or accesses host/guest memory. These are macOS framework samples; Fortnite's
packed shaders remain untested.

The first newly written SceneKit comparison rejected a three-lane vector's
tail padding: chosen zero versus LLVM's 255 at offset 12. That failure, original
binary, partial corpus and LLVM diagnostic remain preserved. The final API
exposes a padding mask, and the checker verifies it through LLVM before comparing
values. No historical game auditor or complete inventory checker was changed.

The unit program cross-compiles and links as a static little-endian AArch64
Linux ELF and passes header inspection. It has not run in a guest. No new
Fortnite probe or runtime Metal capability change occurred.

Complete evidence is retained outside Git at:

`/Users/alex/Library/Caches/vinix-ios/air-image-validation-20261105-r1/`

It includes committed source, original libraries/raw modules, folded LLVM IR,
counts, fixtures, binaries, logs, diagnostics, identities and reproduction notes.
Final binaries, corpora and fixtures use `r2`. Compiler, SDK, LLVM dependency and
sanitizer runtime closures are not sealed. Installed tool/library identities pass
recheck. The unchanged complete inventory checker passes. A full fresh restore
under `air-image-restoration-20261105-r1/` matches every recorded path, byte,
size, type and permission. Restored unit and sanitized LLVM fixtures pass again,
including all four controls. Sibling logs preserve the restore/replay results;
archive and inventory hashes remain unchanged.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-image-validation-20261105-r1.inventory.json` | `390472d8d49bff0890788eb16ad75de65aab1585ad36628a955e6e77259cf9dd` |
| `air-image-validation-20261105-r1.tar.zst` | `209be997404677c805907a9c92e7d04f9d4be177aa2e44ce29b499fcbab44e6b` |
| `source.tar`, revision `6aba5afba` | `4ff71fb61a6c475272eba373b30b366fe52c42ce3cdcbbd6de063fb68ce3fb0d` |
| `unit-aarch64-r2` | `38b1b82183d6e42dad8847f1cd6dd61619429b6468c74af61f4b973b45550730` |

The default Metal device remains nil. Constant images are data for future
initialization/lowering; they do not install guest globals, resolve pointers or
execute load/store instructions. Expression/instruction/intrinsic lowering,
resource/pipeline objects, command execution and presentation remain unfinished.
The prior game capture and historical auditor rejection are unchanged. This
checkpoint does not qualify shader execution or another game launch milestone.
