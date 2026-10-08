# Python to V migration

The target is to reduce the committed Python share to **5% or less** by porting
maintained implementations and their tests to native V. The work is in progress.
At source `789653b1cd264861631988ceece785af2dc7f0f5`, Linguist 7.27.0 reports
**Python 10.74%** (492 files, 4,481,678 bytes) and **V 74.52%** (1,335 files,
31,104,611 bytes). The complete committed-blob inventory and reproduction
command are in [linguist-files.md](linguist-files.md).

The starting snapshot, `9a70678887e1188926d6c8eacfc6b8f1432438f6`, counted
5,206,285 Python bytes in 523 files, or 12.51% of 41,610,938 classified bytes.
The measured net reduction so far is **724,607 Python bytes**. Roughly another
2.39 MB must move at equal replacement size to reach 5%; replacement sizes and
the other counted languages determine the actual percentage.

No Linguist attributes changed. First-party code and fixtures remain counted;
V code is not padded to alter the graph. Historical benchmark scripts retain
their captured bytes and Git provenance. Moving an immutable snapshot to an
archive would receive zero translation credit.

## Completed stages

Counts below describe each stage's own original Python implementations and
tests, including comments and blank lines. Their gross scope is 754,380 bytes.
The net reduction is smaller by 290 bytes of temporary G13 adapter code,
10,311 bytes of extraction bridges, 12,803 bytes of G17 foundation wrappers and
fingerprint changes, 66 bytes in the guest comparator caller, 713 bytes of the
ABI import facade, 362 bytes of power wrappers/bridges, and 5,228 bytes of ADT
wrappers/bridges after import cleanup. Adapter additions receive no extra
migration credit.

