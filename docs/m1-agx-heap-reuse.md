# Best-fit GPU virtual-address reuse

GPU allocation now searches the gaps between VA-ordered reservations and picks
the smallest complete hole that admits the aligned request. Collected interior
ranges can be reused while higher allocations remain live. Pending released
records still occupy their intervals until GC; an unsuccessful placement retries
the same checked range after collection. Invalid requests return before GC.

The highest reservation end advances only when needed. Appending and rotating
metadata pointers preserves VA order while every separately allocated record
keeps its address. Existing descending collection, release locking and owning
layouts remain unchanged. A full-capacity heap with one collected low page and
a live allocation above it now accepts that page again; the baseline reports
out of VA space.

Packaged Asahi's
[`alloc_inner`](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/alloc.rs)
uses `mm::InsertMode::Best`.
[`drm_mm.c`](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_mm.c)
ranks complete hole sizes and checks aligned placement. Vinix now follows that
best-fit principle. **Equal-size tie ordering still differs:** Vinix chooses the
lowest eligible address; DRM MM uses its size-tree order, including insertion
history. The reference source and explicit tie-policy finding are retained.
Vinix's scan and pointer rotation also differ from upstream's tree-backed cost;
native performance remains unmeasured. Backing-object and accounting policies
remain open allocator parity work.

Offline validation passed:

- ASan/UBSan runs 3,072 fragmented, aligned and pending-release cases against an
  independent model. The model enumerates candidate addresses and infers their
  free containing intervals by pairwise comparisons, independently of the
  production sorted-gap walk. Cases preserve live record pointers and check
  ordering, overlap exclusion and the maximum frontier. A targeted probe picks
  the smaller higher hole when alignment leaves equal residual space. The
  full-capacity low-hole probe succeeds with a live high pin.
- The 9,216 padding and 288 repeated-collection cases now use that placement
  model, including leading alignment gaps, interior collection, later insertion
  and complete reset. Existing 5,940 bounds cases, 13 table-growth boundaries,
  automatic GC and concurrent statistics readers pass. Ordinary churn, padded
  churn and table-growth samples retain zero additional blocks and bytes. GC
  still reclaims 8,192 records / 262,144 host malloc bytes below one live pin.
- The production allocator and production page tables run 200 uncached
  global/ASID reuse cycles under ASan/UBSan. The TLBI fixture observes a cleared
  old PTE before heap release, then the new backing at the reused address.
  Higher live mappings stay intact and all host page-table allocations are
  released. Privileged instructions are replaced; these cycles do not execute
  firmware cache invalidation. Dynamic G13 cache/UAT teardown gates are unchanged.
- Eight compiled reuse negatives reject the original capacity loss, missing
  head-hole search, first-fit ranking, ranking after alignment, lowering the high
  frontier, unsorted insertion, ignoring pending owners and premature collection.
  Twelve C mutations check bounds, retry limits, ranking, deferred ownership,
  frontier updates, sorting and temporary allocations. Existing four heap,
  five bounds, four padding, four capacity and six collection compiled negatives
  pass; construction and collection C selftests pass.
- Fresh isolated ARM/x86 kernels build. Native C has three allocation-free
  full-width placement helpers and one explicit metadata constructor; rotation
  uses stack pointer values. Six unchanged heap bodies, ten owning declarations,
  nine GPU lifetime bodies and ten event methods match baseline. Both snapshots
  match the single allocator overlay; x86 C matches after normalizing compiler
  path hashes. Independent lifetime review found no lifetime or aliasing blockers.
- All 61 focused V test files, 150 native storage guards, three storage checker
  selftests, pending-storage checks and native ARM errno probes pass. Existing
  wait, wire, fence, close, async, CPU-cache, VM, sanitized TLB, event, layout,
  render, packet and source-derived wire fixtures pass. Nine completion, eleven
  render, five compute-credit, seven event-credit and four native error compiled
  negatives pass with fresh dependent fixtures.

Allocation-site counts remain 379 ARM / 289 x86 across 833 / 813 source files.
The fresh report exactly matches the verified baseline report. Existing
allowance-check failures remain; no allowance or historical C checker changed.
Native slab rates and GPU behavior remain unqualified.

Fresh heads are Omarchy `3b36b9e19ea00a6c21492098308a7f44a8091564` and packages
`fab37d198dc6b22daf5f17da2f4d10de8346067b`. The selected package definitions
remain unchanged: Linux `bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

The whole-driver audit remains **not_equivalent**. Equal-size placement ordering,
complete allocator behavior, modern UAPI/Mesa integration, timestamp
publication/units, remaining stage backing/event destruction, manager/UAT
replacement, safe firmware teardown, reservation fences, timelines, remaining
wire/default coverage, topology and power/reset behavior remain open.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-heap-reuse-20261117/`.
Baseline is `695454cf8ccd98d4a3047a4513deffd4ce96bb7c` plus sixteen retained
source paths, including one native overlay. Independent unchanged runners are
reused after source/binary checksum checks; dependent fixtures and kernels are
fresh. The baseline fixture, generated C and failing binary are retained. The
unchanged historical inventory checker verifies the preceding complete bundle,
this complete bundle and a full archive restoration. Baseline allocator source
and the retained DRM MM source match the pinned Git revisions. Historical C
checker modes and complete original bundles remain unchanged. `completion.txt`
binds sources and reports to the commit. Generated evidence stays outside Git.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `e33617f37fdbfaf2371d6d4773f061c22ad91ab64db57a4b6990ee27298e24b7` |
| `bundle.tar.gz` | `5a84704acd89c2ceed97468e74d918fe6424f473f70e171c87be995c66b7db3c` |
| `bundle/vinix-aarch64` | `94b6ba6849e9fd05b7ce486952b590adc8f3f29cd5276cd263276c9f0e11b502` |
| `bundle/vinix-x86_64` | `7e24b40f97c08298b1006959f76f195c1da79d1cd12af022c89a1ffc988def20` |
| `bundle/blob-aarch64.c` | `5e99b7015a5aecc59f58e5533a7e005675dfff38e1db0ef291de3e366ea2ed96` |

No GPU workload, firmware interaction, Vinix/QEMU boot, reboot, SSH or deployment occurred.
