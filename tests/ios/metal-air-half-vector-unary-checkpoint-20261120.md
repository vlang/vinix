# AIR half vector unary math checkpoint — 2026-11-20

Feature revision: `37c2e45298651ac53cd22658fccba68db2b868a6`.

Software Metal accepts `air.fabs.vNf16`, `air.floor.vNf16`, `air.ceil.vNf16`,
`air.trunc.vNf16`, `air.sqrt.vNf16`, `air.round.vNf16` and `air.rint.vNf16`
for fixed 1..16-lane half vectors. The existing binary16 lane evaluators
are reused. Keys 62228..62339 append 112 identities after every earlier key;
the vector cache has 62,340 entries and the scalar cache remains 2,204.

`tests/ios/air-native-vector-half-unary.v` passes under ASan/UBSan with LLVM
23.1.5 on arm64 Darwin: 112 AIR/LLVM shapes, 164,864 typed/loaded vector cases
(each run direct and prepared), 1,777,664 native lane comparisons against
JIT-compiled `llvm.OP.vNf16`, 82,432 scalar extractions, 1,008
state/discard/isolation cases, 448 ordered store/repair cases, 2,240
metadata/type refusals, 560 short budgets, 84 native loops with executed-budget
refusals, 896 host-rounding checks, 560 result controls and 49
overload/type/arity/address guards. The 16-lane shapes cover every binary16
encoding. Other lane counts use 32 edge values and patterned values. The
float32 vector unary checker (974,848 lane comparisons) and the half clamp
checker still pass.

Twenty-five unit groups pass, including the new name/key test, all 62,340 cache
identities and 1,048,576 half sqrt checks. A stale test asserted that
`air.sqrt.v2f16` is refused; it now uses `air.fast_sqrt.v2f16` and
`air.sqrt.v2f64`.

A fresh software Metal host passes normal and deterministic `sizes` runs:
592 images, 826,996 checked invocations, 212 rejected pipelines and four
prewrite bounds failures. All 394 earlier comparison rows per run are retained
unchanged. Eight new rows come from `image_air_half_vector_unary`. In that
image, the two lanes of each input get opposite signs. The inputs are a
subnormal, 1.25, 1.5 and a signaling NaN, with sqrt inputs 4, 9, 0 and NaN
and rounding ties 0.5..3.5. Every family is compared against explicit raw bits.
A poison lane stays local, and lane 0 still matches the full call. The frozen
poison lane reads zero. These comparisons gate the pixel value, and an
independent red-byte oracle checks it. The shader has 157 static instructions,
which fits within the one-million-step budget for 4,096 invocations. Generated
host C declares 62,340 vector and 2,204 scalar cache entries.

Toolchain note: another process deleted
`build/ios/fortnite/array-sequence-checks/toolchain` (346 check directories
symlink to it) before the image run. The `v` binary (V c6bb06f, SHA-256
`cd89a6f1…`) was restored from the half-clamp evidence. Its `vlib` and
`thirdparty` were never archived, so they were rebuilt from `~/code/v` with
`git archive 61e5ef1f39`. That is the latest V commit before the toolchain's
first use on 2026-10-13. Three headers preserved by the earlier run match
byte for byte, and `time_darwin.c.v` agrees with `proc_rusage.c.v`. The
rest of `vlib` is not proven identical to the original.

Not covered: retained heap was not measured. Native GPU execution, Apple
compiler emission and Fortnite launch/frame evidence are still unverified.
No kernel or guest build was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-vector-half-unary-20261117-r1`.

Archive: `/Users/alex/Library/Caches/vinix-ios/air-vector-half-unary-20261117-r1.tar.gz`.

- Archive SHA-256: `e21a55f1f493c15fe94bfd77fa9a546c977b4b29a316ffaa449320541ba515c6`.
- Source archive SHA-256: `3356ee1520cefeb8b5535d423807bab0593f76df3dbe57dde07456f6761b648e`.

The archive has the same 1,440 entries as the evidence directory. Toolchain
libraries are referenced externally, so the bundle is not hermetic.
