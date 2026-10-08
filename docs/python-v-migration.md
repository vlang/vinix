# Python to V migration

The target is to reduce the committed Python share to **5% or less** by porting
maintained implementations and their tests to native V. The work is in progress.
At source `8ead088e53de1613cb33a2698ebe31a4da75ece6`, Linguist 7.27.0 reports
**Python 8.03%** (479 files, 3,346,571 bytes) and **V 77.20%** (1,442 files,
32,178,109 bytes). The complete committed-blob inventory and reproduction
command are in [linguist-files.md](linguist-files.md).

The starting snapshot, `9a70678887e1188926d6c8eacfc6b8f1432438f6`, counted
5,206,285 Python bytes in 523 files, or 12.51% of 41,610,938 classified bytes.
The measured net reduction so far is **1,859,714 Python bytes**. Roughly another
1.27 MB must move at equal replacement size to reach 5%; replacement sizes and
the other counted languages determine the actual percentage.

No Linguist attributes changed. First-party code and fixtures remain counted;
V code is not padded to alter the graph. Historical benchmark scripts retain
their captured bytes and Git provenance. Moving an immutable snapshot to an
archive would receive zero translation credit.

## Completed stages

Counts below describe each stage's own original Python implementations and
tests, including comments and blank lines. The 45 completed stages have a gross
scope of **1,928,770 bytes**. Counted import bridges, forwarders and caller changes
account for **69,056 bytes** between gross scope and the measured net
reduction. Adapter additions receive no extra migration credit.

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
| PCI topology compiler controller | `tests/pci-config/topology.v` | 36,084 / 673 | `3befd345377bad2ce884c456e39086c7cda0a6c4` |
| Complete T8103 recovery and tests | `tools/agx-re/t8103adt`, `recover_t8103_adt.v` | 35,013 / 918 | `50ca897fcbe4aed8d06c2a182b9103d2a07ec8a2` |
| G17 expressions, CFG and selector recovery with tests | `tools/agx-re/g17expr` | 119,297 / 3,050 | `7e8c6874ac10d893d9e49d0f88574b7973856d7d` |
| LinuxKPI bounds generator foundation | `tests/linuxkpi/hosttest/bounds.v`, `generate_bounds.v` | 20,254 / 423 | `f662e77d095afed829c6dd2efecd05b4094a1747` |
| Independent heap transition specification | `tests/memory/heapmodel` | 13,042 / 360 | `7fa9a2fbc0150dcfce24b763369ecfed6edc6178` |
| T6050 DART/PTD instruction contracts | `tools/agx-re/t6050power` | 29,053 / 726 | `cd14a887431246e3b3716fe490ec08bc072ac608` |
| Independent XNU zone protocol specification | `tests/xnualloc/zonemodel` | 12,764 / 320 | `184f59417ef960311dd5fb4e3bc0c70821dd08eb` |
| G17 command and queue recovery with tests | `tools/agx-re/g17expr` | 187,668 / 4,662 | `21520b90c1c26d5494d69319eea42ec5eeb04e28` |
| Bounds publication test controller | `tests/linuxkpi/bounds_generation.v` | 22,687 / 394 | `dfadf7b328fc6b1702d336d60f5272b1dd96cbe7` |
| T6050 readiness and transport contracts | `tools/agx-re/t6050power/transport.v` | 33,982 / 829 | `e4917cc2c2a1a3c388d66e5ca8e2304817051f83` |
| Pinned upstream fetch/verify and tests | `tests/linuxkpi/upstreamsource` | 7,651 / 198 | `97eab0f419b1e832de3ed98046df0692c83d6860` |
| Independent allocator reference/model harness | `tests/xnualloc/refmodel` | 15,234 / 350 | `7b45ee15947d3d93b1503c35af3bc901dc3f54e4` |
| G17 work/resource/runtime recovery and tests | `tools/agx-re/g17expr/runtime*.v` | 177,382 / 4,842 | `817216de7261cde54bd9f8f3f210d8afd468bd17` |
| T6050 diagnostic/dashboard contracts | `tools/agx-re/t6050power/dashboard*.v` | 54,938 / 1,339 | `250a71e8df694f1fb02521d899d18f091feff882` |
| Original generated-ASM header controller | `tests/linuxkpi/asm_generated_headers.v` | 17,568 / 355 | `20be6f5958ed9e57b32b985940149c0ae6ee0c10` |
| T6050 PMP firmware and RTKit boot contracts | `tools/agx-re/t6050power/firmware*.v` | 61,485 / 1,555 | `17f53d17dfe6b34db3e4752e5eeb44d6d4d6a5d5` |
| SMP/CSD type and generated-header controllers | `tests/linuxkpi/smp_types.v`, `smp_headers.v` | 41,367 / 709 | `212eb9dbe0da88be25e0203b51dd1ebba7a38132` |
| Captured desktop transcript verdicts and tests | `tests/desktop-perf/perfreport` | 19,333 / 345 | `f4b8496f83c2bfa155ac95c308e2b62519166380` |
| T6050 image instruction proofs | `tools/agx-re/t6050power/image_proofs.v` | 44,775 / 1,102 | `6c150c08da46466209b4c8d0d10d9c3d302ba077` |
| Static-key declarations and page types | `tests/linuxkpi/static_key_declarations.v`, `pgtable_types.v` | 24,388 / 493 | `55ec8ab8b3021b5ebc7342980cf4f1b046282e43` |
| G17 configuration/channel recovery and tests | `tools/agx-re/g17expr/config*.v` | 146,167 / 3,803 | `2909aa80ab11b007910962308f5432f2abc08d86` |
| Original special-instruction compiler controller | `tests/linuxkpi/special_insns.v` | 12,994 / 244 | `18daaab0ed1bda245c96c70a05ad23297deed7d4` |
| T6050 power and PMP DART topology | `tools/agx-re/t6050power/topology*.v` | 36,327 / 870 | `9238aaf2920c12292c9a09a3d7642ec1d93b8c83` |
| Original/V FPU instruction controller | `tests/linuxkpi/fpu_headers.v` | 4,937 / 89 | `8ead088e53de1613cb33a2698ebe31a4da75ece6` |

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
controls cover the ten prior controllers. Commit `bc28715b` adds the malformed
`-h=` status edge across all ten (370 CLI controls); `fbae5cba` covers the same
edge in both ABI/bounds generators (200 controls). These fixes receive no extra port credit.

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

