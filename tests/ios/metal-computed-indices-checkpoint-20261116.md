# Computed shader indices checkpoint — 2026-11-16

Source revision: `123fd6181fbfac508760ec6fdf6b544e43bd141d`.

Single-index GEPs accept bounded pure integer expressions over scalar arguments,
defined literals, literal-lane extraction from direct integer vector arguments,
add/subtract/multiply and trunc/zext/sext. Widths are i1..i64, with existing
integer wrap/cast flag semantics. The fixed pointer base and existing bounds,
alignment, permission and 64 MiB offset restrictions remain. General memory/
control-dependent expressions, additional indexed pointer flow and multiple
dynamic GEP indices remain unsupported.

Preflight owns a private topological graph, limited to 256 shared nodes and 32
levels including cached subtrees. Only required index dependencies consume that
budget. The transient build cache is freed on every exit; graph nodes transfer
to the profile on success and are freed with it. Normal evaluation uses a fixed
256-word stack array, confirmed in generated C. Error reporting uses the
existing boxed-error path; retained heap is unmeasured.

All expressions evaluate from current immutable argument words before any AIR
write, including cold/unused GEPs. Poison or invalid final indices reject before
writes. Modular unflagged arithmetic and negative intermediate values retain
their ordinary meanings. Ordinary/prepared execution and validation alone share
the evaluator; unrelated arithmetic keeps its existing dynamic error behavior.
Caller words/buffers remain borrowed and aliased output cannot alter the resolved
addresses or execution's captured arguments.

AddressSanitizer and UndefinedBehaviorSanitizer checks pass on macOS ARM64:

- 76,800 scalar expression cases across every i1..i64 width, add/subtract/multiply
  and four wrap-flag forms: 26,029 native exact cases and 50,771 prewrite refusals,
  including 21,399 overflow cases identified by defined LLVM overflow intrinsics.
  Flagged native targets execute only accepted inputs. Both execution APIs and
  validation alone check the scalar matrix.
- Another 4,096 vector-coordinate cases check literal lane extraction and
  flattening, including noisy interpreter words and canonical native padding.
  Controls check nine unsupported/depth/node refusals, exact 32-level/256-node
  acceptance, cached-depth extension refusal, cold bounds, aliased snapshots and
  54 cast/poison cases.
- Both runtime hashing modes each complete 54 flattened 3D buffer dispatches
  covering 44,288 invocations: 108 and 88,576 total. Independent group/local
  enumeration checks exact values, partial groups, both selectors, deferred
  inputs, output offsets and padding across two drained runtimes per mode.
  Eight combined late bounds/index-poison failures preserve complete output.
- Fifteen existing interpreter programs pass, including value/indexed/prepared/
  vector/scalar memory, constant/backward/structured GEPs, memory intrinsics and
  focused layout/switch/vector controls. Existing 1D/multidimensional/builtin/
  vector/prepared-reuse runtime modes also pass in fresh processes of the same
  verified executable under both hashing modes.

`regression0-results` qualifies the final maintained checker; early helper/build
diagnostics remain retained. The initial reference run reused noisy vector words
as native input; final native input has canonical narrow padding while noisy
interpreter bindings remain tested separately. `software-indices-final`
qualifies the final runtime, including the result-slot range guard.

Evidence is retained at `/Users/alex/Library/Caches/vinix-ios/computed-index-20261116-r1`;
its verified archive is `/Users/alex/Library/Caches/vinix-ios/computed-index-20261116-r1.tar.gz`.
Complete typed inventory and archive logical-content/metadata comparison pass.
Originals remain retained; no restoration replay is claimed.

- Archive SHA-256: `ba77aab0711fd5fa21eb85ac0ca507d924f01287823855bd4a16d2d712527729`.
- Inventory SHA-256: `2aadb51d285911b65aed378e91b4bb2e4ad4ceaccb854e1e82288f64e0a66026`.
- Committed source archive SHA-256: `b59ed7be98647c5d4c9b28997a95c4072cf113ec1565e522e394aab7b9d2a78f`.

The bundle preserves comparison rows, IR/bitcode, generated C, binaries,
commands/logs, tool identities, ownership review and source hashes compared with
the feature commit. Reproduce with `tests/ios/air-memory-computed-index.v LLVM_AS
FRESH_EXTERNAL_DIR` and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR indices`
using repository module paths and the retained captured toolchain. Local
dependencies remain referenced; this is not a hermetic rebuild. LLVM 23.1.5 JIT
code is uninstrumented and leak detection is disabled. No complete broad runtime
suite, GPU rendering, guest launch or new Fortnite frame is verified.

The [LLVM language reference](https://llvm.org/docs/LangRef.html) defines the
integer wrap/cast poison and GEP index semantics used by these bounded helpers.
