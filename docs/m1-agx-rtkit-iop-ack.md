# G13 RTKit IOP acknowledgement and application power

On both G13 firmware ABIs, receiving an IOP acknowledgement completes the
IOP wait regardless of the state it reports. Endpoint discovery and IOP
acknowledgement both precede the AP ON request, which still requires a fresh,
exact acknowledgement. The legacy wake path continues to require IOP ON
before sending AP ON. [Asahi IOP ACK handler](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/rtkit.c#L277-L288)
[Asahi boot](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/rtkit.c#L1348-L1390)

Application endpoint starts and sends check whether the latest IOP and AP
power words both have low byte `0x20`. The receiver publishes one atomic
readiness value as the power words change and clears it on a crash before
parsing the crash log. A later acknowledgement cannot restore application
access to a crashed transport. [Asahi running predicate](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/rtkit.c#L114-L124)
[Asahi application send](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/rtkit.c#L945-L975)
[Asahi endpoint start](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/rtkit.c#L1009-L1031)

Both native kernel builds and 82 contract test files passed for
`e1470cf9c3edfee11cfefe2cef807654b02013ad` plus the archived patch. The
sanitizer fixture passed 16 G13 transcripts across four IOP state words,
two acknowledgement placements and both ABIs, plus a legacy IOP OFF case.
It checked the AP request, application mailbox words, runtime transitions
and crash rejection. Five negative controls caught an IOP ON requirement
during boot, missing start and send gates, stale IOP state and continued
application access after a crash. Generated ARM64 C confirms allocation-free
release and acquire operations. The allocation scan reproduced 178 baseline
allowance findings.

The pinned IOP source gate passed. The full audit remains `not_equivalent`.
Vinix polls for RTKit messages during boot. Timing on the physical mailbox
and firmware remains unverified. No hardware tests or reboots occurred.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-rtkit-iop-20261118/`.
The archive and restored copy passed full inventory verification.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `0d4d8ce66ba826c6b5763d867d02222c182e03cf1a94119d4dcb0759d4b39da1` |
| `bundle.tar.gz.inventory.txt` | `1e910b95f5c4be5b6bd8d841b06143bd1656ae5ddb52de48bd197e4399c7f2b0` |