- PCI topology: GNU99/GNU11 retain 7,150,771 assertions per compiler profile
  and host, with current and pinned production generation. All five complete
  independent fixture/header inputs, selected bodies and compile/link arguments
  match. Seven native metadata tests, 138 API controls, 32 CLI statuses and
  three maintained shell routes pass per host. ARM sanitizer controls cover
  parsing and lifetime behavior; 300 KB simultaneous output pipes retain
  literal arguments. A real 120-second timeout terminates and reaps the child
  while preserving its log. This is a host config model, not hardware execution.
- T8103: 32 native tests, all 23 unchanged original tests, 11,224 exact API,
  169 file and 239 CLI controls per host. Three malformed help controls retain
  status 1 with a clean diagnostic. Real driver/live-capture dictionaries and
  actual shell routes match; 8,000 calls across 32 simultaneous foreign workers
  return to zero owned outputs and bounded collector retention. ARM sanitizer
  gates retain every numeric and file assertion. Native recovery and the AGX
  make/test callers are integrated by `7c2b42c5`.
- G17 expression/CFG/selector: 33 native tests, 30 unchanged original test-body
  replays and 24,416 exact full-output controls per architecture and sanitizer
  profile. The actual ABI covers 20,384 cases per host, including 4,032 rank
  controls preserving unsigned target versus arbitrary signed use-offset
  comparisons. The actual 25 MB driver selector/inline maps match, with inputs
  unchanged. Each host completes 1,600 simultaneous foreign-thread calls with
  zero owned outputs. Native instruction offsets keep arbitrary precision.
- Bounds foundation: four real GNU99/GNU11 generations, 11 publication/input
  rejection cases, three malformed markers and seven stamp cases per host.
  Headers, assembly and native compiler flags match byte for byte. Fifty-three
  API, 44 CLI and eight execute-only compiler-cache controls cover exact wide
  constants and compiler identities. ASan covers archive extraction and error
  lifetimes; copied libarchive path/error strings survive archive retirement.
  Streaming SHA, source identity and ordered atomic publication live in V.
  The 1,181-byte system archive declaration header remains counted as C.
