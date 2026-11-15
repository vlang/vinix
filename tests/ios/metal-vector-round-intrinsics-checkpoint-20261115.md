# Software Metal vector rounding — 2026-11-15

`843628814d17f31b050d1701a3293aea7da06293` adds direct unflagged `llvm.floor`, `ceil`, `trunc`, `round`,
`roundeven`, `rint` and `nearbyint` calls for fixed 1..16-lane half/float AIR
vectors (`vNf16` and `vNf32`). Each lane uses the existing integer-based scalar
evaluator. Round breaks ties away from zero; roundeven, rint and nearbyint use
nearest, ties to even. The latter two follow the backend's default rounding
profile independently of the host environment; strict FP and FP exceptions
are outside this profile. Arithmetic NaNs use the preferred positive quiet NaN.
Signed zero and infinities retain their defined rounding behavior.

Poison stays local to each lane. Any undef source lane rejects at the executed
call, including discarded results. Source freezes repair indeterminate lanes;
result freezes do not suppress an earlier undef error. Dynamic failures preserve
earlier writes. Results use independent snapshots and compose with existing
bitcasts, fneg, comparisons, selects, shuffles and extraction.

Shared call validation checks canonical overload names, exact signatures,
direct declaration identity, arity, calling convention, call flags and source
construction order. Declaration attributes use the existing bounded scanner.
The separate vector declaration cache now has 288 entries: the previous 64
sign identities retain their keys, followed by 224 rounding identities.
Scalar cache identities are unchanged. Duplicate reserved declarations reject.
Each rounding call charges two lane counts to shared work, one execution step
and one of the existing 4,096 vector result slots. Shared work remains bounded
at 1,000,000 lanes.

Mixed scalar, void and memory APIs admit the calls. The integer-only API rejects
floating lanes even for constant vectors with integer results. Vector arguments,
returns, PHIs and loads/stores, scalable or wider vectors, double/bfloat,
fast-math flags, tail calls, call-site attributes and unsupported declaration
attributes remain outside the admitted profile.

ASan/UBSan validation passes:

- 7,340,032 independent rational checks cover every binary16 encoding across
  seven operations and all 16 lanes, with source masking and snapshot checks.
  Another 22,848 checks cover lane poison, strict undef and freeze. All 288
  sign/rounding overloads have unique cache keys; malformed names, unsupported
  families, shapes and lane tags reject.
- 5,600 decoded shapes cover both formats, all seven operations, every lane
  count, five source forms and five constructions. All 932,806 native LLVM
  comparisons pass, including 917,504 exhaustive half/deterministic float sweep
  samples. Finite values and signed zeros compare bitwise; arithmetic NaNs
  compare by class while the VM must produce its preferred quiet NaN. An
  independent host-double oracle also checks VM values. Indeterminate freezes
  are checked separately from native execution.
- There are 8,792 explicit frozen choices, 21,280 poison-store failures,
  13,174 strict undef failures, 1,952,104 scalar/integer API checks, 112,000
  malformed-call/source mutations and 11,200 short-budget refusals. All output
  and guard bytes are checked with unaligned bindings and derived bounds.
  Another 700 controls cover discards, localized poison, freezes, snapshots,
  composition, repeated loops, declaration mutations, duplicate identities
  and 42 host-rounding-mode checks. Sixteen retained declaration-attribute
  mutations reject before writes. Eight memory/void boundaries check the exact
  shared storage and lane-work limits, including refusal before earlier stores.
- Eight unit and eight reference regressions pass for sign intrinsics, scalar
  floating/integer execution, memory operands/attributes, overflow pairs,
  memmove, saturation, vector bitcasts/fneg and float-to-integer conversions.
  Existing checkers were unchanged.
- Both Swift hash modes pass all 24 software Metal groups with two drained
  runtimes each. Every runtime exercises 420 new dispatches across 98 kernels:
  392 complete and 28 fail as expected. Cases cover tie boundaries and their
  neighbors, subnormals, zeros, infinities, NaNs, deferred input writes, sparse
  bindings, pipeline reuse, poison/undef, source/result freezes, old snapshots
  and fneg/rounding/raw-bitcast/comparison/select composition. Strict undef
  failures preserve the marker; poison failures also preserve a frozen-zero
  store. A fast-math rounding call rejects at pipeline creation.

LLVM verifies native input modules; projected comparison kernels retain their
intrinsic declarations and use the host target. Reference modules are split by
operation to stay within the existing parser record limit. The original
oversized fixture, failing binary and logs remain; its exact initial checker
source was not captured. A later failed control expected an earlier store to
disappear after undef; that binary, exact source, fixtures and logs remain.
The final control checks the preserved store. Helper diagnostics and a runtime
fixture containing generator notices remain too; review removed those notices
before host compilation. No production behavior changed to accommodate these
test errors.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-vector-round-intrinsics-validation-20261115-r1.tar.gz`

The canonical expanded workspace at the same path without `.tar.gz` remains.
It retains results, fixtures, failure evidence, binaries, generated host C and
objects, compiler captures, commands, helpers and feature-pinned
`bundle/source.tar`. The maintained V archive tools compare every logical
payload, path, type, size, byte, mode, link target and root mode with the
original. Complete before/after inventories and archive/tool hashes agree.
No restored replay was performed. Audit receipts are beside the archive under
`.tar.gz.audit`; the typed inventory is `.tar.gz.inventory.txt`.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.gz` | `a9f37b7e09ba3dd0a937c57451dcbc1b94e8ec50b2b7f508a6e6ce919e2e563f` |
| `.tar.gz.inventory.txt` | `b516011e0fe9ea04549ca50b2ab57d33a51afe3612dbbf536179896a46497130` |
| `bundle/source.tar`, revision `843628814d17f31b050d1701a3293aea7da06293` | `86f9b2c6aa5fae8ac61f480e0ed0516d5399b27460162dcdc59caea6cbeb2cd4` |

The standalone compiler was captured after builds; the host compiler before
generation. V libraries, SDKs, assembler, symlink targets and dylibs remain
external prerequisites. Native JIT code is uninstrumented. Leak detection is
disabled and retained heap was not measured. The ordinary runner was not
rebuilt. These are synthetic CPU fixtures: no Apple shader, GPU rendering or
presentation, Vinix guest, Fortnite frame or launch gate is newly verified.
Archive integrity does not replace historical launch auditors.
