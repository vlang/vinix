# Python to V migration

The target is to reduce the committed Python share to **5% or less** by porting
maintained implementations and their tests to native V. The work is in progress.
At source `5e1e3f3fc0f316ff136774faaeb2c23039a60d0b`, Linguist 7.27.0 reports
**Python 11.74%** (506 files, 4,894,781 bytes) and **V 73.49%** (1,285 files,
30,628,232 bytes). The complete committed-blob inventory and reproduction
command are in [linguist-files.md](linguist-files.md).

The starting snapshot, `9a70678887e1188926d6c8eacfc6b8f1432438f6`, counted
5,206,285 Python bytes in 523 files, or 12.51% of 41,610,938 classified bytes.
The measured net reduction so far is **311,504 Python bytes**. Roughly another
2.81 MB must move at equal replacement size to reach 5%; replacement sizes and
the other counted languages determine the actual percentage.

No Linguist attributes changed. First-party code and fixtures remain counted;
V code is not padded to alter the graph. Historical benchmark scripts retain
their captured bytes and Git provenance. Moving an immutable snapshot to an
archive would receive zero translation credit.

## Completed stages

Counts below describe each stage's own original Python implementations and
tests, including comments and blank lines. Their gross scope is 322,171 bytes.
The net reduction is smaller by 290 bytes of temporary G13 adapter code,
10,311 bytes of retained extraction import bridges, and 66 bytes added while
moving the existing guest runner's comparator call to native validation.
Adapter additions receive no extra migration credit.

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
help actions and abbreviations across the LinuxKPI controllers.

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

The allocation comparator's `alloc-compare-20261008/final-qualification.json`
and `postcommit.json` bind its source, compiler, control results and exact
seven-path commit. Each other stage also has a post-commit path/input receipt.
Local caches are supporting evidence, not a required dependency of the tools.

## Continuing work

The coupled fake-G17 plan compiler/reference encoder/generator, foundational
G17 recovery decoders, power recovery/generation and further LinuxKPI compiler
controllers are the next active scopes. They do not count as completed until
qualified and committed. Native numeric decoding must preserve large provenance timestamps as
well as addresses; decoding an unconstrained JSON integer through `f64` loses
information. When an unported Python caller still imports an API, retain a
narrow adapter to the native implementation until its caller is ported too.

Remaining large scopes include G17 ABI and T6050 power recovery, Android/Dota
build and guest runners, shared compiler tooling, and benchmark controllers.
Keep original protocol, build profile, fixture identity, deadlines, allocation
and lifetime behavior. Commit finished stages using only reviewed owned paths,
then regenerate the language inventory from an explicit committed source SHA.