- Heap specification: all ten unchanged original scenarios and ten native
  scenarios pass on both hosts. Each host matches 106,066 seeded MT19937/bit
  controls and 7,154 complete PMM/slab state snapshots, including every payload
  byte through hashes, recycling order, invalid frees and exact arithmetic
  boundaries. ARM ASan/UBSan retains all ten native scenarios. A peer reviewed
  model ownership and invariants. This remains an independent executable model
  and source check; it does not execute the kernel allocator or concurrency.

- T6050 DART/PTD foundation: ten native tests and 13,773 exact API controls
  per architecture; 20 frozen and 18 remaining original checks, actual driver
  manifests, 8,000 calls across 32 foreign threads with zero owned outputs,
  and 10,000-iteration C ABI lifetime/sanitizer stress pass. The returned
  metadata describes checked instruction evidence, not physical firmware execution.
- Zone specification: all six original and six native scenarios pass on both
  hosts, including 80,000 seeded operations and 10,017 complete state snapshots
  per host. Magazine identity, queue order, bitmaps, failed batches, cache swaps
  and backing retirement remain checked. ARM ASan/UBSan passes. Commit
  `49b12d88` additionally accommodates the pinned release's field/array compiler
  behavior; the same complete snapshot and sanitizer gates pass again.
- G17 command/queue recovery: 40 native tests, 35 unchanged original methods,
  6,638 full-output/error controls and 22 actual-driver outputs per host pass,
  alongside the existing expression and power suites. Arbitrary-width symbol,
  vtable and instruction offsets, strict UTF-8 diagnostics and clamp behavior
  retain their original semantics. Each host runs 1,600 foreign-thread calls
  with zero owned outputs. ARM ASan/UBSan covers the same native API.
- Bounds controller: four positive GNU99/GNU11 profiles, 11 rejections, seven
  stamp cases, three malformed markers and 37 CLI controls per host pass.
  The original 847-byte independent C fixture is unchanged. Commit `5675044e`
  uses V directly in the kernel make recipes and tracks helper V/header inputs.
  Sixteen isolated actual-make/original controls pass, covering unchanged
  timestamps, header dependencies and compiler flags. Actual raw assembly
  hashes stay in provenance: unique source-directory names and their derived
  DWARF string-offset comments are normalized only in comparison evidence.
  Four untouched-original repeat pairs independently prove the raw debug hash
  variation. There is no new kernel execution claim.
- T6050 readiness/transport: 15 native tests, 14,232 exact API controls,
  18 frozen and 16 remaining original checks, actual manifests and sanitizer
  lifetime stress pass on both hosts. Tests preserve initial publication before
  readiness, patchbay copy/writeback and ASCWrap lock/mailbox policy. Repeated
  8,000-call/32-thread batches retain zero owned outputs.
- Upstream fetch/verify: three original and three native scenarios pass on both
  hosts, including sanitizers, seven archive cases, 43 CLI and 34 API controls,
  nine transport/publication controls and the exact 7,668-file pinned import.
  Thirty-two phase-proven fault controls check cleanup against unchanged open-FD
  sets; a real 60-second inactivity timeout and immediate progress output pass.
  Initial ineffective interposition and disk-full exploratory logs are excluded.
  A 269-byte declaration-only system archive header remains honestly counted C.
- Reference harness: all four original/native scenarios pass on both hosts,
  with 5,125 complete arena snapshots, 12,000 rotating scans, 3,091 merge cases,
  40,000 mixed buddy operations and the original exhaustive slot counts.
  The unchanged independent C fixture retains both UBSan compile profiles;
  six native compiler argument controls per host match the originals. ARM
  ASan/UBSan passes. The pinned V 0.5.2 `7647ce1` Darwin release passes all 20
  independent model scenarios plus the unchanged 18 actual allocator tests
  in debug and production configurations. A Linux ARM heap-model check passes;
  additional shared-mount Linux checks blocked in FUSE directory reads and were
  stopped, so they receive no success claim. CI now runs the models separately
  from the actual allocator tests. No production allocator or SMP port occurred.

- G17 runtime: 42 unchanged original methods, 45 native functions and 14,086
  complete controls pass on both architectures and ARM sanitizers, along with
  30 real-driver outputs and foreign-thread ownership checks. Commit
  `a82845e9` separately corrects unsigned segment-size narrowing: 11,872 exact
  caller outputs, populated highword/overflow images, immutability and 10,000
  sanitized ABI exchanges pass. That correction receives no port credit.
