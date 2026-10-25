# Failed Maps337 preparation preservation

Maps337 did not launch a guest. Preparation completed the JAR overlay/media
readback, then failed when it looked for the Maps335 baseline configuration at a
relative input path. The authenticated Maps335 prelaunch bundle stores that file at
`prelaunch/inputs/Users/alex/code/vinix/build/android-maps/attempt335.json`.
Maps339 is a separate retry; every Maps337 source and evidence path remains intact.

The audit ran on 2026-10-25 atop source revision
`40d53f1e081264ef4dbb232dcbb4ea6e1d0f43a4`. Exact generator source hashes are
recorded in each external build receipt. The V preservation tool is
`tests/native-android-ws/maps337-preserve.v` (SHA256
`34187ce126a78670edc8ae21326b5a7a2df193800aa428ef3e16c4748f8a15b1`).

The complete COW snapshot is
`/Users/alex/.local/state/vinix/android/maps337-failed-preservation-2026-10-25`,
manifest SHA256
`600c62d7bd0720b225acaca66dc46240b3ddf54acbec4a8a2081e10a6ca2e84d`.
It retains the failed canonical tree, prepared runtime/media, preparation
envelope, generation and runner/receipt builds, original generated C, and the Maps337
generator rebuild audits. Per-origin typed inventories preserve directory and
file modes, types, link targets and regular-file hashes. Originals were not
modified. The retained preparation envelope manifest remains
`0a64a5e6a2cbfc04fd2af383e334ff3d0be506ed9d5558330f35fdd306f6c7e9`.
Independent readback passed all 44,230 typed entries across ten copied origins
and all 20,249 regular files in the complete snapshot. Receipts are the external
siblings `maps337-failed-preservation-typed-readback-2026-10-25.json` and
`maps337-failed-preservation-complete-readback-2026-10-25.json`.

The fresh build audits below retain compiler bytes, complete V input closures
before and after compilation, snapshots of those sources, generated C,
compiler/CC hashes, exact arguments and result receipts. These are later
reconstructive invocations, not retroactive attestations of the original
bootstrap builds. The rebuilt generators were never executed.

All roots are under `/Users/alex/.local/state/vinix/android/` and end in
`-2026-10-25`:

| Root basename before date | Complete manifest SHA256 |
| --- | --- |
| `maps337-generator-audited-build` | `cd1c77f092d85210d8adf1ecbc56f5f97799a1c158ac4ba0df99a5cf38807f04` |
| `maps337-receipt-generator-audited-build` | `5c07c63e8f420467a6f28d5a072429607fc842b6a4b5b7a8691326354bf697f6` |
| `maps339-generator-audited-build` | `30e59d59d04d2a3d8626a5404e33c7635584a6f911d6068235a540005c46994d` |
| `maps339-receipt-generator-audited-build` | `687981371a506c4bd5ad3afbf8cba49cf134884f0fa4be37d69f4daf45c5f930` |
| `maps339-recovery-audited-build` | `1ed5be87d6e04e4cd58f54adf6128aa7dbd86ab26f1d83078b9c8a8334d00972` |

Each rebuild passed the unchanged `build/android-maps/build-bundle-check290`
checker with 294 files. Receipts are external siblings named
`<root-basename>-complete-readback-2026-10-25.json`. The checker SHA256 is
`52c03dc3952acf9a51c5288c12784162171c1fa83522cd1cd5ae268d79092004`;
the pinned V compiler SHA256 is
`109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e`.

Reproduce fresh rebuilds with `build/android-maps/maps337-preserve audit` and
`audit339`; those modes require fresh output directories. The `preserve` mode
also requires its snapshot destination to be absent. The `verify PIN RECEIPT`
mode checks every copied per-origin typed inventory against the snapshot,
while the existing complete bundle checker checks the entire regular-file set.
