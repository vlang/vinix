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
manager lock. RecoverChannel and FwCtl still poll while waiting for their
ring tokens. [Asahi acknowledgement order](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gpu.rs#L1729-L1758)

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
