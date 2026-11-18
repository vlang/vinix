# G13 RTKit management send failures

Both G13 firmware ABIs log a HELLO or endpoint-map reply timeout and keep
receiving boot messages. A final endpoint-map message still starts the
advertised system endpoints, including when its reply times out.
[Asahi discovery handlers](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/rtkit.c#L137-L272)

G13 retries a system or application endpoint start once when the mailbox
reports it could write neither message word. A second timeout propagates the
start failure. An AP ON send timeout still aborts boot. Legacy wake clients
retain their existing failure handling.
[Asahi endpoint start](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/rtkit.c#L1009-L1031)
[Asahi AP power transition](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/rtkit.c#L1302-L1323)

ARM64 and x86-64 builds and 82 contract test files passed for
`b64610bae2ee4626f10433a54e076b849de33d48` plus the archived patch. The
sanitizer fixture checked the attempted and delivered mailbox words for 16
G13 and three legacy timeout transcripts. Four negative controls caught
fatal discovery replies, a missing endpoint retry and a nonfatal AP send.
The generated ARM64 C confirms that the mailbox timeout path publishes no
message and the new helpers allocate nothing. The allocation scan reproduced
the prior 178 allowance findings.

The pinned RTKit management send gate passed. The full source audit remains
`not_equivalent`. Vinix checks the IOP ON low byte at boot. Asahi waits for
IOP ACK completion there and checks the low byte when starting application
endpoints. Physical mailbox and firmware timing remain unverified. No
hardware tests or reboots occurred.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-rtkit-management-20261118/`.
The archive and restored copy passed full inventory verification.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `76d32801f19255a7419c21f9863b4e42976a6e88d53c598956a03d1eb9ca1a25` |
| `bundle.tar.gz.inventory.txt` | `ba946e5ffaccc2613ec6797899d600e8fbf89f8495483eecbe2963bb86cbdd94` |
