# Independent render workqueue retirement

Vinix now returns vertex and fragment ring entries independently when each
stage's expected completion stamp finishes. Previously, the render reaper
waited for both stages before updating either ring's free pointer. Per-stage
publication flags prevent duplicate stores; existing logical sequence checks
prevent reverse reaping from rolling a wrapped ring backward.

Omarchy's packaged Asahi driver drains each
[workqueue's completed prefix](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/workqueue.rs)
and publishes its last completed slot with release ordering. Its
[render submission](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/render.rs)
uses separate vertex and fragment jobs. This change brings Vinix's ring-space
publication closer to that behavior. Shared job buffers, event tickets,
timestamp captures and the aggregate callback still wait for both stages.
Separate stage timestamp ownership remains open.

A malformed completed ring records a sticky failure. Reporting that failure
waits for the peer stage, so its callback cannot release captures still in use.
The existing quarantine path can retry physical retirement after failure
reporting; completion remains one-shot. Independent lifetime review found no
locking or lifetime blocker.

Offline validation passed:

- ASan/UBSan exercises the production retirement helper and actual render
  reaper/completion bodies, with injected result and disposal services. It
  checks 80 complete ring-state images across all stage-completion masks,
  wrap, 64-bit logical sequences, repeated polls and delayed peer completion.
  Reverse visits, failures in either pipe, pointer repair, invalid uncompleted
  peers, shared-backing retention and cleanup retries are covered.
- Seven complete source counterexamples compile and fail designated
  assertions: waiting for both stages, selecting the wrong pipe, coupling
  fragment completion to vertex completion, reporting a partial error early,
  forgetting a sticky error, freeing shared backing early and weakening the
  aggregate retirement gate. Binaries, generated C and mutant sources are
  retained externally with their logs.
- All 53 focused V test files, 146 native storage guards and three historical
  checker selftests pass. Timestamp/staging guards pass on host/native C with
  18 allocation mutations each. Native ARM error-width probes and guards pass.
  Wait, wire, fence, close, full async, CPU-cache, VM, sanitized TLB, layout,
  render and packet fixtures pass. Source-derived fixtures pass 12,000 work,
  14,400 timestamp, 48,000 microsequence, 30,375 tiling, 16,384 packet-command
  and 24,576 resolved-destination cases.
- Fresh isolated ARM/x86 kernels build. Generated-C comparison preserves nine
  existing preparation, cleanup, compute-retirement, publication and ring
  retirement bodies, plus callback and file/pending ownership paths. The
  render reaper's shared result/read/free/callback tail is unchanged. One
  native source overlay matches both build snapshots; x86 C is unchanged after
  normalizing compiler path hashes.

Allocation-site counts remain 381 ARM / 289 x86 across 833 / 813 source files.
The new helper allocates nothing. The preceding complete baseline allocation
report is reused after checksum and full typed-inventory verification; the
feature audit is fresh. The existing allowance-check failure is retained.
Native heap rates remain unmeasured.

Fresh heads: Omarchy `fcf6f1049a4fc6fcc78b8a3a4c70208bef09725e`, packages
`dc67eb3b39f7429f0de98febf97bd85e15125ac0`. Selected Linux/Mesa/M1 package
definitions remain unchanged. Pins remain Linux
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

The full audit remains **not_equivalent**. Modern UAPI/Mesa integration,
separate render-stage owners, timestamp publication/units, manager/UAT
replacement, firmware teardown, reservation fences, timelines, remaining
wire/default coverage, topology and power/reset behavior remain open.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-render-retirement-20261116/`.
Baseline is `6821349395e09c2c2702db9e29717e0e4e20def6` plus nine retained
source paths, including one native overlay. Ten independent runner binaries
are reused after source/binary checksum checks; dependent models and native
fixtures are fresh. The unchanged historical inventory checker verifies the
preceding complete bundle, this complete bundle and a full archive restoration.
`completion.txt` binds sources and reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `7b13d04b6bc1e5e24c23bd7ae77327cca8be7085cfc395528fe764abd9c0bed1` |
| `bundle.tar.gz` | `d11f21804b090fd4b1485024036b16f7518b0d4401101ccd807c3a534ba9271e` |
| `bundle/vinix-aarch64` | `26054a28d63614eb38c241d526dedc026461cb508d71a2f7822404bdc3a6ca51` |
| `bundle/vinix-x86_64` | `a3e412694ab0806043109be6b1d6feb993a9831f4a8c691cdd1a107852a6b6a2` |
| `bundle/blob-aarch64.c` | `e7120c8a6bee9332d88206deced5b2335b165cf99d81770f561dc4a7cbaeab2e` |

No GPU workload, firmware interaction, Vinix/QEMU boot, reboot, SSH or deployment occurred.