- T6050 dashboard and firmware: 22,600 and 9,864 complete API controls per
  architecture, 16 and 14 frozen original tests, exact real-driver manifests,
  native regression suites, sanitizers and 8,000-call/32-thread ownership
  batches pass. Shared ABI stress retains zero owned response buffers.
- ASM/SMP controllers: original C fixture text and complete compiler arguments,
  headers, dependency receipts and result reports match after private paths and
  independently checked producer/stat identities. ASM retains 16 objects/eight
  rejections; SMP headers retain 22 objects/six rejections. GNU99/GNU11 SMP
  fixtures retain 420,004 CSD initializer sanitizer assertions per host.
  Current and pinned V compile the controllers on both actual architectures.
  Untouched strict sign-compare failures remain recorded; supported profiles
  keep that diagnostic visible. Controller deadlines and child reaping remain.
- Desktop verdicts: 23 native functions, 41,003 numeric/transcript controls,
  all 29 unchanged original harness tests, 800 summaries and 120 complete
  stdout/stderr/JSON byte comparisons pass on both hosts. ARM ASan/UBSan and
  success/failure installer stress preserve exact FD sets and remove private
  executables after exit. All Unicode13 nonprintable/digit properties were
  checked exhaustively. Qualified production summaries contain finite rows;
  long direct NaN lists have interpreter-specific unordered-sort artifacts and
  are outside the qualified summary domain. Guest workloads remain unchanged.
- T6050 image/topology: 15,001 evidence and 6,549 raw-image controls, then
  21,898 complete topology controls per architecture and sanitizers, match the
  originals. Frozen tests, native suites and full manifests pass. Synchronous
  inputs, copied outputs, 10,000 sanitized ABI exchanges and foreign-thread
  batches retain zero owned responses. Wide SID tests check canonical key
  enumeration separately; no billions-of-iterations original replay is claimed.
- G17 configuration: 48,313 complete boundary/mutation outcomes per host,
  34 unchanged methods, 38 native configuration functions plus 131 regressions,
  24 recursively typed real-driver outputs and 13,201 public type/error cases
  pass. Highword MOVZ offsets and INT32_MIN negation retain their widths.
  Sanitizers, fake-stack checks and 10,000 shared-ABI exchanges pass with no
  owned response remaining after foreign-thread batches.