| Stage | Native source | Original Python bytes / lines | Source commit |
| --- | --- | ---: | --- |
| G13 InitData layout generator and tests | `tools/agx-re/g13layout`, `generate_g13_initdata_layout.v` | 43,273 / 1,129 | `b20290b18916e79bc9e805fc80c12b7f8ba60f7b` |
| CPU feature policy host controller | `tests/linuxkpi/cpu_feature_policy.v`, `hosttest/core.v` | 30,725 / 613 | `cd936d50fbb86bb3e709362b9c41e6d7bcd873bf` |
| AGX trace comparison and resource descriptor mapping | `tools/agx-re/traceanalysis`, `trace_diff.v`, `map_g17_resource_descriptors.v` | 38,382 / 1,027 | `16bb0b92084864049a3ec4f6ace66002fb8501fe` |
| G13 reference contract checker and tests | `tools/agx-re/g13contract`, `check_g13_reference_contract.v` | 11,783 / 346 | `6bab99862f2fdaa35ce6b4e8063cf1db88071bd8` |
| Strict allocation benchmark log comparator and tests | `tests/alloc-bench/comparecore`, `compare.v` | 33,991 / 613 | `8828abbeb4497d76998d477cf5402c6c7c4cf70b` |
| CPU mask host controller | `tests/linuxkpi/cpu_masks.v`, `hosttest/compiler.v` | 43,864 / 736 | `fc9e67b9f3e708b1c2bf535d401943b1dc981faa` |
| IRQ context host controller | `tests/linuxkpi/irq_context.v` | 25,527 / 552 | `cd509ab1abe11ba0d2a721ef3c6445535b7411cb` |
| Pagefault host controller and module generation | `tests/linuxkpi/pagefault.v`, `hosttest/module.v` | 22,314 / 486 | `7764654abe4b1e7eecfe2cf1f37fc1dd45adc394` |
| AGX firmware, fileset and PMP extraction with tests | `tools/agx-re/imageextract`, `extractionabi` | 47,310 / 1,248 | `1eb9d935609b9c7bd2e7b5f2f668dcbe612845e1` |
| Direct kernel allocation comparison, tests and validation | `tests/alloc-bench/kernelcompare`, `compare_kernel.v`, `validate_kernel.v` | 25,002 / 478 | `5e1e3f3fc0f316ff136774faaeb2c23039a60d0b` |
| Scalar read/store host controllers | `tests/linuxkpi/scalar_reads.v`, `scalar_store.v` | 39,169 / 841 | `98a1d2b40c86217f2589065026cb9c542162d569` |
| Fake-G17 plan/reference encoder/source generator and tests | `tools/agx-re/g17plan`, three V entrypoints | 120,096 / 3,008 | `e7807a42eeb0d2111ba011a17462ec8b235f5c8f` |
| Usercopy and checked-access host controllers | `tests/linuxkpi/uaccess.v`, `user_access_scope.v` | 46,230 / 1,006 | `e973e7fbb1acc808b068b74b73ea6721ef3035cc` |
| Nocache ABI/primitive host controller | `tests/linuxkpi/nocache.v` | 26,985 / 512 | `c395bd3093a50f1a42816984d1e22dbe0626ae25` |
| User-pointer compiler controller | `tests/linuxkpi/user_pointer.v` | 9,179 / 214 | `95bcfdf680f943b6521593d4110f12c388f8521d` |
| G17 Mach-O, instruction and static register recovery foundations | `tools/agx-re/g17decode` | 39,334 / 1,056 | `6868e76fc6498c6efbb9a423972e10b0c9528e97` |
| Structured ABI header generator | `tests/linuxkpi/hosttest/abi.v`, `generate_abi.v` | 18,887 / 349 | `5c3e48b4e94a6b5d629996f68faa76522e4bfa8b` |
| G17 power model/generator and linear recovery with tests | `tools/agx-re/g17power`, `generate_g17_power_model.v` | 48,309 / 1,240 | `87b211013d61f77cf24396cdf1c50fdd78fc0946` |
| Overflow type compiler controller | `tests/linuxkpi/overflow_type.v` | 13,758 / 273 | `4069c0c7430ce41033f7376dc9cadc2c7ef3edd2` |
| Apple DeviceTree/PMGR/PMP primitives | `tools/agx-re/appleadt` | 15,469 / 347 | `5c9b3749bb722a6c8a20f1fb6a776323b81416f1` |
| macOS inspection, property lists and tests | `tools/agx-re/macinspect`, `inspect_macos.v` | 54,793 / 1,388 | `bb18890e06488335a8e2e69ea10b8348900b721d` |

Shell entrypoints compile V executables in a private temporary directory using
`build-support/run-v-tool.sh` and the compiler selected by `find-v.sh`. They
preserve the caller's working directory, literal arguments and exit status.
Commit `29395517` corrected V's default adjacent output path, which otherwise
could overwrite an extensionless launcher. The launchers stayed intact in
subsequent integration tests. Commit `a8297b76` separately preserved the
generator's argument-error behavior; it receives no additional port credit.
Commits `2f201134` and `bc8577ef` select the platform C compiler and preserve
the V compiler binary's architecture when launched through Rosetta. Actual
x86 tests exercise shell routes as well as the independently compiled binaries.
Commit `5bd3b6bb` preserves explicit empty Path options, option-value parsing,
help actions and abbreviations across the LinuxKPI controllers. Commit
`683cbc7c` preserves the argument error for a bare `--`; 310 actual CLI
controls cover the ten prior controllers. These fixes receive no extra port credit.

## Validation

Each stage retained frozen Python originals until the candidate passed its
comparison gates. Originals remain recoverable from the source commit's parent.
Tests executed actual Darwin ARM64 binaries and independently compiled x86_64
Mach-O binaries through Rosetta. The host compiler was
`/Users/alex/code/v/v`, **V 0.5.2 6d549c2**. These host-only changes do not claim
new kernel builds, guest workloads or physical GPU/CPU execution.

- G13 generator: 26 native tests, all 324 GPU/version structure layouts and
  11,188 field offsets per architecture, 20 CLI/layout controls, and exact
  generated source/report bytes. Explicit 4 GiB tests check wide counts and
  offset-return widths. Production generated kernel source did not change.
