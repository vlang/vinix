# Resolved timestamp preparation inputs

Native G13 render and compute preparation now accept resolved user timestamp
destinations. Each engine enables its two timestamp instructions when either
start or end is present. The formatter copies both addresses into the selected
firmware ABI's command record after conversion and before flushing it. Legacy
entry points supply zero user pairs and preserve their result-buffer behavior.
Modern public submission remains unregistered.

The reference is packaged Asahi's
[optional timestamp pair](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/fw/job.rs),
[render preparation](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/render.rs)
and [compute preparation](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/compute.rs).
`UserTimestamps::any()` selects both instructions when either optional
destination exists. Vertex, fragment and compute use independent pairs.

The new preparation APIs take address values. They copy 16 bytes into
job-owned storage and retain no pointer into their arguments. Callers must keep
the validated destination mappings alive through job retirement. File capture
owners provide that lifetime, but their transfer into modern pending jobs is
still required. Capture release must run outside the GPU manager lock.
This change adds no owner transfer, free or callback behavior.

Validation passed:

- ASan/UBSan extraction fixtures compare 24,576 bounded command-buffer images
  for both firmware ABIs, all engine/phase presence combinations, full-width
  addresses and legacy controls. Every byte outside the source-derived 16-byte
  pair remains unchanged. The fixture uses the native buffer API's `voidptr`
  return type. Extracted allocation decisions match microsequence extents
  derived from the Rust start/finalize layouts, two simple headers and optional
  timestamp layouts. Source gates require both instruction guards to use the
  same engine selector as allocation sizing and require post-conversion writes.
- Eight full-source variants replay through extraction fixtures, each building
  an executable that fails its designated selection, size or byte-image
  assertion. These include the truncated copy found during development:
  fixed-array parameters lower to C pointers, so
  `sizeof(pair)` copied only eight bytes. The writer now explicitly copies
  `sizeof(u64) * 2`; the regression remains executable. V source fixtures,
  generators and counterexample runners remain in Git; results remain external.
- All 51 focused V test files and selected reference gates pass. All 145 native
  C storage guards and their selftest pass, including the writer and both
  legacy wrappers. Existing timestamp capture and packet/parser allocation
  selftests pass. Independent lifetime review found no blocker and confirmed
  pointer lifetime, pair bounds, lock behavior and legacy zero-pair controls.
- Fresh isolated ARM/x86 builds pass. Each timestamp-aware preparation body in
  generated C reduces exactly to its preceding implementation after removing
  only new selector declarations and pair writes, substituting legacy `has_result`,
  resolving generated string IDs and normalizing temporary names. Job cleanup,
  retirement, publication, file close, staging, timestamp reaping, callbacks and
  worker service match the previous C. Zero-pair wrappers and the writer have
  no temporary allocations. x86 C matches after normalizing compiler
  discard-variable path hashes. Two overlays are retained; one only corrects
  the fragment carrier-field comment.
- Wait, wire, fence, close, async, CPU-cache, VM, sanitized TLB, layout, render
  and packet-reader regressions pass. Fresh source-derived fixtures pass
  30,375 tiling results, 12,000 work images, 14,400 timestamp instruction images,
  48,000 start/finalize images and 16,384 packet commands.

Baseline and feature allocation audits retain the existing allowance failure
at 381 ARM / 289 x86 sites. Per-file/per-kind counts and source counts remain
unchanged at 832 / 813. Native heap rates remain unmeasured.

Fresh heads are Omarchy `e19607fc5ab3cbe6d2d4ebb13bd9e990db3854d1` and packages
`48d5518a286d3af5a50703670ac53da98b836f99`. Selected package definitions remain
unchanged. Pins remain Linux `bed544bdf93a496ebf70ba180923bab12b6e01cf`,
Mesa `b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. The fresh full audit still reports
**not_equivalent** (exit 1). Modern ioctl/Mesa integration, capture/job transfer,
timestamp publication/units, original mapping ownership across manager/UAT
replacement, firmware teardown, reservation fences, timelines, remaining wire
coverage, topology and power/reset behavior remain open.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-timestamp-inputs-20261116/`.
Baseline is `c8dbee634fd7ab4b79fb17fd6f9f562359829abe` plus nine retained source
paths, including two native overlays. Ten unchanged independent runner binaries
are reused after source/binary checksum checks; dependent fixtures are fresh.
Twelve selected Asahi files are retained after comparison with their Git blobs.
The complete prior bundle, current canonical bundle and full archive restoration
pass the unchanged typed inventory checker. `completion.txt` binds the nine
sources and two reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `3b83afa0e46490a16b0368b3ecfe0d7b0733d95986007133bc25b292f14b1377` |
| `bundle.tar.gz` | `7d336967a3f98412d5c19e42a5b35e1d6bd10153e49ba374e73c23c3db9ee68a` |
| `bundle/vinix-aarch64` | `39056c5429baa853b9e03ba5d610f31f5852329d014f7dff9f96ecc0b4af52c1` |
| `bundle/vinix-x86_64` | `60fc4c2f8c5dc655ac6e4a66babc230d9a5472434395057c4b78f58ae29125c7` |
| `bundle/blob-aarch64.c` | `40562d445204db66152a60d43310ecb34c083f529c00bba73788fd1ddd7adca9` |

No GPU workload, hardware test, Vinix/QEMU boot, reboot, SSH or deployment occurred.
