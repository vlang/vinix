# Software Metal floating minimum/maximum reduction checkpoint — 2026-11-16

Source revision: `267d1c2cf24aeb73621e4c91e8df444ffeccf3f8`.

The bounded AIR interpreter executes ordinary direct
`llvm.vector.reduce.fminimum.vNf16/f32` and `fmaximum` calls for fixed 1..16-lane
half/float vectors, producing a matching scalar. These operations propagate
NaNs and order negative zero below positive zero, following the
[LLVM reduction contract](https://llvm.org/docs/LangRef.html#int-vector-reduce-fminimum).
One-lane results preserve raw bits, including NaN payload/signaling bits;
larger reductions use the existing preferred quiet NaN choice. All source
lanes are observed: poison poisons the result and executed undef rejects,
including later undef after earlier poison. Source freeze repairs lanes;
result freeze repairs poison to zero without hiding an earlier undef error.

Mixed, void and memory APIs accept the calls. Integer-only execution and
floating address dependencies remain excluded. Scalar results consume no
vector construction slots; calls cost one execution step and N+1 validation
lane-work units. Floating and integer reductions share the direct-call shape
validator, with exact element/result type identity and existing declaration,
attribute and work guards. Other floating reduction families, fast-math flags,
scalable vectors and wider formats remain excluded.

`tests/ios/air-vector-float-reduction.v` passes with ASan/UBSan:

- 64 operation/format/count shapes and 10,240 directed cases: 8,704 exact/frozen
  values, 512 poison stores and 1,024 strict undef failures. Every lane count,
  both formats/operations, 32 edge/mixed patterns and five expression modes
  cover literals, insertion and source/result freezes.
- 272,384 native LLVM values match an independent ordered-encoding oracle:
  263,682 exact non-NaN bit comparisons and 8,702 NaN-class comparisons. Native
  code uses only defined replacement words; poison, undef and freeze choices
  are checked separately. NaN payload/sign/signaling differences are permitted
  in the native comparison; interpreter bytes still match its explicit choice.
- 262,144 sweep samples cover every binary16 encoding and 65,536 deterministic
  binary32 patterns for both operations using reused scalar arguments and
  prepared plans. All directed/sweep cases check scalar and ordinary/prepared
  memory execution, nonmutating validation, shifted bindings, every backing
  byte and marker ordering.
- 10,240 short budgets reject with a budget diagnostic before writes, and 64
  integer-only API exclusions reject floating reduction bodies.
- 82 controls check direct floating returns, vector arguments/loads, double
  fneg/shuffle composition, cold/discarded states, floating address exclusions,
  call metadata and malformed names/types. Memory/void limits check 4,096 versus
  4,097 construction results and 1,000,000 versus 1,000,001 lane-work units,
  including expected diagnostics and reduction results using no vector slots.

The sanitized unit suite passes 4,194,304 independent ordered-key values across
all half encodings, deterministic float patterns, both operations and every
count, including one-lane identity, upper-bit masks and source snapshots.
Another 1,148 checks cover all-lane poison/undef and mixed-state guards.
Existing rounding and integer reduction units pass, including all 34,560
cache identities. Sixty-four appended identities preserve every previous key;
each existing i64 declaration cache grows by 512 bytes of stack.

The full integer reduction reference regression passes 40,032 native/oracle
values, 32,526 exact/frozen values, 2,502 poison stores, 5,004 undef failures,
80,064 scalar/integer checks, 40,032 short budgets and 118 controls. Integer
address, vector carry-less multiply and scalar/vector bitcast address controls
pass 150, 650 and 67 checks respectively. Computed-index regression passes
26,029 native exact cases, 50,771 prewrite refusals and 4,096 vector-coordinate
cases; prepared memory passes 28,928 byte comparisons and 3,314 changing-input,
recovery, bounds/budget and copied-metadata controls. Other full matrices were
not repeated.

Fresh normal and deterministic software Metal processes each pass 106 geometry
dispatches, 120 shader images, 218,226 checked invocations, 106 rejected
pipelines and two prewrite bounds failures. The new image converts coordinates
to float, reduces minimum/maximum, converts the scalar results back to integers
and uses them in its red channel. Tests cover queued dispatch, RGBA8
buffer/texture readback, padded bytes, both dispatch selectors, clipped groups,
repeated commits and two drained runtimes per process.

Generated checker and host C retain fixed by-value source/result records and
the existing extrema helper, with no new arrays in the reduction or name
parser. The checker includes both profile declaration caches; the focused
host includes its used memory cache. Existing scalar SSA slots, construction
storage, profile ownership and cleanup are reused. No evaluator kind, node
field, escaping pointer, lifetime extension or free path is added. Existing
allocation/error paths remain. Heap retention was not measured, leak detection
was disabled and native JIT code was not sanitizer instrumented. Broader
runtime and kernel/guest builds were not repeated.

An initial checker build failed because its `nan` helper collided with the C
math function; the retained diagnostic precedes its rename to `is_nan_bits`.
One-off generators also needed string escaping and a narrower image marker;
these implementation corrections are recorded in `attempts.txt`. The corrected
controls probe passes 82 checks, and all qualified matrix, unit, regression and
image runs pass without runtime failures. Saved original artifacts remain.

This is CPU software Metal evidence. Native GPU execution, guest/Fortnite
launch gates, a Fortnite frame and complete Metal support remain unverified.

## Retained evidence

Canonical original workspace (retained in place):
`/Users/alex/Library/Caches/vinix-ios/vector-float-reduction-20261116-r1`.

Complete archive:
`/Users/alex/Library/Caches/vinix-ios/vector-float-reduction-20261116-r1.tar.gz`

- Archive SHA-256: `a0424463ccf2df7bb187cc94a30653c7d8905db6725dcd8b85a8476ec20152fb`.
- Complete typed inventory: sibling `.inventory.json`, SHA-256 `45caf2fc665d21b23a9de8db2c748b56c2c97412fcc485c7c91a845c9ef98e2b`.
- Source snapshot: workspace `source.tar`, SHA-256 `b2c25c40442fae523002b622819ab1c8841dcb51f461ea3ab2570f2e22a3a73c`.

The archive check decodes all logical payloads and compares the complete
workspace's paths, types, modes, symlink targets, sizes and hashes, including
root mode. Inventory comparison passes before compression and is rechecked by
the archive tool afterward. This records integrity with originals retained;
it does not claim a restoration replay or authorize deletion. Commands,
source revision, LLVM target/features, generated C, captured compiler,
executable identities and sanitizer logs are in the bundle. Sealing
commands/statuses are siblings outside the sealed workspace.
