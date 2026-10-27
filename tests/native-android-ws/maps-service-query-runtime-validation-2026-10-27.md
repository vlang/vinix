# Maps service-query diagnostic: missing metadata field

The generic fixture failed on missing `ComponentInfo.directBootAware`; GMS
failed on the same field through `ServiceInfo`. The closed VM retains
`fixture-negative-cause.png`, the fixture's appended UART child output, and
`gms-directboot-error.png`. `maps-launch.png` shows the Android loader, and the
GMS screenshot includes the exited Maps window. This run establishes neither
a successful service query nor authentication or a working map.

External paths below are relative to `/Users/alex/.local/state/vinix/android/`.
The closed run is `maps-service-query-vm-r1`. This audit issued no VM action.

## Exact inputs and lifecycle

The [service-query stager](maps-service-query-stage.md), revision
`61088f06c`, produced `maps-service-query-r1`, manifest
`4d4850aa0f4204999e0d8d9c0cdd3ef0466b4d67c9b26ea371005e4cc93e0b9b`.
It retains all nine prior modules and adds the six-file framework/metadata
overlay. Framework revision `c58cdfba6d9de55e14bdbd1cd8eee8f0fada033e` changes
`PackageManager.queryIntentServices`; it does not add `directBootAware`.
Complete framework producer
`combined-account-webview-service-query-framework-2026-10-27-r1` has manifest
`12f21e139e2602fa9517c6df7d2fda866d366d4d5f0cce6d7e07d62bbd044559`.

The r6 account controller remains revision
`d6d72faa07e30faf9e441cd7ed57242d28bd1960`, executable
`894e57f0eaf773777b3107100068edf1f9b57b427b565756767c576a0de8c6b6`.
The dedicated service-query kernel patcher is
`c4555e4c7967bb7031f16154cea957fe5cc0e94834a3c0ae29876bd813e67b76`,
with complete closure manifest
`15afc71d235487f12a74d5522d9d1b5f7768e91ad7cdb2ada92a3b0b433b6485`.

Owned QEMU PID 54972 launched at 2026-10-27 00:43:32 UTC with 12 GiB/four CPUs.
`stop.json` records SIGTERM at 00:51:07 UTC; `gone.json` records an absent-PID
snapshot at 00:51:16 UTC. The operator reports the known stop identity race;
the reconciliation succeeded. QMP socket and pid file are absent, and
`qemu.log` records signal 15. No QEMU wait/reap status is asserted.

| Closed receipt or screenshot | SHA-256 |
| --- | --- |
| `stage.json` | `811bd187163c4fdc1adec5149c8f028e71482b3e77702a4bbfdc727862d2f83f` |
| `kernel-patch.json` | `40706f99adfc426535778bbcaf9da2e9cfbf0969988b8af69d9142b9557f9cb2` |
| `launch.json` | `b0f544f48cbdf56b41912295a0f91c57d2d80138d4209e68ad03b17d0ac7d9e5` |
| `stop.json` | `c05b0233cdf9375a99cff82b6e772c12e11bc478aa7f55dc72863fe4578f682f` |
| `gone.json` | `dacfd89a4ee63a2cfd336e6bf4ba297531c0dc434673652a0f2b3ab9e98ab593` |
| `fixture-negative-cause.png` | `50602627ae7dd8e35e522c3158ddd3a5b8c3ff6e5ab91b2a067ab419481a9746` |
| `gms-directboot-error.png` | `0670772262d0050a5d1461e08ae330ada62106c8ab5741f711b856d2a2534cb9` |
| `maps-launch.png` | `ec112aabe4a2ddd8ed951647b1bac1ce7cada8b78a2fc6323e638237bbe8e2af` |

Host snapshots during Maps and after GMS exit both record QEMU RSS
12,754,736 KiB. They are not peaks, proof of whole-guest memory exhaustion,
or an explanation of the earlier 92 GiB host-memory report.

## Transfer and failed strict collection

The [credential-free transfer](service-query-transfer-2026-10-27.md) retained
three immutable inputs and exactly three successful HTTP responses in
`service-query-transfer-live-2026-10-27-r1`. They are the 956,576-byte generic
runner and 12,713/8,617-byte client/disabled APKs. Complete fixture producer
`service-query-fixture-2026-10-27-r1` has manifest
`27050d7a8649e8ee7fe996007334a06a9ad957a4d1cf78fb4f90a43419a1200c`.
These host transfer receipts do not establish a successful guest fixture.

Final UART is 2,284,215 bytes, SHA-256
`776f98cbc0e3a244da13d7aa4576deeaa2eae613e45175a030f5440278bd0fa9`.
BEGIN line 399 and END line 6029 announce archive
`f0057045f0759806d8288bacfeef26c614e27ee67d11649e17b4528becbfd9f9`,
1,439,702 bytes in 2,812 chunks. Kernel exec/ELF diagnostics interrupt chunks
1506 and 1507; one ELF record is interleaved around eleven payload characters.

The unchanged `maps-account-collect-r2` independently reran against closed
UART and exited 1: `unknown export frame at serial line=3413`. No strict import
was created. Its executable is
`f1245b715d75ab41a6f1c8b3c0d45e1aed9158bfe3cd097c939ee845a3b1b29e`;
retained older source is
`15e78f25a72da1a34ae8bfd7303bebaa8a20a46af4cedc10ac7a4da6bac10990`.
No equivalence to the concurrently changed Git collector is claimed.
Rerun took 0.05 seconds, maximum RSS 16,318,464 bytes, zero swaps. Plan-local
`closed-collect.log` / `.time` pins are
`3fa41c428ff747b406066f7484d6afc98ee01a04ad2e89e849ea22a095bfb4a2` /
`407d81da667b807223f2fd6163c07b28245567c57ee4b8a652fcc28eca980d03`.