- CPU feature policy: GNU99 and GNU11 each retain 1,116,514 sanitizer
  assertions on both hosts. Nine emitted original fixture/scaffold files,
  19 generated bodies, 18 native objects and two cold-header objects match the
  original controller. Literal arguments, environment, dual-pipe draining,
  the original 120-second deadline and timed-out child reaping were checked.
  The existing frozen e690943 compiler/LLVM profile generates the production
  policy model; current V builds its host controller. Independent C observer
  fixture text stays byte-exact and receives no C migration credit.
- AGX trace tools: all 16 original tests plus eight native edge cases,
  1,435 differential API cases and 29 CLI cases per architecture. Raw JSON
  numbers preserve 64-bit GPU addresses and arbitrary-width ABI integers.
  Nested filter values retain Python-style representations. A narrow libc
  `strtod` binding preserves decimal-to-binary64 rounding.
- G13 checker: eight native tests and 60 differential controls across both
  architectures, including live contracts, source mutations, missing sources,
  synthetic Asahi ordering and CLI error cases. Mutations used copied source
  trees. The maintained make targets and combined Python/V AGX test suite pass.
- Allocation comparator: all 19 unchanged original test bodies exercise the
  native implementation, alongside 21 native tests, 1,052 differential API
  cases and 21 CLI controls per architecture. Controls include complete saved
  benchmark logs, malformed records, unsigned boundaries, exact checksums,
  raw medians and unmatched-run statuses. Exact integer division and narrow
  libc decimal parsing/formatting preserve Python's binary64 rounding. An
  independent peer reviewed numeric and host-allocation lifetimes.
- CPU masks: GNU99/GNU11, native V/original C model, 15,810,213 assertions per
  combination on both hosts; 68 cold host processes, 16 emitted files, 28
  selected bodies and 16 native objects retain their original bytes. Exact JSON
  decoding preserves nanosecond provenance above 2^53 and signed/unsigned limits.
- IRQ context: GNU99/GNU11 each retain 280,732 assertions per host, 11 original
  helper/observer bodies and the actual 256-vector interrupt assembly object.
  Checks retain all 224 maskable enter/exit pairs, 32 exceptions, CS offset 152,
  IF gates, fences, jumps and relocation-table entries. The original compiler
  commands remain without a deadline; generation/runtime deadlines remain 120/30 s.
- Pagefault: GNU99/GNU11 each retain 494,347 assertions and eight fatal
  invariants per host. Complete generated C, all 130 bodies and four x86/ARM
  O0/O2 objects match exactly. LLVM IR differs only in private temporary paths.
  Compiler-only ordering, absence of allocator imports and absence of hardware
  fence instructions remain checked. Fixture and production-header bytes are unchanged.
- Extraction: 20 native tests, all 13 unchanged original Python checks,
  5,419 differential API cases and 107 CLI controls per host. Real LZFSE growth
  and decoder scratch retirement are covered. A 10,000-iteration ASan/UBSan
  fixture calls the actual exported native ABI with foreign threads. Inputs
  remain borrowed for synchronous calls; JSON/binary outputs use libc ownership
  and explicit release. Repeated foreign-loader/ownership batches retain zero
  owned outputs and bounded post-collection heap use. A dedicated loader thread
  keeps Boehm's initial thread alive when first imported from a short-lived worker.
  Narrow Python bridges remain for unported recovery callers: net reduction
  36,999 bytes. The combined AGX suite passes 270 remaining Python tests and
  four V modules. Nine real shell routes pass with the final dispatcher.
- Kernel comparator: all 26 original test bodies, 27 native tests, 1,052 exact
  API cases and 52 CLI controls per host. ARM ASan/UBSan repeats the original
  tests and differential controls. Shared helper regression retains the earlier
  comparator's 19 original tests, 1,052 API cases and 21 native tests. Twelve
  native/shell validator controls cover complete/incomplete logs, a 120 KB pipe
  and late panic. The guest runner sends the captured log snapshot to V through
  stdin; benchmark deadlines and workloads stay unchanged. A peer reviewed
  numeric behavior, error ordering and host lifetimes.

