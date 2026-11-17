# Base-M1 soft-fault initialization

Omarchy's Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf` selects
`fault_control=0xb` for G13 and reports `DRM_ASAHI_FEATURE_SOFT_FAULTS`
when that mode is enabled. Mesa `b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`
uses the bit for shader robustness. With soft faults enabled, shader loads
from unmapped memory return zero and shader stores to it are discarded.
[Linux default](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/asahi_core.rs#L98-L102)
· [Capability selection](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gpu.rs#L303-L348)
· [UAPI semantics](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/include/uapi/drm/asahi_drm.h#L267-L279)
· [Mesa capability check](https://github.com/omacom/mesa/blob/b7b03c5b3b8abe1e040d6056dc62c01b02d3639c/src/asahi/lib/agx_device.h#L418-L424)

Vinix now uses the T8103 configuration for both Globals initialization and
`GET_PARAMS`. The 32-bit word is at `0x10e80` in firmware 12.3 and `0x10fd8`
in 13.5. Both offsets come from the versioned firmware layout. The modern
reply copies bit 0 from the legacy formatter, which derives it from the active
configuration. The tested source is `f5ace8d36` plus this patch.
[Firmware initializer](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/initdata.rs#L780-L790)
· [Versioned Globals layout](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/fw/initdata.rs#L1148-L1159)

The ASan/UBSan regression verified both firmware blobs. Selecting hard faults
changed only the control word, and a control that omitted the new write failed
at the expected assertion. The layout generator reproduced the checked-in
table. Generated AArch64 code showed the configuration reaching the firmware
writer and both capability replies. The ioctl fixture used its injected legacy
formatter to exercise transport and the modern bit mapping. Both kernel builds,
82 V test files and five pinned protocol source gates passed. The allocation
scan reproduced the same 178 existing allowance findings.

This verifies the startup setting and capability reporting on the host.
Physical M1 firmware behavior, the packaged Mesa integration and full driver
parity remain unverified. No boot or GPU access was used.

The tested patch, binaries, logs, pinned source and archive are under
`/Users/alex/.local/state/vinix/omarchy-m1-g13-soft-faults-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `961dcd8897dc87a4a1591bbb7b004802aa9dfa601b7eaca81d1a9d8ae47b4a72` |
| `bundle.tar.gz.inventory.txt` | `e236f1365cd23cfe94216ab96cb4520cd1950d6074863123b06f2e582686bccc` |
