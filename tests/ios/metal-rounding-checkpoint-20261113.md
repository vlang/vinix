# Software Metal floating rounding — 2026-11-13

`88cef5dfa` admits direct LLVM `floor`, `ceil`, `trunc`, `round` and `roundeven`
in bounded AIR buffer kernels and opt-in software Metal compute. Matching
half/float operands and results use the existing scalar validator/evaluator.
The operations round toward negative infinity, positive infinity, zero,
nearest with ties away from zero, and nearest with ties to even, respectively.
Zero results retain input sign; infinities and integral finite values remain
unchanged. NaNs use the scalar evaluator's preferred quiet choice. Poison
propagates and undef rejects. Calls cost one step and do not consult host
rounding mode. The buffer profile admits 27 intrinsic families; rint, nearbyint,
other floating intrinsics, indirect/tail/general calls, call-site attributes
and fast-math calls remain unsupported.

Normal and ASan/UBSan checks each pass 655,680 native LLVM comparisons across
ten functions. Each operation covers all 65,536 half encodings and 65,536 float
patterns, plus 64 float boundaries: both signs of zero, subnormals, infinities,
NaNs, neighbors of half ties, and the transition to integral-only precision.
The 11,545 arithmetic NaN cases compare by class while independently requiring
the interpreter's preferred quiet representation. All 644,135 other results
compare exact bits, including zero signs. MCJIT uses the detected host target
(`apple-m5` here), optimization level 2 and FastISel disabled.

Another 1,600 cached-declaration chains check native results and idempotence.
There are 160 interpreter checks across four host rounding modes and both
signs of 1.5/2.5, with the incoming mode restored afterward. The checker verifies
exact four/five-step execution, byte offsets, sentinels and insufficient
primitive budgets without writes. Twenty poison/undef guards, twenty
freeze/lazy selections and nine call-metadata mutations after a store pass.
Guard functions never execute natively.

Sanitized regressions pass all four scalar-intrinsic unit groups, all 16
integer/mixed unit groups, and 394,272 exact float-sign native/bit-mask
comparisons plus their existing chains and controls. Native JIT-generated
code is not sanitizer-instrumented; the interpreter/checkers are.

All 24 software Metal groups pass with normal and deterministic Swift hashing.
Four deferred dispatches check both signs of 2.5 and 0.5 in both precisions,
including the different tie rules and negative-zero outputs. Inputs change
after encoding; output sentinels persist until commit. Pipeline and caller
output handles are released before commit, and four input/output offset
snapshots produce forty exact output words through bitcasts and checked GEPs.
Existing completion/failure and two-runtime resource-drainage checks pass.

Canonical retained evidence:

`/Users/alex/Library/Caches/vinix-ios/air-memory-rounding-validation-20261113-r1/`

Disk pressure blocked the initial sanitizer log files and first harness
compiler copy. Only that owned failed partial compiler copy was removed;
fresh `*-r3` standalone sanitizer runs pass. The second harness generated
the current V program successfully, then failed writing its TLS archive
receipt with ENOSPC. That original archive was incomplete (92 listed members).
It remains in the bundle. A separate `libios-tls-resume.a` was rebuilt from
all 112 successfully compiled objects; its listing has all objects plus the
symbol-table member. The captured patched C program was compiled/linked
with the maintained harness's clang flags, includes, libraries and ABI sources,
using the separate complete archive. `*-resume.log` compiler/linker receipts
and both host logs are retained. No generated program functions were edited.
The harness's documented preamble/sigaction corrections remain in effect.

The software tree was moved into the canonical bundle after both runs. Its
relocated host passes all 24 groups again with normal hashing. Compiler,
header, generated-source, native fixture, executable, archive and result
identities match the saved manifest. The source snapshot is a streamed
`source.tar.zst`, verified with zstd. The maintained
`tests/packages/wine-workspace-archive.v` inventory tool records and rechecks
all file bytes, sizes, types, permissions and link targets, including the
root. Its separate `.inventory.json` receipt is pinned below. No complete
compressed evidence bundle or fresh restore was produced because of disk
space. Original evidence remains; this inventory does not authorize deletion
or replace historical launch auditors. Other sessions' files were untouched.

The standalone compiler snapshot was saved after checks; the harness captured
its compiler before generation. External library symlinks, SDKs,
assembler and dylibs remain unsealed prerequisites. Leak detection is disabled;
runtime object drainage is checked, retained heap is not measured. The ordinary
runner was not rebuilt. Execution remains a bounded single-thread CPU
interpreter with valid LLVM IR as a precondition. Synthetic fixtures do not
establish Apple compiler-produced kernel compatibility. No GPU rendering,
presentation, Vinix guest, Fortnite frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| `.inventory.json` beside bundle | `2965aeee74a4cbece062298acec72144921d0ac0bf7655e6bccd1d9ac999377f` |
| `identities.sha256` in bundle | `7b428a857d4a48d7c5f9d9022c643f23dff3d98e814a945674eee73286ac56ef` |
| `source.tar.zst`, revision `88cef5dfa` | `b0bf28b6f29d7e4d8fd1073c873e3a0c8e78ad1339c86c94207474166d6b1c7a` |
