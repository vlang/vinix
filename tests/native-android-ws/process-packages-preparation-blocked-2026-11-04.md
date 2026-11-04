# Process-package image preparation blocked by disk reserve

The process-package SDK/native fix, signed fixture and delivery are committed
and [host-qualified](process-packages-host-2026-11-04.md). Image staging is
committed in `385535613`; all 15 qualification phases passed, including the
69-control stager self-test, complete SDK/native audit, helper enumeration,
142-inventory batch suite, 55-stage ancestry and capture of 850 inputs.
The [image-tool report](maps-process-packages-stage.md) identifies the complete
frozen tools and qualification evidence. Preparation and ARM execution remain
pending; no successor GMS or Maps result is established.

Paths use `S=/Users/alex/.local/state/vinix/android`. The qualified executable
is `S/maps-process-packages-tools-2026-11-04-r2/stager-project/maps-process-packages-stage`,
SHA-256 `c341a1ea643046cc25adc193871726d72988275805aefa7c20f995f847a67600`.
Its six-root, 18,189-entry tool seal is
`S/maps-process-packages-tools-sealed-2026-11-04-r2/sealed/manifest.json`,
SHA-256 `c2bfbf96a8d2f8b2331012b6b57f4c71b873c0831dff4291378ae6bcd98e6ef6`.
Sealing and independent fresh readback passed with guard/child zero and
complete cleanup. The first interrupted seal remains included.

At 20:56 UTC, the authorized preparation guard refused before launching a
child because free space was 927,457,280 bytes, below the 1 GiB reserve.
Complete controls remain at
`S/maps-process-packages-preparation-2026-11-04-r1`. The receipt
`prepare.guard.json` hashes to
`30206b74e988e0328b21975dc08cdb5e3e25c1ff604e0e8904726a095ebf0bc7`.
It records guard125, child-1, reason `disk reserve`, PID0, zero RSS
samples/groups and `cleanup_complete=false`. No stager or VM was launched,
and the intended output `S/maps-process-packages-r1` was not created.

The guard retains the explicitly authorized 30-minute audit deadline and
4 GiB outer shared-filesystem growth allowance, 600 MiB RSS, 1 GiB reserve
and 4 MiB output limit. The original shell file cap remains unchanged.
The stager independently requires at least 5 GiB initially and retains its
separate cumulative 512 MiB write budget, including 125 MiB charged for
complete module/kernel digest receipts. No limit was bypassed.

Resume when free space exceeds 5 GiB with enough stability for the complete
audits. Reuse this qualified executable and its exact sealed SDK/native pair;
no additional framework, native, fixture or tool build is required. Use fresh
controls, prepare a new closed output, retain both complete 142-inventory
audits and all module/kernel readbacks, then clone the closed image.
The frozen kernel is inherited; no kernel installation is needed. Use the
qualified coexistence admission against the then-current foreign identity,
run the [process-package ARM fixture](process-packages-fixture-run.md), validate
its receipt/export, release its dedicated mount, then retry GMS stability and
Maps through the supported controller.

CI PID23708 remained running and untouched. The previous owned VM remains
stopped. No cache or evidence was deleted. Preserve all complete host/tool
bundles and failed attempts. After space temporarily recovered to about 2 GiB,
the complete preparation controls were sealed and independently read back at
`S/process-packages-preparation-attempts-sealed-2026-11-05-r1/sealed/manifest.json`,
SHA-256 `844a37353405044def332444bc07ffb0630b58e3fb14c0c44a04d255add3604a`.
This one-root/three-entry seal retains the original refused guard and empty log.
Seal and fresh readback passed with guard/child zero, empty reasons and complete
cleanup in 55/58 ms; sampled RSS was 3,063,808/6,635,520 bytes and observed
growth 413,696/12,288 bytes. Both retain 600 MiB RSS, 900 seconds, 64 MiB growth,
1 GiB reserve and 4 MiB output limits. This closes the pending evidence check;
it does not create an image or establish ARM success. Preparation still needs
5 GiB initial free space. Complete original controls remain required.
