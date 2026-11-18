# G13 RTKit boot handshake

Both G13 firmware ABIs now wait for firmware-led RTKit startup after
releasing the ASC CPU. The existing wake handshake remains available to
the other RTKit clients. [Asahi ASC startup](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/driver.rs#L264-L286)
[Asahi G13 RTKit startup](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gpu.rs#L1379-L1395)

G13 echoes the decoded three-bit endpoint-map base with the existing
MORE or LAST flag. It starts all advertised known system endpoints,
including TraceKit. After endpoint discovery and IOP ON, it clears AP
state observed before the request and requires a full `0x0020` AP
acknowledgement. [Asahi endpoint map](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/rtkit.c#L191-L272)
[Asahi AP power transition](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/rtkit.c#L1302-L1323)

The endpoint discovery, IOP and AP waits use separate one-second budgets.
Vinix polls the mailbox against its ARM64 monotonic counter while the
boot locks mask interrupts. [Asahi completion waits](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/rtkit.c#L1235-L1246)
[Asahi boot sequence](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/rtkit.c#L1348-L1390)

ARM64 and x86-64 builds, 82 contract test files and five pinned source
gates passed for `274ce95125175650d71a00004e79316f726fa3e2` plus the
archived patch. The sanitizer fixture passed 14 G13 transcripts and one
legacy wake transcript. The delayed case took more than 1.8 seconds
across all three phases. Six negative controls caught an extra IOP wake,
an overwide map reply, omitted TraceKit startup, reuse of stale AP state,
acceptance of a partial AP state and loss of the AP deadline reset.
Generated ARM64 C confirms the G13 dispatch and allocation-free polling.
The allocation scan reproduced the 178 baseline discrepancies.

The full source audit remains `not_equivalent`. Management reply send
failure handling and physical firmware timing remain open. No hardware
tests or reboots occurred.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-rtkit-boot-20261118/`.
The archive and restored copy passed complete inventory verification.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `6762df067057eb4ab999dbb8ffa69851384eb71df25cdb4bb8692e55b44034bc` |
| `bundle.tar.gz.inventory.txt` | `a6f3e0ecb9d75f6e7f11f51d0c9f0efdcc5a75c909fca955b182b3d671e62667` |
