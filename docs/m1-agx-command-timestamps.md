# Per-command timestamp retirement

The file worker now releases a completed command's timestamp captures while
neighboring commands retain the pending submission, file and VM. A private
callback-finished flag is published after completion backing is freed and before
the callback's final node-count decrement. Early `done` publication and client
signals on the aggregate fence cannot release captures. The worker marks each
command consumed once; zeroed capture entries make final batch cleanup safe.

Packaged Asahi retains timestamp destinations in individual
[compute](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/compute.rs)
and [render](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/render.rs)
work owners. Its [workqueue](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/workqueue.rs)
drains completed items, invokes each callback and queues each item for cleanup.
Vinix still combines the vertex and fragment stages of a render command. Stage
release timing and exact cross-command allocation/error order remain unqualified.

Validation passed offline:

- ASan/UBSan runs 148 distinct mapping retirements across 2-, 8- and 64-command
  batches in forward and reverse order. Each completed command releases its own
  mapping; neighbors retain theirs and the aggregate VM owner survives. Repeated
  polls preserve one-shot release. Forced early `done` flags and forged fences
  retain every mapping until private callback retirement.
- A deterministic 128-queue saturation test stops the backend as the blocked
  node's reaper acquires its completion flag. Both retired mappings release even
  though normal node polling was skipped; prepared metadata and aggregate pins
  retire on the next worker pass. Eight complete source mutations compile and
  fail their designated ownership assertions, including a blocked-node omission.
- All 52 focused V test files pass. Six generated-C helper guards pass for host
  and native output, rejecting 18 allocation mutations each. All 145 historical
  native guards, their three selftests, and packet/capture storage guards pass.
  Independent review found no lifetime or locking blocker. ARM uses byte-width
  release/acquire accesses for the new private flag.
- Fresh isolated ARM/x86 builds pass. Nine native preparation, cleanup,
  retirement and publication bodies, close, queue capture/release, timestamp
  reaping, shared staging, pending polling and three completion helpers match
  the preceding ARM C after resolving generated string IDs. Callback disposal
  reduces exactly after removing its copied index and private flag store; the
  worker reduces exactly after removing the new reaper call. All three source
  overlays match both build snapshots. x86 C matches after normalizing compiler
  discard-variable path hashes.
- Existing wait, wire, fence, close, async, CPU-cache, VM, sanitized TLB, layout,
  render and packet-reader fixtures pass. Source-derived fixtures pass 12,000
  work images, 14,400 timestamp images, 48,000 microsequence images, 30,375 tiling
  results, 16,384 packet commands and 24,576 resolved-destination images.

Allocation counts remain 381 ARM / 289 x86 with unchanged per-file/kind counts,
833 / 813 source files and the existing allowance-check failure. Native heap
rates remain unmeasured. No ownership allocation was added.

Native inspection also exposed an existing error-width mismatch: AGX `int`
error fields use 32-bit ARM atomic routines despite 64-bit V storage. Negative
error fidelity needs a follow-up fix. Full audit status remains **not_equivalent**.
Modern UAPI/Mesa integration, render-stage release, timestamp publication/units,
mapping ownership across manager/UAT replacement, firmware teardown, reservation
fences, timelines, remaining wire/default coverage, topology and power/reset
behavior remain open.

Fresh heads are Omarchy `dceae1857bc5df80eedbba07ff8a03c2dc428fdd` and packages
`bbe598b422c7427acb6f566092dab9b5b0f60641`. Selected Linux/Mesa/M1 package
definitions are unchanged. Linux remains `bed544bdf93a496ebf70ba180923bab12b6e01cf`,
Mesa `b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`, m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-command-timestamps-20261116/`.
Baseline is `d5b2404022dce0f62d7bde15e338e669d8972f72` plus eight retained source
paths, including three native overlays. Nine independent unchanged runner
binaries are checksum-verified against the prior complete bundle; dependent
model/async fixtures are fresh. Thirteen Asahi reference files, atomic V/assembly
sources, source overlays, generated C and executables are retained. The unchanged
typed checker verifies the preceding complete bundle, this complete bundle and
its full archive restoration. `completion.txt` binds sources and reports to the
feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `969981137af616eb3ad218c21bf756148f7db4ac06d647ba0fb2608c2ede81a2` |
| `bundle.tar.gz` | `a52ca74ea203be9beac187f06e0d550bcde2b1f5030c91a1d23067cba36c6dc5` |
| `bundle/vinix-aarch64` | `8e4ec1f29b4400dc00305be8dc0bb1461701e328287217ae036b0ca2f1f944b4` |
| `bundle/vinix-x86_64` | `040097091975ba1d34971ceb505a435c7772cbdfeb626c56bffd6aed3b0d6850` |
| `bundle/blob-aarch64.c` | `d6288a15d66dc808b2eea7d11f921eab99c4837722142a20442a7e57adb09fdd` |

No GPU workload, hardware test, Vinix/QEMU boot, reboot, SSH or deployment occurred.
