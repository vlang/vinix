# Audio continuation host qualification, 2026-11-05

The parallel format-2 continuation host contract passes. Both CLI build modes
compile, all 44 normal tests pass, all 44 production tests pass with 126 retained
predicate checks, and unchanged format-1 pure checks pass 50 controls. This is
not native audio, real preparation, target compilation or guest qualification.

The maintained source began on `156c7497640dbf2015fae375ae12dccf64683956`.
The product source is the complete independent private `host-overlay-05`;
its literal map is
`1b45ccaf6f375dceef09c3e149b365fbe2b320de08f72ce6a2240cdbbecbe4d2`.
The test-only production `host-overlay-06` map is
`e57d3c6d1bcb3a42364e35c71d83a33e32062acbab09e2e27d9c21884c1fca62`.
All ten implementation files and the CLI are identical between those overlays.
The initial unvalidated draft and every failed attempt remain preserved.

## Retained evidence

State parent `T` is
`/Users/alex/Library/Caches/vinix-codex/section14/package-audio-portal/a4-independent-fixtures-aarch64-prepare-20261104-01`.
Complete host state is `T/audio-continuation-host-01` (`H` below).
Its external complete literal inventory is
`T/audio-continuation-host-01.literal.tsv`: 3,882 entries, 541,170 bytes,
SHA256 `03f4c49f2073313e3b9ed32f3a2b0277f110d1d20a376b0262b8d371ef17281d`.
It binds literal tree contents and permissions, not loaded-library closure or
native acceptance. All raw C, binaries, command/environment records, logs,
fixtures, source copies, input maps and failed runs stay outside Git.

| Evidence under H | Result | SHA256 |
| --- | --- | --- |
| `normal-controls-02/status.json` | 44 normal tests, exit 0 | `42bfece12f450a449656fd9aa29481800ff0cdbd2a11b17cd1723278d433919c` |
| `production-controls-01/status.json` | 44 production tests, 126 sites, exit 0 | `cf8aaaadceb8d5916589d2a1abd39dfb5f6227cddb9869973084f7cfb0ab9537` |
| `production-forced-false-01/status.json` | exact expected exit 1 | `1b78d84aacccbdefc13dc94122ebd751204b26129cd1cde82c26619e3fb5ad22` |
| `format1-prepare-pure-01/result/result.json` | unchanged pure 50, exit 0 | `858253f2653367b891cb5fc43d41d36a360eadd22aad9d5ed89ed5e860d51952` |
| `final-status.json` | host scope and limits | `a5d92c56b46d2ca9a5546aad5ffa0b540a4f2fdbac1b4396a1958dbd36d988a2` |
| `reports/final-endpoint-01.json` | six-root endpoint | `cc636c5ddc37932ac0e2b826542f6fca04c2c1a44b85851be4e97a218d29a912` |

## What the checks establish

Exact shared specifications bind all twenty command receipts to their entire
argv/environment/source/flags/output roles. Tests exercise the actual frozen
receipt wrapper, strict schemas, all eight missing-execute-bit ELF refusals,
source-content/base provenance, independent donor partial observations,
resource arithmetic, cancellation/deadline gates and publication failure.
Candidate and final verification share one boundary; exclusive atomic rename
is the last fallible publication step. Full real manifest/target/publisher/audit
integration remains pending.

The APFS regression exposed that adding an excluded regular receipt changes
root directory nlink. Only represented owned-root nlink, size and times are
normalized. Mode, owner, device/inode, nonroot metadata, file alias checks,
complete membership and raw intrascan comparisons remain bound. Actual retained
normal and production witnesses record raw nlink 3 to 4 with unchanged inode
475249454 and 476763563 respectively. Normalized fields and identity were
asserted; full normalized records were not separately serialized. Added files,
empty directories, changed mode and replacement-root witnesses remain retained.

Each mode executes four real `Engine2.command` owner cases: clean exit 0,
nonzero 7, timeout/deadline with exit 137, and a held output pipe. All eight
typed results confirm observed ownership, reap, empty group and final waitpid
-1/ECHILD 10. Parent CFLAGS restoration and sticky SIGTERM refusal checks pass.
Children are finite, private copies of the pinned fixture. These results
qualify those owner fixtures, not compiler process-tree cleanup.

