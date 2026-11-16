# Software Metal requested SIMD-group count checkpoint — 2026-11-16

Source revision: `b71c6933db10458dff50af725e69313383986026`.

Compute kernels accept `air.dispatch_simdgroups_per_threadgroup` as a ushort
or uint scalar. It supplies the SIMD-group count for the requested threadgroup
size. With this CPU backend's execution width of one, it is the requested
width * height * depth. It stays unchanged in clipped edge groups, while
`air.simdgroups_per_threadgroup` reflects their actual size. This follows the
[Metal Shading Language specification](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf),
section 5.2.3.6. Tests use synthetic AIR with the air-prefixed metadata spelling;
Apple AIR emission/native GPU behavior is not qualified. `xcrun --find metal`
reports that the compiler is unavailable; that receipt remains retained.

The new kind uses u16 bit 4096 and scalar slot 28. Existing tags and slots
remain unchanged. It shares exact type-name, scalar width, duplicate, metadata
and matching-SIMD-width validation. Requested dimensions come from each recorded
dispatch snapshot, including indirect dispatches. Existing planner bounds make
the product safe and keep the count within ushort range.

`tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR simd-dispatch` builds a
fresh host and passes normal and deterministic hashing processes under
ASan/UBSan. Across both runs:

- 1,012 dispatches and 886,400 checked invocations cover all thirteen
  geometry/SIMD arguments, ushort/uint scalar forms and existing pair/triple
  geometry forms. Independent group/local enumeration checks complete records,
  shifted outputs and untouched padding. Both direct selectors, partial groups
  on all axes, oversized groups and 4,096-thread grids pass.
- 280 indirect dispatches receive counts written after encoding, then copied
  by an earlier blit. Caller count-buffer references are released before
  commit. The same seven prepared pipelines handle all dispatch methods.
- Ten additional kernels use individual SIMD arguments without old geometry
  arguments or optional type names; the new kind is checked alone in both
  widths. Requested counts also participate in bounded address calculations.
- 536 pipeline refusals include malformed scalar/vector types, names,
  properties, duplicates, existing geometry mismatches and twenty distinct
  SIMD width mismatches across all ten pairs and both width directions.
  Four short outputs refuse before writes. Each process drains two runtimes.

Fresh processes of the same executable also pass prior simd-builtins, indirect
and sizes modes in both hashing configurations. Their counters remain 716
SIMD dispatches with 638,392 checked invocations, 40 indirect dispatches with
55,192 invocations plus 12 deferred failures and 24 encoding refusals, and
448 shader images with 667,228 checked invocations and RGBA8 buffer/texture
readback. No broader AIR matrices or kernel/guest builds were repeated.

Scratch grows by one u64 from 28 to 29 words. No owner or resource lifetime
is added: the same execution-owned array backs borrowed value bindings, is
reused across validation/execution and is freed on success/error. Generated C
confirms a fixed 29-word helper result without allocation in that helper.
Object draining is checked; retained heap was not measured and leak detection
was disabled. This extends CPU software Metal. SIMD collectives, barriers,
rendering, native GPU execution and new Fortnite launch/frame evidence remain
outside this checkpoint.

Evidence: `/Users/alex/Library/Caches/vinix-ios/simd-dispatch-20261116-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/simd-dispatch-20261116-r1.tar.gz`.

- Archive SHA-256: `de3ebece3e39fad54428f59c7e639cc094ccf01a0fbb579f77b06dc4cf8b1204`.
- Typed inventory SHA-256: `c1a803f413c0133f5e55de35e8cd38579795395667625eaa38232d609696a97b`.
- Source archive SHA-256: `91aa7929a29f71e85bd029346d5c6d54f902b6b195dd3299d670442c28537d7e`.

Complete inventory and archive comparison passes for every logical file
byte, path, type, mode and link, including root mode. Originals remain retained;
no restoration replay or evidence deletion is authorized. Source pins match
the feature commit. Generated C, IR/bitcode, readback comparisons, commands,
tool/executable identities and sanitizer logs remain. Captured toolchain
libraries are referenced externally, so the bundle is not hermetic.