## Diagnostic derivation and retained closure

The separate [diagnostic reconstructor](diagnostic-uart-reconstruct.v) requires
an explicitly pinned source and literal byte-removal plan. It protects every
original frame header, verifies all canonical sequential chunks against the
announced full archive size/SHA-256, and validates every regular entry's
size/encoding/hash. It writes a diagnostic archive and selected public metadata
to a fresh private external directory, never a repaired UART or `import.json`.
The r6 exporter excludes private broker and Maps logs; the diagnostic cannot
recover them. Diagnostic use leaves the original strict failure unchanged.

Tool revision is `2d2e7abfd207b0115bd0a897cb8e847bb278c0da`; retained source
and executable pins are respectively
`9ff07d5a6bf1b35a688912abf18ae998d008331260dcfbbe9bb972ba6c94a64f` /
`296fec6830a6e61bc408d2a09d1d1e11da7a04230df665532469e8ca3a374957`.
The explicit plan removes 200 kernel bytes in five exact ranges and preserves
the eleven payload characters between split ELF fragments. It is pinned to
`bda6f9ad48e80e341a159a10350d0124121bf14cbe7bc8f64c706d4abc976e28`.
Actual derivation passed the full announced archive hash and all 21 entries.

| Final measured command | Seconds | Maximum RSS, bytes |
| --- | ---: | ---: |
| Boehm host build | 4.84 | 228,081,664 |
| Self-test: 4 positive, 29 negative | 1.53 | 3,915,776 |
| Actual diagnostic derivation | 0.27 | 33,210,368 |

All exited zero with zero swaps. Source bounds are 8 MiB UART, 4 MiB archive,
64 KiB plan and 32 removals totaling at most 4,096 bytes. Earlier compile,
literal-plan and output-qualification failures remain retained. The added
filesystem test caught ignored `wx` exclusivity in this V version; the final
writer uses native exclusive creation and checked close/readback. An earlier
compile peaked at 908,509,184 bytes. Final compiler/runtime measurements do not
establish a universal memory bound.

Plan-local `derived-diagnostic-r2` contains the verified archive and only the
selected public receipt/log-hash metadata. The receipt reports failed GMS
broker, `service_ready=true`, broker exit 1 and zero cleanup survivors. Readiness
is transport readiness. Empty auth/browser failure arrays establish no success.
Only the excluded broker log's hash is available:
`9478344f95929a31437cce89e2b2d3c415b6a6d1ac181c0ff74639f01c65df5f`.

| Derived metadata | SHA-256 |
| --- | --- |
| `diagnostic.json` | `497f4622e1a9a73a7077cd2604283c26755046f673d2e05d907b4af55f7feecc` |
| `exported-receipt.json` | `66cdc1b1d9fa7a60b3ba7255838a94cd3a4a8fb94eba44963255216391b6e2be` |
| `exported-private-log-sha256.json` | `24d4236e4519454388eaf57e8fb3eb972fe24ce5941f0dc9ad68be8938bfbfa8` |

Final derivation log/time are
`c60777c5cd73096fa6c96b734ac081eaacbcece42c3d30513b1d9b7c9afa3895` /
`0c963dbea45e665aef1a8169a36fa2467b740908dd285ce0daf3223bc8ec1837`.

The new delta plan is
`maps-service-query-vm-r1-stream-plan-2026-10-27-r1/roots.txt`, SHA-256
`eefc8e68855516333945142cfef781223ad02f7180b9ba801ebdf07bd428d633`.
Its 44 canonical nonoverlapping roots retain the
complete current VM, producer, framework, fixture, runner, transfer, provenance,
qualification/tool receipts and selected extra SDK tools, plus the preceding
complete controller manifest/inventories. The original controller closure and
all of its original inputs remain required, not replaced by summaries.
Its unchanged full check freshly passed all 60 roots/51,109 entries in
52.51 seconds, maximum RSS 21,970,944 bytes, zero swaps, pinned to
`f2407f1b7b23ae6c453afef451831e5f24889eee6933f49e79d51441d7ce6da5`.
This selected-tool audit does not establish recursive historical ancestry or
a hermetic SDK/C/shared-library/QEMU rebuild closure.

The final delta is
`maps-service-query-vm-r1-runtime-sealed-2026-10-27-r1`, manifest
`0341a63a280f6a8c43db20a663dc873d0918676c61b739ce52b7808169a80f32`.
Seal plus built-in full check passed all 44 roots/8,005 entries in 14.88 seconds,
maximum RSS 27,099,136 bytes. A separate pinned full check passed in 9.45 seconds,
maximum RSS 23,166,976 bytes. Both exited zero with zero swaps. The new manifest
directory occupies 2,080 KiB; its retained plan/diagnostic directory occupies
3,784 KiB (`du -sk`). Original large input bundles remain in place.

Adjacent files use prefix
`maps-service-query-runtime-stream-2026-10-27-r1`:

| Suffix | SHA-256 |
| --- | --- |
| `.seal.log` | `fcf3e3309fa56ee9c7a090b165b2768962455a48e560ace3b305229ce5ecfcbb` |
| `.seal.time` | `1d3feefcb1dce49e06c8976629ff64cc0545c38ca6a5f71d137ff4ca779da65c` |
| `.check.log` | `fffe9d3cf2ec2c165a7542674cf2f1a3f9b1dd91b21158bb76240b50e393b2f6` |
| `.check.time` | `e87ae6a1ce6dd13e946e84fcce2d8b23a21d49c8a9113053d4d92a7481912be8` |
| `.du.log` | `25dcf90f40f78b059a8dd9d3082db536a0b4b24a7d469e068ffba35385e4f2a8` |