- Fake-G17 tools: 14 native tests per host, all 17 original test bodies routed
  to native APIs, 3,944 exact API cases per host and ASan/UBSan, and 638 CLI
  controls. Generated 51,435-byte kernel V and 1,583-byte ABI header remain
  byte-exact. Wide offsets, selectors and external keys retain their full
  integer values. The maintained make test/check targets and four shell routes
  pass; integration is committed separately as `e54a156e`.
- Scalar access: GNU99/GNU11 each retain 1,033 read and 26,260 store assertions
  per host. The 123 read bodies, 123 store-frontend bodies, 124 word-module
  bodies and independent invalid-width fixtures remain exact. Six x86
  O0/O1/O2 proof objects retain CPUID and immediate MOV widths, with no RMW
  or allocator imports. Supplied-header profiles and 32 CLI controls per controller pass.
- Usercopy/checked access: 197/143 generated bodies remain exact. Usercopy
  retains 9,200 assertions per standard on both LLVM 23 host ABIs; scope
  retains 449,253 per standard on both AppleClang 21 ABIs. Untouched scope
  fails on LLVM 23's unused-global diagnostic; native negative controls retain
  that failure instead of weakening warning flags. Fixtures, headers,
  compiler-only fences, normalized IR/width diagnostics and 29 CLI controls per
  controller match. Runtime deadlines remain 30 seconds.
- Nocache: 25,299,139 assertions per standard per host and a supplied-header
  ARM profile, 123 frontend and 127 primitive bodies, all eight freestanding
  frontend/ABI combinations and six x86 O0/O1/O2 primitive proofs. All 22 native
  objects match the originals. Typed inline-assembly widths, memory operands,
  CPUID ordering, NT instruction selection and the SFENCE memory clobber remain
  checked, along with no runtime imports. The fixture retains its 60-second
  deadline; 32 CLI controls pass.
- User pointer: 25,603 assertions per standard per host, byte-exact fixtures,
  headers and extracted pinned macro, all six wrong-type diagnostics and no
  runtime imports. The 30-second fixture deadline remains; 32 CLI controls pass.
- G17 foundations: 63 original functions moved to V. Each ARM/x86/ASan build
  passes 121,304 decoder/Mach-O controls, including exhaustive UTF-8 byte pairs,
  logical masks, random encodings, signed offsets and wide branches. The real
  driver retains all 6,545 symbols, ten code spans and six vtable targets.
  Nineteen recovery and 21 extraction native tests, 227 unchanged recovery tests
  (12 original private-fixture skips) and the integrated 253 Python/six-module
  suite pass. Foreign-thread tests retain zero owned output buffers and bounded
  collector use. Net Python reduction is **26,531 bytes**, including the
  loader's 13-byte fingerprint addition; `python-accounting.json` pins exact
  committed blob sizes. The public alignment helper now accepts arbitrary
  signed integers in native V.

- ABI generator: 123 original/native source and metadata controls, 44 CLI
  controls and 19 decimal rounding/limit controls. Three actual production
  headers match byte for byte with both pinned and x86 host compilers. Exact
  unbounded constants, source-root confinement, adapter arity, local capture,
  type/width validation and JSON error category remain checked. Original
  overflow/exchange and all four ABI audit-generation fixture tests pass.
  The unchanged spin controller fails in current transitive headers on both
  hosts; native negative gates preserve that baseline diagnostic. Commit
  `52a79217` changes the kernel make recipes to native V; 12 isolated make and
  original-generation controls verify exact headers, repeat timestamps and
  helper-triggered regeneration. This does not claim kernel execution.
