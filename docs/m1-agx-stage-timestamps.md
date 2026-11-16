# Render-stage timestamp ownership

Each completed render stage now releases its own retained timestamp pair
through the file worker. The native reaper publishes a private vertex or
fragment notification after that stage's successful ring retirement. The
worker acquires that notification, clears only the selected pair and releases
its mapping references outside the manager lock. Repeated polls consume each
stage once. Client fences and the earlier aggregate `done` flag cannot authorize
this release.

Omarchy's packaged Asahi driver retains
[separate vertex and fragment timestamp pairs](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/render.rs)
inside their respective work objects. This increment gives Vinix independent
capture retirement. Shared render backing, event tickets, result publication
and the aggregate callback still wait for both stages.

Stage and aggregate callbacks share one completion-data owner. They install
under the manager lock; aggregate completion clears the stage callback before
releasing that owner, including cancellation, shutdown and quarantine retries.
The pending-node callback count and aggregate VM pin remain live during worker
cleanup. Shared timestamp IDs keep the peer's references until it completes.
Independent lifetime review found no blocker.

Offline checks passed:

- The full ASan/UBSan async fixture executes 584 independent stage releases
  across 1-, 8- and 64-render batches, both completion orders, distinct/shared
  IDs, duplicate completion attempts, repeated polls, forged completion and shutdown.
  It checks mapping counts, peer captures, node counts and VM pins while shared
  render metadata remains retained. Existing 148 per-command retirements,
  blocked-node cleanup, rollback and immediate-completion cases remain enabled.
- Four complete source counterexamples compile and fail designated ownership
  assertions: swapped stage notification, aggregate-only release, trusting
  early `done`, and releasing both pairs after one stage. Nine native retirement
  counterexamples also pass, including wrong notification and uncleared stage
  callback cases. The actual native retirement/reaper/completion bodies run
  in the sanitizer fixture with injected disposal services.
- Fresh ARM/x86 kernels build. Generated-C comparison preserves ten existing
  preparation/cleanup/reaper/publication bodies after removing only the new
  render initializer's default null callback. Stage retirement reduces exactly
  to baseline after removing its two notification calls; aggregate completion
  reduces exactly after removing its leading callback clear. Existing aggregate
  callback disposal, both GPU completion callbacks and all six error-publication
  functions match baseline. Private stage flags select ARM byte acquire/release
  atomics. Five source overlays match both build snapshots; x86 C matches after
  normalizing compiler path hashes.
- All 54 focused V test files pass, including the allocation-source copier and
  UAPI tests. All 148 native storage guards and three checker selftests pass.
  Eight pending/timestamp helpers reject 24 allocation mutations on host and
  native C; seven capture helpers and twelve packet helpers also pass their
  storage guards. The native error probe now extracts only its target function,
  avoiding the newly adjacent stage callback. It passes seven negative errnos
  and all four compiled width/override counterexamples with production ARM
  atomic instructions on host memory.
- Wait, wire, fence, close, full async, CPU-cache, VM, sanitized TLB, layout,
  render and packet fixtures pass. Source-derived models pass 12,000 work,
  14,400 timestamp, 48,000 microsequence, 30,375 tiling, 16,384 packet-command
  and 24,576 resolved-destination cases.

Allocation-site counts remain 381 ARM / 289 x86 across 833 / 813 source files.
No new allocation site was added; existing render metadata gains a callback
pointer. The preceding complete baseline report is reused after checksum and
full typed-inventory verification; the feature allocation audit is fresh. The
existing allowance-check failure remains unchanged. Native heap rates remain
unmeasured.

Fresh heads: Omarchy `fcf6f1049a4fc6fcc78b8a3a4c70208bef09725e`, packages
`831644942f1aa0d3c6b6c3ad2ef51a19f693e2bc`. Selected package definitions remain
unchanged: Linux `bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

The full audit remains **not_equivalent**. Modern UAPI/Mesa integration,
timestamp publication/units, remaining render-stage backing/event retirement,
manager/UAT replacement, safe firmware teardown, reservation fences, timelines,
remaining wire/default coverage, topology and power/reset behavior remain open.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-stage-timestamps-20261116/`.
Baseline is `cd6e27616379b442b8f82d745f71f91674430080` plus eighteen retained
source paths, including five native overlays. Nine unchanged independent runner
binaries are reused after source/binary checksum checks; dependent models and
native fixtures are fresh. The unchanged historical inventory checker verifies
the preceding complete bundle, this complete bundle and a full archive
restoration. `completion.txt` binds sources and reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `242fe8d69443c8078bb28485e5e74a7400c41a13515ab70a11efcf4376f3d29b` |
| `bundle.tar.gz` | `35dee0f3184c9efdedcc083704ac818bce4e4e1b86409081714aafaa43371544` |
| `bundle/vinix-aarch64` | `7f46a9fb49239f42b3087acaad4503278e750ab44584e145e908a069c32e770e` |
| `bundle/vinix-x86_64` | `de91fd01a13380d77fc755f2e2587a254f3fed0d52b081171b70f34856d9d1e4` |
| `bundle/blob-aarch64.c` | `47aa0e24f1e7dd5eab398e26b4e34f8e6cd3f57fbe02fca33fa6871a8f4925cf` |

No GPU workload, firmware interaction, Vinix/QEMU boot, reboot, SSH or deployment occurred.
