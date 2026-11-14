# Software Metal floating-to-integer vectors — 2026-11-15

`40339422f751dd00e4762e287e27e9e9efad2f8b` adds unflagged `fptoui` and `fptosi` from half/float
to i1..i64 for fixed AIR vectors of 1..16 lanes. Lane count is unchanged.
Conversion truncates toward zero, independently of host rounding. NaN,
infinity and values whose truncated result is outside the destination range
produce lane-local poison. Negative fractions between -1 and zero convert
to unsigned zero; fractional values just below a signed minimum remain valid
when truncation brings them into range. Signed i1 has range -1..0.

Any undef source lane rejects the executed cast, including discarded results.
Source freezes repair indeterminate inputs but leave numeric invalidity
unchanged. Result freezes repair produced poison without suppressing earlier
undef errors. Unselected poison lanes may be discarded. Complete supported
literals and earlier constructions are validated, including inactive blocks.
Independent snapshots compose with integer operations and existing vector casts.
Dynamic failures preserve prior writes.

Each cast costs one step and source plus result lane work. The existing
1,000,000-lane budget, 4,096 static construction slots and execution-owned
array are reused; no ownership field or per-lane allocation is added. Mixed
scalar, void and memory APIs support these conversions. The integer-only API
rejects floating sources, even when the result and arguments are integers.
Nonzero flags, other formats, reshaping, vector arguments/returns, PHIs and
loads/stores remain unsupported.

ASan/UBSan qualification passes:

- All 8,388,608 half-encoding comparisons across every destination width and
  both signs match an independent exact f64 oracle: 6,678,532 defined values
  and 1,710,076 poison results. It scales the half significand exactly and
  only casts finite nonnegative magnitudes at most 65,504. Source masking,
  immutable snapshots, fractional and i64 boundaries also pass. Another
  417,792 lane-state checks cover every destination, format, sign and lane/count.
- 768 decoded shapes cover every destination width, both source formats,
  both signs and 1/3/16 lanes. There are 511,264 defined LLVM values,
  204,616 poison-store failures preserving prior writes, 512 explicit zero
  freeze choices and 1,432,784 scalar/integer API checks. The sweep includes
  655,360 exhaustive half samples at i1/i8/i16/i32/i64 and 40,552 further
  boundary/random samples. Every output and guard byte is checked with
  unaligned accesses, odd integer widths and derived bounds.
- 7,680 metadata/source mutations and 1,536 short budgets reject before writes.
  The comparator rejects 384 corrupted values, kinds, widths, step counts
  and poison tags. Another 546 focused controls cover numeric invalidity,
  strict undef, freezing, discards, poison isolation, snapshots, composition,
  loop slot reuse, decoded flags, unsupported profiles and host rounding.
  Eight memory/void boundaries admit exactly 4,096 constructions and
  1,000,000 lane-work units; exceeding either rejects before writes.
- Five unit and five LLVM reference regressions pass for shared cast dispatch,
  bitcasts, integer casts, precision changes, integer-to-floating conversions,
  scalar execution and vector floating arithmetic. Four maintained reference
  checkers use double/bfloat rejection fixtures where their previous ordinary
  float-to-integer vector casts are now supported. Historical bundles and
  their original checkers remain intact.
- Both Swift hash modes pass all 24 software Metal groups with two drained
  runtimes each. Each runtime exercises 288 new deferred dispatches across 48
  kernels: 145 complete and 143 fail as expected. The checks cover 256 saved
  native value/tag pairs, sparse bindings, writes after encoding, pipeline
  reuse, source/result freezes, numeric invalidity, snapshots, integer-cast
  round trips, comparison/select composition and full i64 results. Undef
  failures preserve only the marker; poison failures also preserve the first
  frozen-zero store. Unsupported double conversion rejects at pipeline creation.

The native projection contains only defined i64 saturation operations and
separate range/NaN predicates. Finite half inputs widen to float exactly. Range
predicates truncate as float before comparing with powers of two, preserving
the fractional boundary rules. No invalid ordinary native cast executes.
LLVM verifies the complete module and the native projection. Detailed comparison
rows, projected bitcode, target identity and assembler logs are retained.

The initial run passed its comparison batches, then LLVM rejected an invalid
FMF guard during assembly. Its source, binary, complete fixtures and logs remain.
LLVM does not admit that syntax on these casts; final flag controls mutate
decoded instructions directly, while parser-level guards use valid unsupported
formats. All final controls pass.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-vector-float-int-validation-20261115-r1.tar.gz`

The canonical expanded workspace at the same path without `.tar.gz` remains.
It includes complete results, failure evidence, binaries, generated host C and
objects, compiler captures, commands, helpers and `bundle/source.tar` pinned
to the feature revision. `tests/packages/wine-workspace-archive.v` seals it
using `tests/ios/swift-staging-archive.v check-archive-root`. The checker decodes
every logical payload and compares paths, types, sizes, bytes, modes, symlink
targets and root mode with the original. Complete original inventories and
tool/archive hashes match before and after compression. No restored replay
was performed; originals remain. Audit commands and receipts are beside the archive
under `.tar.gz.audit`; the typed inventory is `.tar.gz.inventory.txt`.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.gz` | `ddfeaa6d300cd7f4e2a6c59ae6cc916cdb8dcbe0686f4e648223633c1631662c` |
| `.tar.gz.inventory.txt` | `e847a5775c05272cea7ac88bd9ba492dbae64c8dc6c542e4583ae0ce51d87d36` |
| `bundle/source.tar`, revision `40339422f751dd00e4762e287e27e9e9efad2f8b` | `645f57a1b2788b9c1440ac6742ffb274a829d20baa9535ff2ed57b768d43c4ab` |

The standalone compiler was captured after builds; the host compiler was
captured before generation. V libraries, SDKs, assembler, symlink targets and
dylibs remain external prerequisites. Native JIT code is uninstrumented. Leak
detection is disabled and retained heap was not measured. The ordinary runner
was not rebuilt. These are synthetic CPU fixtures: no Apple shader, GPU
rendering/presentation, Vinix guest, Fortnite frame or launch gate is newly
verified. Archive integrity does not replace historical launch auditors.
