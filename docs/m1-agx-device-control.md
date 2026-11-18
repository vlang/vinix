# Base M1 G13 device-control commands

Asahi inserts one device-control variant in firmware 13.3. Vinix sends the
following tags for its two G13 firmware ABIs. Both commands retain the
0x30-byte entry size. [Asahi device-control enum](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/fw/channels.rs#L162-L195)

| Command | 12.3 | 13.5 |
| --- | --- | --- |
| GrowTVBAck | `0x0d` | `0x0e` |
| RecoverChannel | `0x0e` | `0x0f` |

GrowTVBAck copies all 64 bits of the firmware halt counter into the
acknowledgement. The status field remains at offset `0x10`, and the wire
field remains at `0x18`.
[Firmware status layout](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/fw/initdata.rs#L38-L60)

The worker publishes the ACK and releases the device-control ring lock
before ringing the doorbell. Missing owners and ordinary allocation
failures still get an ACK. Fatal growth failures stop publication. During
an IRQ wait, shutdown can stop the ASC and reclaim the ring. Before
retrying, the sender checks GPU state and the FIFO deadline under the
manager lock. This revision used polling for RecoverChannel and FwCtl.
[Asahi acknowledgement order](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gpu.rs#L1729-L1758)
[RecoverChannel follow-up](m1-agx-recover-channel.md)

ARM64 and x86-64 builds and all 82 contract test files passed for
`aab62891a6ca4af6f902fc255a31ca6877ef9263` plus the archived patch.
ASan/UBSan covered both command payloads on both G13 ABIs, including a
nonzero high half of the halt count, ring and FIFO failure, and shutdown
during the wait. Four negative controls caught a legacy tag, a truncated
counter, loss of stopped state and a bypassed IRQ wait. The UAT flush,
TVB growth and job lifetime suites also passed.

Generated ARM64 C confirms the 64-bit load and ring publication before
the wait. Independent lifetime review found no blocker. The allocation
scan reproduced 178 baseline findings. The pinned source gates passed
and the full audit remains `not_equivalent`. No hardware tests, boots
or reboots ran.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-device-control-irq-20261118/`.
The archive and restored copy passed full inventory verification.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `8386b78d101c4d93bcd73f53ec9c39f700f0f398af72ae5c65c16fd980870451` |
| `bundle.tar.gz.inventory.txt` | `819ef275e5cdd1cdcf486b0c41574d34f0f649b5cceccae28abda37120028e35` |

## Synchronous growth at the block limit

Firmware `GrowTVB` requests a ten-block extension. If fewer than ten blocks
fit, Vinix leaves the allocation alone and still sends `GrowTVBAck`. With
exactly ten blocks available, a successful extension fills the buffer to its
limit.
[Pinned growth and capacity check](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/buffer.rs#L474-L498)
[Pinned acknowledgement dispatch](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/channel.rs#L399-L408)

The previous handler attempted a partial extension with nine blocks available.
The ASan/UBSan fixture reproduces that failure and checks three capacity
boundaries on both firmware ABIs. The fixture also models the current shutdown
interfaces so it can exercise the production handler. The TVB growth suite,
79 source-contract test files and both kernel builds passed. The allocation
scan matched the 176 baseline findings. M1 hardware validation remains open.

The evidence archive covers `82be046b2c9c1b485884f1abf75c7d01d92d3291` plus
`source.diff`. The original and restored copies passed verification. The
archive is at `/Users/alex/.local/state/vinix/omarchy-m1-grow-tvb-limit-20261119.K6LgXP/bundle.tar.gz`
with SHA-256 `bac9b726bf264fd7e03bcef0d3a352c9d6d86bb7e16b233ce741f405c6256b6d`.
