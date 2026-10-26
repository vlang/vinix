# Fresh atomic kernel source preparation — 2026-10-26

`prepare-fresh-atomic.v` copies 17 fixed, hashed source files from the reviewed
donor into a fresh detached worktree at
`9acefa77bee69247c837e97987a2377536aa41cc`. It also retains six controller/guest
source files before compilation. It checks ordinary-file metadata around reads,
both copy hashes, the worktree identity, and absent output/dependency paths.
It performs no build or qualification.

The helper SHA-256 is
`3d25b3032a58736db649924e4df1dcee16dd3e4f0d285204ce71da058b533a51`.
The maintained guarded controller remains
`20aa8efe95413e461a2cb95f1a0fd94331709fa79225029f334cc72103cc43dd`.
The resulting six-file tracked patch is
`c1891d5ffe3823d9d7bfe9b3b47ba14fab590f8e8e12f2afb0d47b28cc2bb5f6`,
plus the separately pinned frame-page source. Both compilers are the retained
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5` V.

Complete plans, argv, environment, generated C, logs, statuses and observations
are retained outside Git at
`/Users/alex/Library/Caches/vinix-codex/section14/matched-peer-frame-atomic-fresh-20261026`
(`R` below). Historical refused bundles remain unchanged.

- The initial full checkout failed the projected 512 MiB inclusive budget.
  A clean 14-pattern sparse checkout reduced its materialization. These setup
  operations have bounded statuses but no automatic five-second observation
  proof; `R/setup-monitoring-limitation.json` records that limit.
- Preparer bootstrap01 refused a 5,103 ms observation gap. Fresh bootstrap02,
  source copy01, controller bootstrap01, host controls01 and closure controls01
  all returned actual 0. Their original argv/status/source records remain in R.
- Build01 returned actual 1 before final qualification. Both inner makes
  returned 0; its outer size probe failed. The observer did not preserve that
  probe's stderr/status, so its precise cause is unknown.
- Build02 retained raw probe output and returned actual 1 after an observation
  gap of 197,312 ms. Its x86 make returned 0; ARM returned 137 when interrupted.
  The controller preserved partial outputs. No `qualification.json` or complete
  seal exists for either attempt.

The policy charged donor, worktree, R and the planned seal parent against
512 MiB in both allocated and apparent size, with 2 GiB admission and 1 GiB
live free-space floors. Each inner make had a 900-second limit; the outer
two-architecture command had 1,320 seconds. Build02 observed peaks of
238,164 KiB allocated and 263,163 KiB apparent, but the gap prevents a continuous
sampling claim. Its exact refusal analysis is
`R/build-02.refusal-analysis.json`, SHA-256
`42614747ba8676897932d3299ba99db42d79bc2cda07c1a662049f0ade5bd6b6`.

A post-refusal check found the source patch, seven critical source hashes and
controller unchanged, no worktree output directories, and no exact owned
wrapper/controller/make process. Its interrupted ARM input postflight did not
produce a complete closure result. An independent native observer and a fresh
both-architecture attempt remain required before consumers, guest tests,
allocation scans or performance measurements can use this evidence.
