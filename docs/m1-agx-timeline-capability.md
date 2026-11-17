# Base-M1 DRM timeline capability

GET_CAP returns `1` for `DRM_CAP_SYNCOBJ_TIMELINE` on the native t8103
device. The feature is set on the driver registration after firmware
initialization. The primary and render nodes use the registered device's
feature word. Devices without the feature bit report `0`. The binary
syncobj capability is available on all existing DRM devices.

Omarchy's Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf` advertises
the feature on Asahi and reads it from the device in GET_CAP. Its Mesa pin
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` uses the probe result to install
its timeline wait and signal functions. This comparison uses Vinix
`648ecff17` plus the capability patch.
[Linux GET_CAP](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_ioctl.c#L248-L254)
· [Asahi features](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/driver.rs#L119-L120)
· [Mesa timeline probe](https://github.com/omacom/mesa/blob/b7b03c5b3b8abe1e040d6056dc62c01b02d3639c/src/util/u_sync_provider.c#L141-L146)

The wire fixture exercised the 16-byte `0xc010640c` GET_CAP request through
the node copy path with a timeline-enabled device and two configurations
without the bit. It also checked binary discovery and ran with heap buffer
allocations forced to fail. The old constant-zero handler failed the same
probe on the timeline-enabled device. The ASan/UBSan DRM fixture, 82 V test
files, five pinned source gates and both kernel builds passed. The allocation
scan reported the same 178 existing allowance findings, with 377 AArch64 and
289 x86_64 sites.

The Mesa probe was verified against its pinned source. The package's Asahi
header and Linux's header differ in parts of the command ABI, including
extended render records. The retained comparison gives those differences
for matched Mesa qualification. Published fence reclamation, full scheduler
qualification and testing the packaged Mesa build on M1 remain open. All
validation in this increment ran on the host.

The source patch, build artifacts, reference snapshots and restored evidence
are under `/Users/alex/.local/state/vinix/omarchy-m1-timeline-cap-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `938b8cb09e36e45e1341602c4b8859ec3371f33784b2e99a1426b96d89115ed6` |
| `bundle.tar.gz.inventory.txt` | `982cad156eb526b02791d3247cfbbf4e4d262a96024e2e971e6c87e95761a7a0` |
