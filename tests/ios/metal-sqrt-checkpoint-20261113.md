# Software Metal square root — 2026-11-13

`12b2c1eba` admits direct LLVM `sqrt` in bounded AIR buffer kernels and opt-in
software Metal compute. Matching half/float operands and results reuse scalar
validation and integer root/remainder evaluation, rounded to nearest with ties
to even independently of host rounding mode. Signed zero retains its sign;
positive infinity remains unchanged. Negative nonzero inputs and NaNs produce
the preferred quiet NaN. Poison propagates and undef rejects. Each call costs
one step. The buffer profile now admits 28 intrinsic families; general calls,
indirect/tail calls, call-site attributes and fast-math calls remain rejected.

`tests/ios/air-memory-rounding.v LLVM_AS FRESH_DIR sqrt` checks the new profile.
Its default mode retains the previous rounding operations and count guards.
Normal and ASan/UBSan sqrt runs each pass 327,744 native comparisons and another
327,744 native `sqrt(fabs(x))` compositions. Coverage includes every half
encoding, 65,536 float patterns, 64 signed class/limit edges and 196,608 float
neighbors of squared root midpoints. The midpoint generator uses integer
products/shifts independently of the production root algorithm, spanning the
normal exponent range.

The 66,720 primitive arithmetic NaN cases compare by class while requiring the
interpreter's preferred quiet representation. Other primitive results compare
261,024 exact raw words, including zero signs. Compositions use the same NaN
policy and additionally require nonnegative interpreter outputs. MCJIT uses
the detected host target (`apple-m5`), optimization level 2 and FastISel off.
The checker verifies four/five-step execution, offsets, sentinels, insufficient
primitive budgets, 32 host-rounding controls with incoming mode restoration,
four poison/undef guards, four freeze/lazy choices and nine metadata rejections
after a store. Guard functions never execute natively.

Sanitized regressions pass all 655,680 rounding comparisons and their existing
controls, all four scalar-intrinsic unit groups and all 16 integer/mixed groups.
The scalar sqrt group includes 32 exact cases and 327,680 independent integer
root/remainder inequalities. JIT-generated reference code is not sanitizer-
instrumented; the interpreter and checkers are.

All 24 software Metal groups pass with normal and deterministic Swift hashing.
Four deferred dispatches execute sqrt and sqrt-of-absolute-value on 2, -4,
negative zero and the minimum positive subnormal in both precisions. They
check sixteen exact output words, preferred domain NaNs, zero signs and
subnormal rounding. Inputs change after encoding, sentinels persist until
commit, and pipeline/caller output handles are released before commit. Four
input/output offset snapshots and two-runtime resource drainage pass.

Canonical retained evidence:

`/Users/alex/Library/Caches/vinix-ios/air-memory-sqrt-validation-20261113-r1/`

The maintained harness generated/compiled the current V program and TLS archive
successfully, but linking to the shared disk failed with ENOSPC twice. Those
failure receipts remain. A temporary 128 MiB RAM disk held the executable;
linking used the harness's same objects, archive, flags and libraries, with
only the output path changed. The harness's documented preamble/sigaction
corrections remain. No generated program functions were edited. Compute
fixtures were generated on RAM; temporary library-file checks used the
harness's APFS temporary directory.

The actual tested app and both hashing modes' compute fixtures are preserved
inside `software/ram-payload.tar.zst`. The ordinary
`software/NotificationChecks.app` directory is failed linker staging, not the
tested executable. The payload was extracted to a fresh RAM directory. Recursive
file comparison passed, both executable hashes matched, and the restored host
passed all 24 groups with normal hashing. Replay fixtures and logs were saved.
The maintained inventory tool recorded the original RAM tree; after moving
the restored tree to that same source path, its unchanged checker passed all
file bytes, sizes, types, permissions and link targets, including the root.
Both archive checksums passed before the RAM disk was detached. The archived
host executable's SHA-256 is
`a357886efb3f32517ebec333ff132e9c7b746073a7134f0b9ea7ba0669dc66dc`.

The complete canonical bundle remains in place with its own recorded/rechecked
inventory and selected source/header/executable/result identities. A source
snapshot is retained as `source.tar.zst`. No complete compressed canonical
bundle or whole-bundle fresh restore was produced because of disk space. No
completed disk evidence or other sessions' files were removed. Inventory
receipts do not authorize deletion or replace historical launch auditors.

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
| `.inventory.json` beside canonical bundle | `ef6d9478c322f2f95ebab27b143accd0a1e54d7cc311559a29ff774f8d98c54a` |
| `ram-inventory.json` in bundle | `b046b73b07f64e8f2a760b58690fe85b729f5e7a7b6f7193ad5a0016beb43efc` |
| `identities.sha256` in bundle | `4ad1c2bd7c23f85e2b4834d8da0497ee523daceb658eededd61fea0bd7e2a552` |
| `software/ram-payload.tar.zst` | `eee4371aab3b5bbb105f924b43c0cb162325278ebd4e9199e3424f96333ac73b` |
| `source.tar.zst`, revision `12b2c1eba` | `0590cfa9bb643d8c597cf2f97ab149d866b2dcc29066c1001dfd7324cdf6603e` |
