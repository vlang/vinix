# Indexed shader memory checkpoint — 2026-11-16

Source revision: `15329dbf41d7ebc7fb9503e1268e47f8c2e41a78`.

The memory interpreter accepts a single-index GEP whose index is a direct
i1..i64 function argument and whose base is fixed, including earlier constant
GEPs. It uses the declared allocation stride, masks the input width, rejects
negative values and checks nonwrapping offsets within 64 MiB. Every indexed
pointer and access, including cold blocks, resolves against current bindings
before any AIR write. Unused pointers permit one-past; accesses also require
their complete size and alignment. Existing constant paths retain their support.

Ordinary and prepared execution share the validation. The new
`prepared.validate(bindings, step_limit)` checks bindings and indexed addresses
without executing AIR. It does not evaluate arithmetic poison or guarantee
future changed inputs. Static minimum sizes cover the fixed component;
execution checks the current resolved addresses again. The owned offset array
is freed on validation failures, successful validation-only calls and execution
exits. Caller words/buffers remain borrowed; aliased output cannot alter the
resolved offsets or captured values. Retained heap is unmeasured.

Indexed pointers can feed ordinary loads/stores only. Further GEPs, pointer
PHI/select/freeze/casts/comparisons and memory-intrinsic use reject, including
zero-length intrinsic uses. Computed SSA indices, multiple dynamic indices and
negative argument indices remain unsupported. Software Metal can use its scalar
grid-position builtin directly as an index; the value remains zero for the
existing single-invocation dispatch profile. Larger grids remain unsupported.

AddressSanitizer and UndefinedBehaviorSanitizer checks pass on macOS ARM64:

- 37,788 exact native LLVM cases and 15,460 invalid-input refusals across all
  64 index widths, 13 allocation layouts and plain/inbounds/nuw/nusw forms.
  Ordinary and prepared execution each check every case, while validation alone
  checks acceptance and untouched output. Exact cases also compare independent
  expected bytes. Native code executes only valid inputs.
- Fifteen unsupported-shape/flow/readonly refusals and 48 ordinary/prepared/
  validate-only boundary cases cover alignment, one-past and cold-block access.
  Additional controls cover the exact 64 MiB limit, aliased index snapshots,
  64 address-space copies, readonly binding permissions and default objects.
- Fifteen existing regression programs pass: value arguments, prepared memory,
  native vector memory, scalar execution, constant/backward/structured GEPs,
  memcpy/memmove/memset and five focused layout/intrinsic/switch/vector suites.
- Both runtime hashing modes pass six builtin dispatches and 38 invalid
  pipelines per mode. Scalar/unnamed fixtures now store through an indexed GEP.
  Fresh processes of the same verified executable also pass 80 existing vector
  and 16 prepared-reuse dispatches across the two modes.

The first matrix and diagnostic rerun failed because the fixture's generic i64
alignment produced a 12-byte structure stride, while native ARM64 used 16.
The fixture now explicitly declares `i24:32-i64:64`; interpreter behavior was
unchanged for that discrepancy. Failed IR/logs remain retained. Only
`reference-final` qualifies the final maintained indexed checker and controls.
The [LLVM GEP specification](https://llvm.org/docs/LangRef.html#getelementptr-instruction)
defines signed index conversion and allocation-size scaling.

Evidence is retained at `/Users/alex/Library/Caches/vinix-ios/indexed-memory-20261116-r1`;
its verified archive is `/Users/alex/Library/Caches/vinix-ios/indexed-memory-20261116-r1.tar.gz`.
Complete typed inventory and archive logical-content/metadata comparison pass.
Originals remain retained; no restoration replay is claimed.

- Archive SHA-256: `6f7971815039645458c2c33b28301c8103427e7c3309acbe7531df35d1184b03`.
- Inventory SHA-256: `1d320e0ec0288ff07bd1b82125391a69fa8b5b1e7ac9ee760c63740d5f3d0f11`.
- Committed source archive SHA-256: `481bdb8ed27ed92b1c53ad27bf29a74c9eb2617f16c87e5f6b4f766bc8d8b244`.

The bundle includes comparison rows, IR/bitcode, native layout/target receipts,
runtime generated C, binaries, commands/logs, tool identities and reviewed source
hashes compared with the feature commit. Reproduce with
`tests/ios/air-memory-indexed.v LLVM_AS FRESH_EXTERNAL_DIR` and
`tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR builtins`, using repository
module paths and the retained captured host toolchain. Local dependencies remain
referenced; this is not a hermetic rebuild. LLVM 23.1.5 JIT code is
uninstrumented and leak detection is disabled. No complete broad runtime-suite
pass, GPU execution, rendering, guest launch or new Fortnite frame is verified.
