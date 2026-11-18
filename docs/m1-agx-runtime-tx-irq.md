# Base M1 G13 runtime RTKit transmit IRQ

The base M1 GPU worker can use the send-empty interrupt for RTKit buffer
replies and IOReport, Syslog and OSLog acknowledgements. It holds the
manager lock while allocating or reading shared buffers and while testing
and writing the transmit FIFO. Only the bounded IRQ wait releases the lock.
This follows the pinned Asahi path that waits for send-empty and checks
removal before retrying the FIFO.
[Asahi mailbox transmit](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/mailbox.c#L269-L349)

The worker reacquires the manager lock and checks GPU state and the 500 ms
deadline before another FIFO attempt. Shutdown masks both mailbox lines
before stopping the ASC and releasing RTKit backing. If shutdown happens
during the wait, the worker abandons the scalar reply without another TX
FIFO read or write. IRQ-masked callers and machines without the IRQ use
timed polling. Runtime job doorbells, firmware-control sends and the shutdown
message still use timed polling.

ARM64 and x86-64 kernel builds and all 82 contract test files passed for
`2eac72f68706a76a4345a3e40ba29d0bded65d77` plus the archived patch.
The sanitizer fixture exercised both G13 firmware ABIs with early and stale
IRQs, IRQ-masked polling, shutdown while a buffer reply was waiting, and
lock reacquisition at and after the deadline. Five negative controls
caught regressions in shutdown, deadline and IRQ handling. Generated ARM64
C confirms the guard, FIFO and shutdown ordering without new allocations
in the wait. The allocation scan reproduced the 178 baseline allowance
findings.

The pinned source gates passed and the full audit remains `not_equivalent`.
Interrupt delivery, timing and shutdown on the physical M1 remain unverified.
All checks ran offline without boots or reboots.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-runtime-tx-irq-20261118/`.
The archive and restored copy passed full inventory verification.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `e79c1f7d92734d4ff629ed5449534514715be6e2b5a970d8c4deab706e73c03c` |
| `bundle.tar.gz.inventory.txt` | `7967d5524d933fec9392b2a1d75951e4db82559d1b71c625385e937534a75d65` |
