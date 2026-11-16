# Compute event admission credit

Completed compute work now returns event-window admission credit before
backing cleanup. The reaper records the active published ticket's completion
after stamp proof and successful pipe-2 ring retirement, then publishes its
retirement flag. A delayed or refused UAT cleanup keeps the physical ticket,
command/timestamp backing and job metadata retained while the completed event
prefix makes capacity available.

This follows packaged Asahi's
[workqueue completion accounting](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/workqueue.rs):
`last_completed` advances before callbacks and deferred command destruction.
Its [compute submission](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/compute.rs)
uses that same workqueue mechanism.

An invalid credit record marks the manager errored and takes the existing
quarantine/error-callback path. Callback data is consumed once; repaired cleanup
retries retain the existing cached timestamp result and pending-count guards.
Prepared jobs bypass firmware retirement. Independent lifetime review found no
blocker. No owning layout, allocation site or physical-release method changes.

Offline validation passed:

- ASan/UBSan executes the actual compute reaper, completion helper, timestamp
  reader and event-credit methods with injected backing-disposal services.
  Forty ring/stamp-wrap and cleanup-refusal cases verify credit before disposal,
  pending-work retention, peer-queue isolation, retained ticket identities,
  cached results and one-shot callbacks. Callback state is freed on its first
  invocation so retries exercise real callback-data lifetime.
- Malformed rings, foreign event owners and unknown publication values retain
  backing and report one failure. Repaired retries, the actual reverse reaper
  across ring/stamp wrap, prepared caller ownership and abandoned-job cleanup
  pass. Five complete source counterexamples compile and fail designated
  assertions: withheld credit, wrong pipe, early retirement, ignored credit
  errors and replayed callbacks.
- Fresh isolated ARM/x86 kernels build. Generated-C comparison preserves eight
  owning/event/timestamp declarations, all ten event methods, ten existing
  preparation/cleanup/render-retirement/publication bodies and file/pending
  ownership. Both completion bodies, timestamp readers and all six error
  publication functions match baseline. The compute reaper reduces exactly to
  baseline after removing only its credit call, local queue alias and
  error-state write. One native overlay matches both build snapshots; x86 C
  matches after normalizing compiler path hashes.
- All 55 focused V test files, 150 native storage guards and three checker
  selftests pass. Eight pending/timestamp helpers reject 24 allocation mutations
  on host/native C. Native ARM error probes and width guards pass. The full
  event fixture passes 10,240 retained-credit completions; eleven render,
  seven event-credit and four native error counterexamples also pass.
- Wait, wire, fence, close, full async, CPU-cache, VM, sanitized TLB, layout,
  render and packet fixtures pass, including 584 render-stage timestamp cases.
  Source-derived models pass 12,000 work, 14,400 timestamp, 48,000 microsequence,
  30,375 tiling, 16,384 packet-command and 24,576 resolved-destination cases.

Allocation-site counts remain 381 ARM / 289 x86 across 833 / 813 source files.
The complete preceding baseline report is reused after checksum and full
typed-inventory verification; the feature allocation audit is fresh. The
existing allowance-check failure remains unchanged. Native heap rates remain
unmeasured.

Fresh heads: Omarchy `fcf6f1049a4fc6fcc78b8a3a4c70208bef09725e`, packages
`31a00be0422da1e6b27dbb3e99ac533123d581fa`. Selected package definitions remain
unchanged: Linux `bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

The full audit remains **not_equivalent**. Modern UAPI/Mesa integration,
timestamp publication/units, remaining stage backing/event destruction,
manager/UAT replacement, safe firmware teardown, reservation fences, timelines,
remaining wire/default coverage, topology and power/reset behavior remain open.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-compute-credits-20261116/`.
Baseline is `b7f63310a64c76ca5860bce5c308a44e8c1734ec` plus nine retained
source paths, including one native overlay. Ten independent runner binaries
are reused after source/binary checksum checks; three additional unchanged
event/counterexample runner binaries are also checked before reuse. All fixtures
and native builds are fresh. The unchanged historical inventory checker
verifies the preceding complete bundle, this complete bundle and a full archive
restoration. `completion.txt` binds sources and reports to the commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `3523d65ae6c5f671722f7285d368f452b087ddea1b2885ce9dec6ed714e5d56e` |
| `bundle.tar.gz` | `6d318e62689e3c8fc6b74fa45f046309ecb6d7ab9c5b8b5ec2d7a45ada6007be` |
| `bundle/vinix-aarch64` | `4dcb02a7c630890834d0a5dbcc091d7cfd6455e898fb2cc03a239d4c91a35510` |
| `bundle/vinix-x86_64` | `20bfdef712182f1ddb271941da3ebc2115ad4f1197203a02b28cedb60ebb704a` |
| `bundle/blob-aarch64.c` | `5ca6c490d91222217f645e6596227ec880449e5144981e29294848d4501c0717` |

No GPU workload, firmware interaction, Vinix/QEMU boot, reboot, SSH or deployment occurred.