- G17 power: 13 native tests, 4,307 model and 197 recovery controls per host
  and sanitizer profile, 48 CLI controls, four original generator tests and
  three original recovery tests. The actual driver recovery dictionary and
  11,490-byte generated kernel table match exactly. Arbitrary-width voltages,
  Q40 arithmetic, binary32 overflow and original instruction-proof mutations
  retain their errors. Platform `powf` rounding is compared with the original
  oracle running on the same architecture. Foreign-worker import calls return
  to zero owned output buffers. Net retirement is 47,947 bytes.
- Overflow types: the complete C fixture is byte-exact. Both production and
  immutable original headers retain 454 boundary cases and 4,099 assertions
  for GNU99/GNU11 on ARM/x86. Nine provenance/header/declaration mutation
  controls, 32 CLI controls, exact file-scope diagnostics, no runtime imports
  and the original 30-second deadline remain checked.
- Apple ADT: 23 native tests and 54,690 exact API controls per architecture,
  including the production import boundary. All 43 original T6050/T8103
  fixture tests and both actual T6050 manifests pass. Real LZFSE growth and
  scratch retirement, copied payloads, numeric predicates, error ordering and
  unaligned instruction matching are covered. Each host completes 8,000 calls
  across 32 distinct simultaneous foreign workers with zero owned outputs and
  bounded collector retention. ASan/UBSan also covers 10,000 direct ABI calls.
  Gross scope is 15,469 bytes; counted wrappers/bridges leave 10,241 net bytes.
- macOS inspection: 28 native tests, all 22 unchanged original test bodies,
  36 full original contracts, 2,383 additional API controls, 2,472 property-list
  controls and 168 CLI controls on each host. Binary/XML integers retain
  arbitrary precision; literal read-only registry commands, simultaneous pipe
  draining, Unicode, sorted ASCII JSON, selected-property filtering and saved
  plist behavior match. Four maintained shell routes pass from `/tmp`.
  Sanitizer gates use Boehm with the real stack and a separate `-gc none`
  fake-stack build, retaining every wide-integer assertion. An independent
  unchanged `math.big` test reproduces corruption when Boehm is combined with
  ASan fake-stack relocation; the incompatible configuration is recorded
  separately. System Expat remains an upstream parser primitive; conversions
  and binary-plist parsing are V, with parser retirement reviewed by a peer.
  Commits `5c9b3749`/`789653b1` integrate native power/ADT/inspection callers and
  the complete AGX test suite; original generated producer comments remain
  unchanged to preserve the byte-exact table provenance.

CLI help/usage, JSON decoder and OS-specific filesystem diagnostics may differ;
algorithm diagnostics, data schemas, success output and failure statuses are
checked against the originals. Assertions, timeout limits and original fixture
workloads were not weakened.

Machine-local evidence is under `/Users/alex/.cache/vinix-python-to-v/`:

