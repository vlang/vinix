# Complete slab observer host and target qualification

Normal and production builds each passed **373 explicit parser/reader controls
and 57 complete-transcript controls**. Both AArch64 and x86_64 observers linked
as static, little-endian ELF64 executables with strict pointer and format
diagnostics. Independent generated-C reviews passed. No new guest or kernel
memory/performance qualification is claimed.

The parser admits the entire pinned fourteen-class slab schema, large pages,
the written-after-free footer and successful EOF. Complete before/after bytes,
object/page deltas and both footer values are preserved. Qualification rejects
any nonzero exact delta or either nonzero corruption counter, including rounded
or cancelling allocations. The observer continues measuring nonzero results.

The source base is `ce23a45d441da46ff867b42c487d6f6f8efe2113`, plus the captured
observer sources. Documentation was updated after execution. Raw source copies,
commands, cleared environments, generated C, binaries, original input checks,
complete output, statuses and endpoint observations remain outside Git below
`/Users/alex/Library/Caches/vinix-codex/section14/`:

- `perf-heap-producer-compiler-20261105-02` retains the independent compiler
  derivation and the later failed fixed-array/GCC target attempt.
- `perf-heap-producer-value-cursor-20261105-01` is the accepted fresh observer
  qualification. Its retained action labels remain `A2`/`B3`; these are the
  source-corrected retry scopes called A3/B4 during review.
- `perf-heap-producer-value-cursor-20261105-01-seal-01/inventory.json` is the
  unchanged original full-state seal, SHA256
  `4cd56552c06c5459fb2a0cde20a2eee467296737d64f08ebbaf8948c0f0a7ac1`.
  Its separate original check passed with the exact completion marker. Audit
  output and the five successful original header postchecks are outside the
  sealed state.

The accepted plan SHA256 is
`28f936615f59e5f7be101e31f101800caa5b5853b300a8803fb5c887ed9c68de`.
The complete as-run source inventory SHA256 is
`b7cbd1fb6859e1526c4630ae09db454b86ea3811b7f6b17633f3cb0bfacd518e`.
The state contains `selected-artifacts.sha256` and the executed action driver's
source, generated C and binary. Every host/target action returned its expected
status; usage, absent input, invalid architecture and existing-output refusals
remain failures. The invalid-architecture output remained absent.

Both host and target phases passed unchanged full original source, parent and
derived-toolchain checks before and after execution. All five original musl/GCC
header-tree checks passed before and after target linking; the selected CRT,
static libraries and direct tool pins stayed unchanged. Readelf reported the
expected machines, no interpreter or required dynamic library, and both legacy
and V observer symbols.

| Target | Generated V C SHA256 | Static ELF SHA256 |
| --- | --- | --- |
| AArch64 | `be18c3499e91ee3804d5bccbbb7ccb426c99f7e843b16d53adf73aff3bdc9d81` | `bb7097a944cf20d176d78e60865841b7272ba21c9bcca1528d943c947490014e` |
| x86_64 | `6df7f55cdcdbdfeaa59246bd30b68176a8e235961e4e1772bf6d4ba538bc9cbd` | `e7874d55c93a6bb1dd2e0821974885437778535a696ce8f14c9eb7e2df95d21f` |

The parent ff75 compiler remains unchanged. The independent successor SHA256 is
`53debcfe66952ba952d64b2b94dbb2408bed6992453d1ac6bad5889e4bd1ec7e`;
its original complete literal-tree inventory is
`91522669adf530d589bffacfb1be6190a75dd04d0dd5fd844a035d928b609377`.
The preparer allows exactly the pinned historical ten-file bench adjunct, one
printf precision cast and the new executable. Bootstrap C is retained outside
that tree. The ordinary bootstrap used the parent's default diagnostic flags;
strict target links used independent clang23/lld23 with explicit pinned musl
headers, CRT and libraries, without warning suppressions or generated-C edits.
This does not establish a hermetic host SDK/loader or compiler source closure.

Earlier failed attempts remain preserved. Generated-code review caught a
24-byte `memdup` even for an addressed fixed-array cursor. Passing cursor state
and helper results by value now produces automatic C values on both targets.
Review also confirmed automatic snapshot/delta/reset/argument storage, native
i32 signal handlers, warm reset before the cohort, complete reads and cleanup,
and proof output after both snapshots. Error boxing is confined to refusal
paths. The strict GCC attempt rejected the unchanged legacy scanf suppression
format; the accepted strict Clang route retains the original C hash
`2490bc0e69142080f52a469e241cbb37d61d0e0687a191618654a3b617b68771`.

Endpoint guards retained a 768 MiB allocated/apparent ceiling, including earlier
attempts, with 128 MiB reserved inside it, 2 GiB phase admission and 1 GiB
continued free-space floors. The last target endpoint recorded 367,540 KiB
allocated, 355,785 KiB apparent and 59,514,952 KiB free. These are sampled endpoint
observations, not continuous disk or RSS bounds. Adapter host qualification,
prepared images, native measurements and current-kernel integration remain
separate gates; the two adapter changes are excluded from this component.