Pinned V removes language assertions under `-prod`. The first production-test
compile is preserved as failed qualification and was never executed. Seven
test-only companions now preserve exactly 126 condition expressions through
ordinary if/panic calls. Runtime hard hashes/site counts/full inverse equality
and independent source review bind every condition and surrounding byte.
Generated C review confirms 44 definitions/calls, 126 predicate calls plus the
same forced-false call, and initialization proof before the first test.
The identical production binary first exits exactly 1 with all three distinct
markers and an empty fixture parent, then completes all 44 checks with exit 0.

Latest successful C and binaries:

| Phase | C SHA256 | Executable SHA256 |
| --- | --- | --- |
| `normal-cli-03` | `caaa290bd1189b2a7db103485be69228daa1829154f79e05964ba6527879777f` | `ca1a6570998242a5e117e9059981ca47c70a338060b3f46e7ec47740d464fdde` |
| `production-cli-01` | `3b4d38e772bd815797275401b455e4b6064003d2d3a672148d0fe7e85ead1241` | `4491f2fb8b45db7276cf718741f1b7d21712310b39672ce69fe3a42e0cc8c082` |
| `normal-tests-03` | `ecddde14ca732ec4c6d0b8770ddb6d93005fd50705cf68c85602efbdde6f0bc1` | `ea5100fd59653a59abf08d9cc7d246accb12d35fd2f65d53d87878a807921c26` |
| `production-tests-02` | `784c21f4dd2960dfdf81e27844c01f074c1c18135f5033ec8c31e0d7eadbf2f4` | `9c51cc21c43fddd625a383fab7e0fe3f8e8531f9b48ae436e7a3dc11e3cf4543` |

## Composition, closure and limits

The qualified workflow uses an explicit private guard overlay; the shared
historical guard stays exactly
`5aa9cea7b338b914f7548a9a63a86ae6874dabb373350a5605f068fa7f2858ce`.
The private guard
`bd8505ab1f343ba918f980716af0a6408601dab9a625b0792c6483bf7b7d6630`
changes only eleven internal identifier references to avoid a pinned-compiler
namespace collision. Source derivation bootstrap/read-only `--controls` pass;
its `--emit` writer remains unexecuted. No default shared-import build claim is
made. See [the composition instructions](audio-portal-continuation-plan.md).

V `ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`,
clang 23.1.0, explicit SDK 27.2, clean recorded environments and strict pointer
diagnostics were used. The final retry explicitly selects
`-new-compiler -no-retry-compilation -nocache`; matching launcher/driver source
supports fail-closed dispatch. Earlier marker names alone are not asserted as
fallback proof. No compiler tree or historical checker was changed.

Normal five-map and production six-map cohort endpoints match completely:
selected host-source roots, original/derived source, compiler tree, clang
include tree and SDK usr/include. Ten direct tool/SDK pins match. This is
literal cohort endpoint evidence, without whole-SDK, loaded-library, hermetic,
continuous input or RSS claims.

GNU timeout uses TERM 300 seconds/KILL after 10 for compiles and at most
180 seconds for controls, with bounded logs. Compiler results establish actual
exit and retained output, without typed descendant-cleanup claims. The existing
native owner supplies the separate four-case cleanup evidence.

Reviewed plan 11 increases the internal host allocation from historical 96 MiB
to 112 MiB, always preserving a full 16 MiB tail inside the unchanged 2 GiB
aggregate cap over the original six roots. Every failed counter/bootstrap/test,
source copy, cache, fixture, log and map remains charged. Admission requires
2 GiB global free space, with the existing 1 GiB live floor. The final pre-map
endpoint measures 1,873,891,328 allocated and 2,118,201,344 conservative apparent
bytes (each pathname rounded to 4 KiB). Against baseline 2,025,447,424, that is
92,753,920 new bytes. The frozen final status initially reserved 4 MiB for
remaining proof and integration. Main integration measured a 3,153,787-byte Git
index, so the subsequent conservative reserve is 6 MiB, including the entire
temporary index copy, external literal map, final documentation/metadata,
independent main source copies and supplemental Git objects. This is a
reallocation within measured remaining body, not a cap increase. Adding that
reserve and the untouched 16 MiB tail gives 115,822,592 new bytes and
2,141,270,016 aggregate, below both limits. Endpoint measurements are not
continuous dual-cap enforcement.

No reviewed real Donor2/Source2 manifests exist. Real continuation needs at
least 200 MiB new preparation outputs plus dynamic full-map/receipt reserves;
the retained namespace cannot admit it. Guest qualification needs separate
source, owner, resource and complete-retention work for all three scenarios.
Section 14 native audio acceptance remains open.
