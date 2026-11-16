# Software Metal SIMD identity checkpoint — 2026-11-16

Source revision: `12b80807c801b1f1c285040eb147262b329697cb`.

Compute kernels accept `air.thread_index_in_simdgroup`,
`air.simdgroup_index_in_threadgroup`, `air.simdgroups_per_threadgroup` and
`air.threads_per_simdgroup` as ushort/uint scalars. SIMD arguments declared
together must use matching integer widths. Each semantic is unique; vector,
other-width, spoofed-name and invalid metadata forms reject. The scalar/type
contract follows the [Metal Shading Language specification](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf),
section 5.2.3.6. The AIR spellings also appear in the
[AIR builder source](https://github.com/vertex-language/air/blob/main/kernel.go).
These checks use synthetic AIR; Apple compiler/native GPU validation was not run.

The CPU backend retains its execution width of one. Each invocation receives
lane zero, its flattened local index as subgroup index, the actual clipped
threadgroup volume as subgroup count, and SIMD width one. The pipeline query
and builtin calculation share one width constant. Duplicate masks and argument
tags widen to u16; previous semantics keep their bits and slots. Four scalar
words append to the existing 24-word binding array.

`tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR simd-builtins` builds a
fresh host and passes normal and deterministic hashing runs under ASan/UBSan:

- 716 dispatches and 638,392 checked invocations across both runs. Seven
  reusable pipelines combine all twelve geometry/SIMD arguments with scalar,
  pair, triple, ushort and uint forms. Eight more kernels use one SIMD argument
  without any old geometry arguments or optional type-name metadata.
- Independent group/local enumeration checks complete output records and
  padding. SIMD values feed bounded addresses. Both direct dispatch selectors,
  partial groups on all axes, oversized groups, 4,096-thread grids, buffer
  offsets and pipeline reuse pass.
- 424 rejected pipelines include malformed types/properties, duplicates,
  unknown semantics, existing geometry mismatches and twelve distinct SIMD
  width mismatches (all six pairs, both ushort/uint directions). Four short
  outputs fail preflight without any write. Every process drains two runtimes.

The same final executable passes geometry-types, builtins, indirect, indices
and sizes modes in fresh normal/deterministic processes. These retain their
previous counters, including 652 geometry-type dispatches with 594,712 checked
invocations, 40 indirect dispatches with 55,192 invocations and 12 deferred
failures, 108 computed-index dispatches with 88,576 checked invocations, and
448 shader images with 667,228 checked invocations and RGBA8 buffer/texture
readback. The builtin mode passes 12 dispatches and 76 invalid pipelines.

Initial runs preceded the matching-SIMD-width guard and remain as baseline
evidence. Specification review added the guard and twelve mismatch fixtures;
`software-qualified` and `qualified-*` logs qualify the final source and rerun
all listed regressions. No execution expectation was relaxed.

No resource owner or lifetime is added. Dispatch scratch grows by 32 bytes;
the same owned array is allocated once, borrowed by typed bindings, reused
for preflight/execution and freed on success/error. Generated C confirms a
fixed 28-word per-invocation result without allocation in that helper. Object
draining is checked; retained heap was not measured and leak detection was
disabled. SIMD collectives, barriers, rendering, native GPU execution, guest
launch and new Fortnite launch/frame evidence remain outside this checkpoint.

Evidence: `/Users/alex/Library/Caches/vinix-ios/simd-builtins-20261116-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/simd-builtins-20261116-r1.tar.gz`.

- Archive SHA-256: `bb3bed9c2603d084615f7b4e4ab5c8327eecf64d2645b07ba5b5155006cc5fd9`.
- Typed inventory SHA-256: `0e9735ce572dec87cac60cc43e504b2c73a20918297c2272c29d11f614188851`.
- Source archive SHA-256: `20d112560649cec498994d25c31c7b48f759c8710351c7ca082c00ba8c0e01ad`.

Complete inventory and archive comparison passes for all logical bytes,
paths, types, modes and links, including root mode. Originals remain retained;
no restoration replay or evidence deletion is authorized. Source pins match
the feature commit. Commands, compiler/executable identities, generated C,
IR/bitcode, comparisons and sanitizer logs remain. Captured toolchain libraries
are referenced externally, so this is not a hermetic bundle.
