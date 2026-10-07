# Python to V migration

The target is to reduce the committed Python share to **5% or less** by porting
maintained implementations and their tests to native V. The work is in progress.
At source `8828abbeb4497d76998d477cf5402c6c7c4cf70b`, Linguist 7.27.0 reports
**Python 12.13%** (512 files, 5,048,421 bytes) and **V 73.09%** (1,267 files,
30,429,444 bytes). The complete committed-blob inventory and reproduction
command are in [linguist-files.md](linguist-files.md).

The starting snapshot, `9a70678887e1188926d6c8eacfc6b8f1432438f6`, counted
5,206,285 Python bytes in 523 files, or 12.51% of 41,610,938 classified bytes.
The measured net reduction so far is **157,864 Python bytes**. Roughly another
2.97 MB must move at equal replacement size to reach 5%; replacement sizes and
the other counted languages determine the actual percentage.

No Linguist attributes changed. First-party code and fixtures remain counted;
V code is not padded to alter the graph. Historical benchmark scripts retain
their captured bytes and Git provenance. Moving an immutable snapshot to an
archive would receive zero translation credit.

## Completed stages

Counts below describe each stage's own original Python implementations and
tests, including comments and blank lines. Their gross 158,154-byte scope is
290 bytes larger than the measured net reduction because the G13 checker
temporarily gained an adapter to the first native generator before its own
port. Those adapter bytes are not additional baseline migration credit.

| Stage | Native source | Original Python bytes / lines | Source commit |
| --- | --- | ---: | --- |
| G13 InitData layout generator and tests | `tools/agx-re/g13layout`, `generate_g13_initdata_layout.v` | 43,273 / 1,129 | `b20290b18916e79bc9e805fc80c12b7f8ba60f7b` |
| CPU feature policy host controller | `tests/linuxkpi/cpu_feature_policy.v`, `hosttest/core.v` | 30,725 / 613 | `cd936d50fbb86bb3e709362b9c41e6d7bcd873bf` |
| AGX trace comparison and resource descriptor mapping | `tools/agx-re/traceanalysis`, `trace_diff.v`, `map_g17_resource_descriptors.v` | 38,382 / 1,027 | `16bb0b92084864049a3ec4f6ace66002fb8501fe` |
| G13 reference contract checker and tests | `tools/agx-re/g13contract`, `check_g13_reference_contract.v` | 11,783 / 346 | `6bab99862f2fdaa35ce6b4e8063cf1db88071bd8` |
| Strict allocation benchmark log comparator and tests | `tests/alloc-bench/comparecore`, `compare.v` | 33,991 / 613 | `8828abbeb4497d76998d477cf5402c6c7c4cf70b` |

Shell entrypoints compile V executables in a private temporary directory using
`build-support/run-v-tool.sh` and the compiler selected by `find-v.sh`. They
preserve the caller's working directory, literal arguments and exit status.
Commit `29395517` corrected V's default adjacent output path, which otherwise
could overwrite an extensionless launcher. The launchers stayed intact in
subsequent integration tests. Commit `a8297b76` separately preserved the
generator's argument-error behavior; it receives no additional port credit.

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

CLI help/usage presentation and OS-specific missing-file wording may differ;
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

The allocation comparator's `alloc-compare-20261008/final-qualification.json`
and `postcommit.json` bind its source, compiler, control results and exact
seven-path commit. Each other stage also has a post-commit path/input receipt.
Local caches are supporting evidence, not a required dependency of the tools.

## Continuing work

The coupled fake-G17 plan compiler/reference encoder/generator, binary
extraction tools, CPU mask controller and further LinuxKPI compiler controllers
are the next active scopes. They do not count as completed until qualified and
committed. Native numeric decoding must preserve large provenance timestamps as
well as addresses; decoding an unconstrained JSON integer through `f64` loses
information. When an unported Python caller still imports an API, retain a
narrow adapter to the native implementation until its caller is ported too.

Remaining large scopes include G17 ABI and T6050 power recovery, Android/Dota
build and guest runners, shared compiler tooling, and benchmark controllers.
Keep original protocol, build profile, fixture identity, deadlines, allocation
and lifetime behavior. Commit finished stages using only reviewed owned paths,
then regenerate the language inventory from an explicit committed source SHA.
