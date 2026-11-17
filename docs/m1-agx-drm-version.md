# Base-M1 DRM version reporting

The native T8103 driver reports `asahi` version `0.0.0`, date `0` and
description `Apple AGX Graphics`, matching the normal VERSION reply from
Omarchy's Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf`. The old
`1.0.0` reply made Mesa set `render_rsrc_spec_hi` during device open. The
packaged Mesa pin `b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` sets the flag
for a positive major or a minor of at least two. This change targets T8103.
[Asahi driver identity](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/driver.rs#L92-L99)
· [Linux VERSION reply](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_ioctl.c#L540-L559)
· [Mesa capability selection](https://github.com/omacom/mesa/blob/b7b03c5b3b8abe1e040d6056dc62c01b02d3639c/src/asahi/lib/agx_device.c#L887-L897)

The group-zero `GET_PARAMS` source comparison also found the same VM window
(`0x4000` through exclusive end `0x7fffff8000`), 512 MiB minimum kernel window,
64-command and 16-attachment limits, nanosecond timestamp units, and shader
ISA generation 2 with legacy HAL. Both drivers report fused topology and the
final performance state's frequency. The memory limit fields are zero on base
M1. Linux configures the ledger limits in its G17 probe.
[Global parameters](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs#L420-L442)
· [G13 hardware parameters](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gpu.rs#L1410-L1428)
· [Memory limit setup](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/driver.rs#L414-L419)

The ASan/UBSan fixture reproduced libdrm's length and data calls through the
production node transport and VERSION handler with the native registration
metadata. It checked T8103, G17, short buffers and Mesa's version predicate.
Reinstating the old major failed the T8103 check. Both kernel builds, 82 V
test files, AGX ioctl regressions and five pinned source gates passed for
Vinix `b327e507e` plus this patch. The allocation scan reproduced its 178
existing allowance findings.

The normal VERSION reply and selected `GET_PARAMS` fields were checked on the
host. Running the packaged Mesa build through device open and submission on a
physical M1 remains unverified. The source audit still reports incomplete
driver parity. No hardware tests or reboots were performed.

The tested patch, reference sources, native binaries and logs are under
`/Users/alex/.local/state/vinix/omarchy-m1-drm-version-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `4c90e48e422914df7c6c6b490fa2ab54b60e4c3563e5cd27e731d610cb72d1ac` |
| `bundle.tar.gz.inventory.txt` | `564520c34d4939135ecb7d809989b9a829577083c97f842abc4a24fc6ece5dfe` |
