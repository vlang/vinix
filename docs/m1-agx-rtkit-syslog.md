# G13 RTKit Syslog and buffer preparation

The pinned Asahi AGX driver uses a write-back CPU view and uncached firmware
UAT mappings. It maps the backing for bidirectional DMA during initial GEM
setup. ARM64 noncoherent DMA setup cleans the backing to the point of
coherency. The Rust RTKit bridge leaves the optional streaming DMA flag
clear for AGX record reads. [Asahi AGX allocation](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gpu.rs#L502-L519)
[GEM DMA setup](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_gem_shmem_helper.c#L1086-L1108)
[ARM64 DMA setup](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/arch/arm64/mm/dma-mapping.c#L15-L21)

Vinix now cleans and invalidates the whole zeroed, 16 KiB-rounded backing
before publishing its RTKit address. Its cached CPU view and uncached
firmware mapping match the selected Asahi attributes. Retries reuse the
prepared buffer. Record reads rely on the existing mailbox barriers.

Syslog now checks the slot against both the latest INIT slot count and the
negotiated buffer length. It copies the context and text into 279 bytes of
stack storage, bounds and trims the strings, and echoes the notification
after the read attempt. Missing and invalid records still reach the echo.
Vinix skips invalid records silently and continues to report a failed ACK
send to its caller. [Asahi Syslog handler](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/rtkit.c#L638-L730)

ARM64 and x86-64 builds, 82 contract test files, five pinned source gates
and independent lifetime review passed for
`0b747aeb9a62202b7011f8d83d491a0f9d3a0e67` plus the archived patch.
The sanitizer fixture passed 20 Syslog cases and reran both-ABI crash and
retry coverage. Three negative controls detected missing initial cache
preparation, an ACK sent before copying, and a slot outside the negotiated
range. The linked ARM64 binary contains the expected cache and barrier
instructions. Generated C confirms stack-only Syslog storage, and the
allocation scan reproduced the 178 baseline discrepancies.

The full audit remains `not_equivalent`. OSLog notification ACKs,
inherited sessions, and physical device coherency remain open. No hardware
tests or reboots occurred.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-rtkit-syslog-20261118/`.
The archive and restored copy passed complete inventory verification.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `314bbe96a45ccf8022430fd68b0538ecf0bb57bd94b50755c3b9aeefb587da1c` |
| `bundle.tar.gz.inventory.txt` | `3ead081ea3a4c8c7f78b8806715bc51977b6e6ac68a3756953251db0870d2e43` |