- Static/page/instruction/FPU controllers preserve every original C fixture,
  full report/dependency/Clang argument checks and actual host profiles.
  Static keys retain six objects/four rejections and 4,001 sanitizer assertions
  per standard per host; pages retain four objects/two rejections with visible
  sign-compare warnings. Instruction headers retain 16 objects/four rejections
  and exact disassembly without executing privileged or MOVDIR64B instructions.
  FPU's unchanged x86 fixtures retain 1,024 x87/MXCSR borrows under sanitizers.
  Current/pinned controller CLI gates and ARM controller sanitizers pass.
  These host checks make no new kernel, QEMU, device or scheduler claim.

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
| `pci-topology-20261008/final-v2` | `qualified-final.json` | `80ce667aaefeca08f348c33756926daa9d98f653fc25c91a8992bf7daed0230a` |
| `agx-t8103-20261008/final` | `qualification.json` | `a49e0a3a0d1c24926c214ebf0557281ca09d94246e314855b849ed48e2eb66c8` |
| `g17-expression-20261008` | `final-qualification-v1.json` | `275e897b66eda2a44802fd6fec9837936de072d048aa511ff4efd4972ee235b4` |
| `bounds-foundation-20261008` | `qualified-differential.json` | `f622b8fa789e0c6ac48834dd30d85c1981ba7efbf3ed259546488688295ca76c` |
| `heap-model-20261008/final-v2` | `qualification.json` | `0fbd8e02f55065e26be8d1a531924cba8ad9d20f7618286580215c3c86c01c60` |
| `agx-t6050-20261008/final` | `qualification.json` | `f6373c11c8f5a46a302d17086de12f52597cee739e8ae2f5c19d4649c1f2891f` |
| `zone-model-20261008/final-v1` | `qualification.json` | `1fdcbb11cc4385b2b6d909ed0f5fef21278815a1615766511ee4cffbc1713b6d` |
| `zone-model-20261008/release-compatible-v3` | `qualification.json` | `433b9dfade73bfa3341ae26c4458d2886d8eb677105ef4c616fc3a4528e08863` |
| `g17-command-20261008` | `final-qualification-v1.json` | `c155a371887a0728da1f87182c1819dae195ed6f94fad7f067263ef0c85069c3` |
| `bounds-controller-20261008` | `qualification.json` | `4a514d4e0824591b5438ba350356f45420ff9403dc95e1824ca4c32c7863543a` |
| `bounds-make-20261008` | `qualification.json` | `64627194efb2bde571c58928e58f6418c0b0f12b2b6412aa9bacc7fcc952da13` |
| `agx-t6050-contracts2-20261008/final` | `qualification.json` | `e8f16f73c39fce61da58defb41e017c41ce34abcbdb241a2eeeff9c7eb737d5e` |
| `upstream-source-20261008` | `qualification.json` | `6462c4c499f7327d56d21646a958309fcde3dae93ad37715ab6a30630b43b801` |
| `xnu-reference-20261008/final-v4` | `qualification.json` | `d758074c6892ec7e0ce35359e3210224dcc7b581b038b5373d22b2a731f67a56` |
| `g17-runtime-20261008` | `final-qualification-v1.json` | `6220ca770db0656414899153fd0513f99991eea7a617b72021ab1823c0dd7206` |
| `agx-t6050-dashboard-20261008/final` | `qualification.json` | `769475a6e350a79417d93334a11e1432b8bb2668b7696b9b89720a1c7403bb68` |
| `asm-headers-20261008` | `qualification.json` | `f69848e63d5df306b45d763e6d1b69e6107d84a6612ab76bf34693c68d42611b` |
| `agx-t6050-firmware-20261008/final` | `qualification.json` | `f1732269659b7160451dcf7baf9099975d38052c7cc263570b1b96a023f3e970` |
| `smp-types-20261008` | `qualification.json` | `06bae0188c0dd854a5f03cf60aeaf1326098b59f04c4cad4781e56a59451f850` |
| `desktop-perf-foundation-20261008/final-v3` | `qualification.json` | `30ea179c963746ce60b9aaec1e89887ac4e0605129180c289fe2ead56200877f` |
| `agx-t6050-image-proofs-20261008/final` | `qualification.json` | `40e4a1721b7e4aad3f7c5a7a1a99ceb87d626cb1239d531095f9835080076e29` |
| `static-page-types-20261008` | `qualification.json` | `489b78a3bf256e75e4e1b1100e55f2e25ee59e0f8a3b9a86e38faeecdd721780` |
| `g17-config-20261008` | `final-qualification-v2.json` | `a82b731d518630334c59710da44e3c8a41788c8d31f08259f3d578772cda4324` |
| `special-insns-20261008` | `qualification.json` | `30ac4df57a0f9d2cef4fe1218d221f4f31ad941cf2d088f8a677ca44868d019b` |
| `agx-t6050-topology-20261008/final` | `qualification.json` | `08fd4006fa1aa8563fc4ab4a90ba48985d284834e35f18cccfec52b611c64c18` |
| `fpu-headers-20261008` | `qualification.json` | `c52fe2ee6f994e25d9690cd623338b69f85b18092a159bfa07d407daa6369998` |
| `g17-caller-span-20261008` | `qualification.json` | `61b651601e28491fa91a15fee410fefe7219ff5572ee9189db9870f36fa23dcf` |

The allocation comparator's `alloc-compare-20261008/final-qualification.json`
and `postcommit.json` bind its source, compiler, control results and exact
seven-path commit. Each other stage also has a post-commit path/input receipt.
Local caches are supporting evidence, not a required dependency of the tools.

## Continuing work

G17 event recovery, remaining T6050 image contracts, LinuxKPI compiler
controllers and verified-root image tooling are active.
They count only after qualification and exact-path commits. Native numeric
decoding must preserve large provenance timestamps as well as addresses; decoding an unconstrained JSON integer through `f64` loses
information. When an unported Python caller still imports an API, retain a
narrow adapter to the native implementation until its caller is ported too.

Remaining large scopes include G17 ABI and T6050 power recovery, Android/Dota
build and guest runners, shared compiler tooling, and benchmark controllers.
Keep original protocol, build profile, fixture identity, deadlines, allocation
and lifetime behavior. Commit finished stages using only reviewed owned paths,
then regenerate the language inventory from an explicit committed source SHA.