| Stage directory | Qualified receipt | SHA256 |
| --- | --- | --- |
| `g13-layout-20261008` | `final-wide-source-qualification-v2.json` | `764b6228e84cf4604d1a0613aa240f1d89ec887e6f456066524665f205da9d5e` |
| `cpu-feature-policy-20261008` | `qualified-differential.json` | `81cc725dbbb222983a3393176659260948c4c6d06742d2d9d8aa42506dcca5a4` |
| `agx-trace-20261008/final-v2` | `pre-retirement-validation.json` | `517f985360c37009eb0fde8e89c06478af11c68b04ec85ba6dba33e83611ddcf` |
| `g13-contract-20261008` | `final-qualification-v2.json` | `82b2490e20dc7a0432dd24e445cfbd09ee69b7db5249fe071f681b5213751571` |
| `alloc-compare-20261008` | `final-qualification.json` | `635b83e54f2740841689ebbd42a7fbbeb6c2002385023e295031ddc7a5f5768f` |
| `cpu-mask-20261008` | `qualified-differential.json` | `26991750c66c6fea2f9a0d216a4658dfedc83f57a58961c63e443c10810909b8` |
| `irq-context-20261008` | `qualified-differential.json` | `c9682c6a274d92a82e38307602772e31d64193f279ca09d3a8f1a0518a88d807` |
| `pagefault-20261008` | `qualified-differential.json` | `b790c3692173edab83cc1d6c3d2d5908ec93ab72028c5a71f2fe1e2a75f47032` |
| `agx-extract-20261008/final` | `precommit-validation.json` | `7494ef3012d3fd3ed1404f66c9beeecb7d0cdffc835e28a86935bca217da54af` |
| `kernel-compare-20261008` | `final-qualification.json` | `51e8f6b99a83a0e1b324f93b7a2bd00fa6ba3b4becde57041596a9495699765b` |
| `scalar-20261008` | `qualified-differential.json` | `7b6b7f1b49faab37067e01a634f9c2ef44ffef93fb86ff87d3f2cdcee0c383bd` |
| `g17-plan-20261008` | `final-qualification-v1.json` | `654687dc35ee1c3f4a8b728b29973e7a0c3570623514c55cd1fdebb470ffcd05` |
| `uaccess-20261008` | `qualified-differential.json` | `3a09d15a59eebbbfa52f4edf59495072941087cbe145fdb9fece37b3bb7ee730` |
| `nocache-20261008` | `qualified-differential.json` | `db8fc5edcc7a632ad24ff8d52bf3725d84a9391c477988d88420fc879fd3b147` |
| `user-pointer-20261008` | `qualified-differential.json` | `ffd668b7e0b1ce5ffc1de3b7faeed5b5f125b761f6a6a9b65a470ebc1f7aa6ae` |
| `agx-recovery-20261008/final` | `precommit-validation.json` | `06dbaf60ec1254e4542815831d7cd956e0a90fd866941c379941750e2cd678f5` |
| `abi-generator-20261008` | `qualified-differential.json` | `5dfac93ff16b90315ce8a4f72e9ce18ce4a57d9054b7acd4e4d1db7069a619a3` |
| `abi-make-20261008` | `qualification.json` | `a2d4cd0684cbcac830672234255faa17f56091855cec15dfeb6db99b63784f8d` |
| `g17-power-20261008` | `final-qualification-v1.json` | `db7ca98b76c32ff4d812db2ad2250b6276f433efa2a84641360b75a5161d0162` |
| `overflow-types-20261008` | `qualified-differential.json` | `8b405a83166d6bc694d2db9d037397c70c4d106585e81f004cec7b1284f8ca68` |
| `agx-adt-20261008/final` | `precommit-validation-v2.json` | `576bcd4ed65b47c183390c22af548c5ad1bf0eb5025183b9413b3788affb84a6` |
| `mac-inspect-20261008/final-v2` | `qualification.json` | `d35a167b17766851319a55692d435a80c10e3794d923f5a3e4481f28e7f72aa3` |

The allocation comparator's `alloc-compare-20261008/final-qualification.json`
and `postcommit.json` bind its source, compiler, control results and exact
seven-path commit. Each other stage also has a post-commit path/input receipt.
Local caches are supporting evidence, not a required dependency of the tools.

## Continuing work

G17 expression/CFG/selector recovery, complete T8103 recovery, PCI topology
compiler orchestration and the LinuxKPI bounds/audit foundation are active.
They count only after qualification and exact-path commits. Native numeric
decoding must preserve large provenance timestamps as well as addresses; decoding an unconstrained JSON integer through `f64` loses
information. When an unported Python caller still imports an API, retain a
narrow adapter to the native implementation until its caller is ported too.

Remaining large scopes include G17 ABI and T6050 power recovery, Android/Dota
build and guest runners, shared compiler tooling, and benchmark controllers.
Keep original protocol, build profile, fixture identity, deadlines, allocation
and lifetime behavior. Commit finished stages using only reviewed owned paths,
then regenerate the language inventory from an explicit committed source SHA.
