# Geometry builtin types checkpoint — 2026-11-16

Source revision: `75982841161c18039060659606601e4a6e180449`.

Software Metal geometry arguments accept ushort/uint scalars, pairs and triples.
The local index remains scalar. This profile requires exact width/shape matches
within grid-position/size and local-position/size families, matching local
position/index widths, and common lane counts across declared geometry vectors.
Type names must match the underlying integer type; floats, pointers, other
widths/counts and existing invalid metadata remain refused. Existing dispatch
limits keep every supplied value within ushort range.

New validation state consists of transient integers and static type-name strings.
The 24-word dispatch array, borrowed slices and ownership paths are unchanged.
Narrow fixture kernels zero-extend inputs before tiled address arithmetic and
u32 stores. Retained heap is unmeasured; leak detection is disabled.

ASan/UBSan checks pass on macOS ARM64 in both hashing modes, with two drained
runtimes per mode: 652 dispatches, 594,712 invocations, 260 pipeline rejections
and four prewrite bounds failures. The seven reusable pipelines cover all six
types plus scalar/uint3 mixes, all eight semantics, both selectors, partial and
oversized groups, maximum grids, offsets and untouched padding. Independent
group/local enumeration checks records; narrow values enter addresses through
explicit zero-extension. Fourteen distinct mismatch fixtures include integer
widths, unrelated vector lengths and local index widths, alongside 51 existing
invalid metadata/type/duplicate fixtures.

Fresh processes of the same executable pass builtin, direct/multidimensional
grid, computed-index, size/image-readback, group-coordinate, indirect dispatch,
vector-memory and prepared-reuse modes in both hashing modes. Unsupported narrow
and pair fixtures now use i8 and one-element vectors. Historical bundles retain
their original sources. The first runtime attempt caught accidental one-element
vector admission; the explicit vector lane 2..3 guard fixes it. Its failed log
remains retained. `software-types-final` qualifies the final code.

Evidence: `/Users/alex/Library/Caches/vinix-ios/geometry-types-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/geometry-types-20261116-r1.tar.gz`.
Complete inventory and archive byte/metadata comparison pass; originals remain
retained. No restoration replay is claimed.

- Archive SHA-256: `37e632ad12a7a3fe360e710740eba9df2152dc0cd2f7baea4b452c5790608a7e`.
- Inventory SHA-256: `b9a7cd7cafabb7784521a68e3ccfa9e897a14ea1b51ad1832d03a5f104f0d9b8`.
- Source archive SHA-256: `436ad4781bf47b179c047a29593bed3140351b7c919697cb696958187e5a05a3`.

The bundle preserves IR/bitcode, comparisons, generated C, binaries, commands,
logs, tool identities, source hashes compared with the feature commit and an
ownership review. Reproduce with `tests/ios/metal-software-checks.v
FRESH_EXTERNAL_DIR geometry-types` and the retained captured toolchain using
repository module paths. Dependencies remain referenced, so this is not hermetic.
No broad runtime suite, native GPU, guest launch or new Fortnite frame is verified.

The six geometry type forms are described in the [Metal Shading Language specification](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf).
