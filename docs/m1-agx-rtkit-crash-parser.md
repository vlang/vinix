# G13 RTKit crash-log decoding

Both G13 ABIs now ignore unknown crash endpoint message types before or
after buffer negotiation. Type 1 still requests a buffer on first receipt and
reports a firmware crash after negotiation. The private snapshot decoder
prints the firmware version, each line of a crash message, crash time,
mailbox history, exception mode and all 31 general-purpose registers.
[Asahi receive handler](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/rtkit.c#L551-L605)
[Asahi decoder](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/rtkit-crashlog.c)

The record size includes the 16-byte section header. Vinix passes only the
remaining payload to each decoder. Mailbox parsing reads complete 24-byte
records after the 28-byte prefix. Text reads stop at the payload boundary,
a NUL, or the 1,024-byte console limit. Vinix retains its 128-section limit
and task ID diagnostic. [m1n1 wire declarations](https://github.com/AsahiLinux/m1n1/blob/b4654b32941d51afdb77579d63e7cb1aa6c03ecc/proxyclient/m1n1/fw/asc/crash.py)

ARM64 and x86-64 kernel builds, all 82 contract test files, five pinned
source gates and independent lifetime review passed for
`86138749a4204b13b0b689d6c034197fefdee760` plus the archived patch. The
sanitizer fixture passed 22 crash paths and four unknown notifications
across both ABIs. It checked multiline and unterminated text, mailbox
padding, undersized records and snapshot cleanup. Three negative controls
detected an unknown message marking the transport failed, an extra mailbox
row crossing into the next section, and a short register dump accepted as
complete. Generated ARM64 C showed no implicit heap allocations in the
decoder. The allocation scan reproduced the 178 baseline discrepancies.

The full audit remains `not_equivalent`. Shared-buffer retry behavior,
inherited-session handling and DMA coherency remain open. No hardware tests
or reboots occurred.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-rtkit-crash-parser-20261118/`.
The archive and restored copy passed complete inventory verification.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `4ae92638c790acc8dddf8f266f65b67d84324b23704b76fad5dd80e43c72a222` |
| `bundle.tar.gz.inventory.txt` | `d74b94662e9a926508214979ec4518de959ad85602a6e2806f4aec7c0138c2f5` |
