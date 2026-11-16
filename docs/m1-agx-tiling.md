# Base M1 render tiling comparison

The actual native tiling helper agrees with the selected single-cluster
calculation in Omarchy's packaged Asahi
[render queue](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/render.rs).
No native arithmetic change was needed. This increment adds an independent
source model, executable comparisons, counterexamples and storage guards.

A restricted expression translator reads 29 named scalar formulas and all 13
packed parameter words from the reference. It preserves expression precedence,
casts, ceil division, alignment and conditional fields, and refuses unsupported
names, calls, casts or syntax in those selected expressions. Model arithmetic
is widened: the reference's validated 16K dimensions keep pre-layer products
within `u32`, while layered sizes require 64 bits. Sample encoding, bounds,
layer metadata and the single-cluster specialization are separately guarded.
This models selected source expressions; it does not execute Rust or translate
every statement in the function.

The ASan/UBSan fixture compiles the complete actual native helper, its two
arithmetic helpers and result declaration. It compares every result field and
the complete packed parameter image, including 112 reserved bytes, in 30,375
valid cases. Cases span pixel/tile/macrotile boundaries, all supported sample
and uTile combinations, layers 1/2/3/2047/2048, allocation sizes above 4 GiB and
full-width PPP/helper words. All 32 invalid geometries are refused, including
zero/oversized dimensions, invalid layers/samples and reversed 16x32 uTiles.

Eight complete native-module mutations compile and fail against byte-identical
generated expected models: floor tile division, missing macrotile alignment,
omitted layer scaling, 32-bit layered-size truncation, swapped packed axes,
missing layer metadata, missing TVB alignment and missing layer bit packing.
The truncation counterexample fails on a large 2047-layer case. Sources,
binaries, generated C, models and assertion failures are retained outside Git.

All 44 V test files, selected reference gates, 130 native storage guards and
their allocation-mutation selftest pass. Fresh sanitizer runs pass 12,000 work
images, 14,400 timestamp images and 48,000 start/finalize images. Existing wait,
wire, fence, asynchronous retirement, file-close, CPU-cache, VM, sanitized TLB,
layout and render regressions pass. Sanitizer linkage receipts are retained.

This changes only host tooling, tests and reports. Kernel sources match the
completed `c34beb2cfc3ef226438bf7093e4a7e64f5f2392e` checkpoint. Its ARM/x86
C/ELFs, original six-overlay snapshots, build receipts and allocation audits
are reused with explicit identity proof; no new native build is claimed.
The original allowance checks still fail at the baseline 381 ARM / 289 x86
sites with unchanged per-file/per-kind counts. No allowance changed. No new
kernel allocation, free, owner or mapping lifetime is introduced. Native heap
rates and hardware behavior remain unqualified.

Fresh heads are Omarchy `15d240a48cb0ec8ca1bb4a1959588ed969555c78` and packages
`1b93aeed9b8425e2c5ec558950939ffd38263798`. Pins remain Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. The fresh complete audit remains
**not_equivalent** (exit 1), with selected gates passing. ABI/Mesa migration,
reservation fences, cumulative timelines, queue ownership, remaining command
and initialization defaults, topology and power/reset remain separate gaps.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-tiling-20261116/`.
The complete preceding bundle, current canonical bundle and archive restoration
pass the unchanged typed inventory checker. The new bundle retains sources,
native reuse receipts, tests, counterexamples and initial harness diagnostics.
`completion.txt` binds seven source paths and two reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `116f4bc88595f6fe5fc8734ae08c1a8a9c8fe6768e35808ac156154f1b5bfe5f` |
| `bundle.tar.gz` | `9a33ca4b41fe5ec13cdd33b0ea08e269d99718fe29b2ca6e0582774d0a71d54e` |
| `bundle/vinix-aarch64` (reused) | `ee90d0b5a9422a1bbbde141fca6f7cd490fa8f90856803bdbc0790690fe38b34` |
| `bundle/vinix-x86_64` (reused) | `01e4a54e665b01ed8aa3a4bf57594f23ca7c1928d34207358b6cd4672c41c305` |
| `bundle/blob-aarch64.c` (reused) | `3cf873cd02503ad8628ba0efe672def2488763b1bd8e065bf6293c79edfef687` |

No GPU workload, privileged instruction, Vinix/QEMU boot, reboot, SSH or
deployment occurred. This comparison does not establish full driver parity.
