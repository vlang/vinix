# Software Metal floating classification — 2026-11-13

`94f00b0ee` admits direct LLVM `is.fpclass` in bounded AIR buffer kernels and
opt-in software Metal compute. Half/float inputs and literal defined i32 masks
in 0..1023 produce scalar i1. Mask bits select ten classes: signaling/quiet
NaNs, negative infinity/normal/subnormal/zero, then positive zero/subnormal/
normal/infinity. Empty/full masks select none/all defined inputs. Poison still
propagates and undef rejects. Calls cost one step and share scalar validation
and raw-bit evaluation. The buffer profile now admits 31 intrinsic families.
Parameter two's exact immarg is admitted; every call's immediate is checked
even after its declaration is cached. General/indirect/tail calls, call-site
attributes and fast-math calls remain unsupported.

Normal and ASan/UBSan checks each pass 1,613,824 exact native comparisons
across 2,048 functions. All 1,024 masks in both precisions are tested against
twenty independently labeled representatives of the ten classes, totaling
40,960 boundary checks. Twelve masks per precision (empty/full and all ten
individual classes) additionally cover every half encoding or 65,536 float
patterns. The interpreter's i1 byte must have zero high padding; only the
native byte's defined low bit is compared. Neighboring sentinels and exact
four-step execution pass; insufficient budgets reject without writes.

Twelve poison/undef guards include masks 0, 3 and 1023; eight freeze/lazy
selections consume/discard computed poison with empty/full masks. Eighteen
metadata mutations and 24 immediate controls target a second call after a
valid cached call and a store. They reject before writes, including SSA,
argument/declaration, mistyped, poison/undef/opaque/splat and out-of-range masks.
Both valid baselines execute five steps and store the expected true value.
Altered indexes/constants and guard functions never execute natively.

Thirty-two environment checks cover both precisions, four host rounding modes,
signaling NaNs, subnormals and negative zero. Interpreter and native checks
raise no floating exceptions; the incoming rounding mode is restored. MCJIT
uses the detected host target (`apple-m5`), optimization level 2 and FastISel
off. JIT-generated reference code is not sanitizer-instrumented; the
interpreter/checkers are.

Sanitized regressions pass both scalar-classification unit groups (40,960
independent value/mask checks and immarg attribute/work-limit guards), all 16
integer/mixed unit groups, and 657,664 floating-extrema primitive plus 657,664
mixed-chain native comparisons and their existing controls.

All 24 software Metal groups pass with normal and deterministic Swift hashing.
Ten deferred dispatches classify all ten classes in both precisions, checking
float NaN/finite predicates and half signaling-NaN/NaN predicates. i1 results
feed integer extension and selection, producing forty exact output words.
Inputs change after encoding, sentinels persist until commit, and pipeline/
caller input/output handles are released before commit. Ten offset snapshots
and two-runtime resource drainage pass.

Canonical complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-fpclass-validation-20261113-r1.tar.zst`

The maintained V harness built and ran on a temporary 512 MiB RAM disk with
its unchanged compiler-preamble corrections. The complete 189 MiB bundle
contains standalone tests/results, the full software harness tree, both
compiler snapshots, header, source.tar at the pinned feature commit and an
identity manifest. Git initially could not write its index during disk
pressure; the retry committed successfully when space became available.
Concurrent sessions' newer commits are outside the pinned source snapshot.

A level-19 archive with a 256 MiB window was saved on disk. Decode with
`zstd -dc --long=28 ARCHIVE | tar -xf - -C FRESH_DIRECTORY`. An attempted read
before compression finished caused a premature extraction failure, reported
by zstd in the tool output. The premature checksum receipt and empty tar log
remain as `.premature.sha256` and `.restore-premature.log`. Only that owned
failed partial extraction was removed.
After compression exited successfully, a fresh checksum and complete
extraction succeeded.

The fresh restored tree was moved to the original source path while the
original remained under another name. The unchanged maintained
`tests/packages/wine-workspace-archive.v` inventory checker verified every
file byte, size, type, permission and link target, including the root. Selected
identities match. All five restored suites pass again, including all 24
software Metal groups with normal hashing. The complete inventory matches
after replay and the saved archive checksum passes afterward.

Replay fixtures/logs are retained in the same-prefix `.replay.tar.zst`, whose
own complete inventory matches a fresh extraction. Separate inventory receipts
and build/restore/check logs remain beside both archives. The RAM disk was
detached only after verification. Initial standalone evidence remains in the
same-prefix directory. No earlier completed evidence or other sessions' files
were removed. These receipts do not replace historical launch auditors.

The standalone compiler snapshot was saved after checks; the harness captured
its compiler before generation. External library symlinks, SDKs, assembler
and dylibs remain unsealed prerequisites. Leak detection is disabled; object
drainage is checked, retained heap is not measured. The ordinary runner was
not rebuilt. Compute remains a bounded single-thread CPU interpreter requiring
valid LLVM IR. Synthetic fixtures do not establish Apple compiler-produced
kernel compatibility. No GPU rendering, presentation, Vinix guest, Fortnite
frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| Complete `.tar.zst` | `4371a3c16c0c80fd7c3270141b2d46b5321fb617d682191799fcac8e7588ed56` |
| `.inventory.json` | `12e99a3dcf79ad8ba5e32fde49b27461ff1fdc8e85aacea3f626c6553a5c22a9` |
| `.replay.tar.zst` | `9a1494410072562f1ceff5ec00404335e539ab7d72353a699507dd4711cfbf65` |
| `.replay-inventory.json` | `b52d3eddc56dc2078faab92c6da1d9d443ceab885540a668fec1d32015b77d31` |
| `source.tar`, revision `94f00b0ee` | `8facc4cf3279bc4430691a47fc30790a2114af7323bddaa7128dae2c4d29fbe6` |
