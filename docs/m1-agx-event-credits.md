# Render event admission credit

Completed vertex and fragment stages now return their event-window admission
credit before aggregate render cleanup. Previously, their ring entries retired
independently, but the completed event prefix advanced only when shared backing
was freed. A completed stage could therefore remain charged against the
126-publication window while its peer still ran.

The new `WorkQueueEvents.record_completion` validates a matching active,
published ticket and advances only the signed, wrap-safe completed prefix.
The render reaper calls it after stamp proof and successful ring retirement,
before publishing the stage notification. Unknown, inactive, unpublished or
foreign-slot records cannot grant credit. Recording completion leaves all
tickets, overflow storage, user counts and physical stamp pins owned.

Packaged Asahi's
[workqueue signal path](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/workqueue.rs)
advances `last_completed` before callbacks and deferred command destruction;
its admission check uses the submitted/completed delta. Vinix now separates
render credit from backing destruction too. Retained counters continue serving
peer barriers until existing ownership cleanup releases them. Raw GPU progress
alone still cannot bypass host admission. A failed credit record follows the
sticky protocol-error path, deferring aggregate completion until the peer is
safe. Independent lifetime review found no blocker.

Offline checks passed:

- The complete production event manager and workqueue run under ASan/UBSan.
  Tests record 10,240 completions over 1,024-ticket backlogs, both visit orders
  and five signed/zero-wrap baselines. All tickets, eight overflow blocks and
  physical/initial-event pins remain retained while successive 64-command
  batches regain admission credit. Duplicate completion, invalid records,
  deferred owner release and final slot reuse are checked. Existing admission,
  cancellation, ABA, half-range, allocation rollback and physical-pin tests
  remain enabled.
- The native retirement fixture compiles the actual queue declarations and
  ownership lookup/credit/capacity methods beside its stamp test double. Forty
  stage/ring/stamp-wrap cases return only the completed engine's credit while
  preserving every ticket identity. Existing 80 ring-state cases, reverse
  retirement, actual render reaper/completion bodies, cleanup retries and an
  invalid-credit peer-deferral case pass with sanitizers.
- Seven complete source counterexamples compile and fail designated credit
  assertions: foreign slot, inactive/unpublished ticket, missing progress,
  backward progress, consumed owner and skipped overflow. Eleven native
  retirement counterexamples also pass, including withholding either engine's
  credit. Four native error-width/override counterexamples pass separately.
  All binaries, mutant sources, generated C and logs are retained externally.
- Fresh isolated ARM/x86 kernels build. Generated-C comparison preserves all
  six owning event/render declarations and nine existing event methods. Ten
  preparation/cleanup/reaper/publication bodies, file/pending ownership and
  timestamp/error callbacks match baseline. Render retirement reduces exactly
  to baseline after removing its two credit calls, local queue aliases and
  error-state writes. Both source overlays match both build snapshots; x86 C
  matches after normalizing compiler path hashes.
- All 54 focused V test files, 149 native storage guards and three checker
  selftests pass. Eight pending/timestamp helpers reject 24 allocation mutations
  on host/native C. Native ARM error probes and width guards pass. Wait, wire,
  fence, close, full async, CPU-cache, VM, sanitized TLB, layout, render and packet
  fixtures pass, including the 584 render-stage timestamp cases. Source-derived
  models pass 12,000 work, 14,400 timestamp, 48,000 microsequence, 30,375 tiling,
  16,384 packet-command and 24,576 resolved-destination cases.

Allocation-site counts remain 381 ARM / 289 x86 across 833 / 813 source files.
The new method allocates and frees nothing; owning layouts do not grow. The
complete preceding baseline report is reused after checksum and typed-inventory
verification; the feature allocation audit is fresh. The existing allowance
failure remains unchanged. Native heap rates remain unmeasured.

Fresh heads: Omarchy `fcf6f1049a4fc6fcc78b8a3a4c70208bef09725e`, packages
`31a00be0422da1e6b27dbb3e99ac533123d581fa`. Selected package definitions remain
unchanged: Linux `bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

The full audit remains **not_equivalent**. Modern UAPI/Mesa integration,
timestamp publication/units, remaining stage backing/event destruction,
compute credit during deferred cleanup, manager/UAT replacement, safe firmware
teardown, reservation fences, timelines, remaining wire/default coverage,
topology and power/reset behavior remain open.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-event-credits-20261116/`.
Baseline is `677d042c1a5ee2f0be7e493856f0ce4b1c1b0386` plus sixteen retained
source paths, including two native overlays. Ten unchanged independent runner
binaries are reused after source/binary checksum checks; native builds and
dependent fixtures are fresh. The unchanged historical inventory checker
verifies the preceding complete bundle, this complete bundle and a full
archive restoration. `completion.txt` binds sources and reports to the commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `3ed9e5478c22ddea8e3e8245e5cee3ec85faf80574061e2c9d59b1eb9e87b291` |
| `bundle.tar.gz` | `9a978dc5bdc7b0f429ae10b9fc2ecaf0607c1798541c6001c7a8bb8b8b216672` |
| `bundle/vinix-aarch64` | `15d2a49b6934cb9a00ad97cdee990e530d8b17fff0fb3b0ccc307338e5f9d6b0` |
| `bundle/vinix-x86_64` | `b80a38ef66b0e1680e248f12f05ec36afe60982bbaf4ca5b51c9a0df1a1cfcc7` |
| `bundle/blob-aarch64.c` | `6689bf1ffdb510df431885f8e2df642eac7bd98003d2085e3f3bd48287b0302a` |

No GPU workload, firmware interaction, Vinix/QEMU boot, reboot, SSH or deployment occurred.
