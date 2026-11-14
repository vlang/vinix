# Software Metal vector floating arithmetic — 2026-11-14

`af67acdc5920bb31bec95e1e50dce3c617a130ed` adds unflagged `fadd`, `fsub`, `fmul`, `fdiv` and `frem`
for fixed 1..16-lane half/float AIR vectors. Each lane uses the existing
integer-based scalar math at its own precision: nearest/ties-to-even rounding,
gradual underflow, signed zeros and infinities. Arithmetic NaNs choose the
preferred positive quiet NaN (`0x7e00`/`0x7fc00000`), permitted by
[LLVM NaN semantics](https://llvm.org/docs/LangRef.html#behavior-of-floating-point-nan-values).
FP zero divisors and invalid arithmetic yield IEEE infinity/NaN without poison
or host traps. `frem` uses truncating-quotient `fmod` semantics.

Both complete sources must be supported literals or earlier constructions.
Preflight includes unselected lanes and inactive blocks. Poison remains local
to each lane, including division/remainder. Any undef operand lane rejects at
the binary instruction, including discarded results or extraction of another
lane. Freezing sources repairs indeterminate lanes; freezing a result does not
suppress earlier errors. Dynamic failures preserve prior writes.

Results retain independent snapshots and feed all supported vector operations.
One executed binary instruction costs one step. Both source counts plus result
count charge the shared 1,000,000-lane validation budget. The existing 4,096
static construction slots and execution-owned array are reused and freed on
all exits. No ownership field or per-lane allocation is added. Fast-math flags,
other lane formats, scalable vectors, vector PHIs, arguments/returns and vector
loads/stores remain unsupported. Mixed scalar, void and memory execution share
validation/evaluation; the integer API rejects floating vectors.

ASan/UBSan qualification passes:

- 36,202 independent exact integer arithmetic lane checks cover both formats,
  every count and all five operations, retaining source snapshots. Another
  32,640 lane-state controls cover both operands, counts, lanes and operations,
  poison isolation, strict undef, IEEE invalid arithmetic and shape/tag guards.
- 1,500 serialized shapes cover six counts, five constant forms and literal,
  computed, frozen, inserted and shuffled results: 2,100 native LLVM comparisons,
  2,200 fixed-zero choices, 4,390 poison-store failures and 2,810 strict undef
  rejections. Scalar/integer APIs pass 23,000 checks, metadata/source mutations
  19,500, and short budgets 3,000 rejection checks before writes.
- A separate 16-lane sweep passes 657,920 LLVM comparisons, including 24,012
  preferred-NaN choices. It covers all 65,536 half left encodings with a
  permutation of right encodings, deterministic float pairs and complete
  16-by-16 edge grids. Unaligned scalar accesses, derived bounds and every
  result/padding byte are checked. Total native comparisons: 660,020.
- 336 focused controls cover left/right poison/undef, source/result freezing,
  discarded results, old snapshots, arithmetic/negation/comparison/select/shuffle
  composition, loop slot reuse, IEEE zero/infinity/NaN, every fast-math flag,
  inactive blocks and unsupported profiles.
- Eight public memory/void boundary checks admit exactly 4,096 constructions
  and 1,000,000 lane-work units; 4,097 or 1,000,016 reject before writes.
- Existing negation, integer binary, comparison, per-lane/whole-vector select,
  freeze, shuffle and extraction references pass, together with integer
  execution, scalar promise, comparison and integer vector binary units.
  Current integer-vector and host floating rejection fixtures now use `nnan`;
  unflagged arithmetic has become supported. Historical bundles are unchanged.

LLVM verifies complete modules before native projection. Only defined selections
execute natively; indeterminate selections use explicit interpreter expectations.
Non-NaN arithmetic and copied bits compare exactly. Arithmetic NaN comparisons
require the interpreter's preferred encoding while permitting native payload/sign
choices. Byte GEPs and align-1 accesses match VM layout; MCJIT uses the host layout.

All 24 software Metal groups pass in both Swift hash modes, with two drained
runtimes each. Per runtime, 230 new deferred dispatch samples exercise both
formats and every operation: signed zeros, infinities, overflow, subnormals,
signaling/quiet NaNs, input changes after encoding, poison/undef, source/result
freezing, old snapshots and chained arithmetic/negation/comparison/select/shuffle.
210 complete and 20 fail as expected. Ten failures preserve only the prior
marker; ten also preserve a frozen-zero store before a poison store fails.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-vector-float-binary-validation-20261114-r1.tar.zst`

The bundle retains fixtures/results, binaries, generated host C, objects,
build receipts, compiler snapshots, LLVM headers, selected identities and a
`source.tar` pinned to the feature revision. Initial unit/helper compilation
errors, two host failures and an interrupted diagnostic run remain. macOS crash
reports identify an ASan allocation in the libnotify child-atfork hook, before
the rejection case runs. The ten blit rejection checks now use `posix_spawn`
to execute fresh test processes. They require exit 1, the expected Metal error,
and no sanitizer diagnostic; all forty child logs are retained. No rejection
case is skipped or allowed to pass on a crash. Decode with
`zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

A fresh extraction replaced the bundle path. The maintained
`tests/packages/wine-workspace-archive.v` checker matches complete bytes, sizes,
types, modes and link targets, including the root; all 952 selected identities
match. All sixteen restored runs exit 0: nine references, five unit binaries
and both 24-group host modes, using separate output roots. Complete inventory,
selected identities and archive checksum match after replay. A fresh replay
archive extraction also matches its complete inventory. Original expanded
trees remain.

The standalone compiler was captured after builds; the harness captured its
separate toolchain before generation. SDKs, assembler, library symlinks and
dylibs remain external prerequisites. Native JIT code is uninstrumented. Leak
detection is disabled and retained heap was not measured. The ordinary runner
was not rebuilt. These are synthetic CPU fixtures: no Apple shader, GPU
rendering, presentation, Vinix guest, Fortnite frame or launch gate is newly
verified. Integrity checks do not replace historical launch auditors.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` | `fdb11ca062e5c6328d145a6a3569cbfd9885f5ec19c4407d15b584fd09bde25d` |
| `.inventory.json` | `60f61831065794eccf9362c8552a638d9dffde26683721b3ff9102e9644713e7` |
| `.replay.tar.zst` | `e5a27cf7aa1d1a59db0cf4d27fba281345712c51293884b37a3f9f382ad76a0e` |
| `.replay-inventory.json` | `656038ae95917d2c006cfab660dda8e76fd514424806aaaed52d3f9898dcdba5` |
| `source.tar`, revision `af67acdc5` | `6b9e1306db9c99d022b5c871c1494e76d9e80e5de593c2147dad7f476e6a2208` |
