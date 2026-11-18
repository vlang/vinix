# G13 ASC mailbox transmit timing

Both G13 firmware ABIs use a per-send 500 ms budget when the ASC transmit
FIFO is full. Vinix checks for immediate space first, then polls the FIFO
every 100 μs using the ARM generic counter. The mailbox lock covers each
status read and complete write. It is released during the wait between
polls. The shared-memory barrier precedes the low and high writes, and a
timed-out attempt publishes neither word. An endpoint-start retry gets its
own budget. [Asahi transmit budget](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/mailbox.c#L114)
[Asahi polling and IRQ waits](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/mailbox.c#L269-L348)

The timed path serves firmware-led G13 management, system and application
traffic. SMC, DCP and the legacy wake clients use the iteration-based send.
Asahi can wait on the T8103 mailbox's send-empty interrupt. Vinix uses
Asahi's polling interval and timeout budget with its monotonic counter.
[T8103 GPU mailbox node](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/arch/arm64/boot/dts/apple/t8103.dtsi#L541-L552)

ARM64 and x86-64 builds and 82 contract test files passed for
`19a531e2d73f517af3c92ca0065d0954d36be1c6` plus the archived patch.
The sanitizer fixture exercised the production mailbox transmit code for
seven FIFO boundary cases, a fresh retry and a legacy timeout. It checked
barriers, the exact register writes, lock ownership and wait duration.
Five negative controls caught a shorter timeout, a wait under the mailbox
lock, swapped words, a missing barrier and dispatch to the legacy send.
Generated ARM64 C confirms ordered, allocation-free transmit. The allocation
scan reproduced the 178 baseline allowance findings.

The pinned source gate passed. The full audit remains `not_equivalent`.
Physical mailbox timing and IRQ-driven wakeups remain unverified. No hardware
tests or reboots occurred.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-rtkit-tx-20261118/`.
The archive and restored copy passed full inventory verification.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `0f96f8e0ed899262d19d6ca1ea1da985877691ae118cc6f1312a6e1e5cc130e5` |
| `bundle.tar.gz.inventory.txt` | `1a392955d9de3d5c2206d6679bb299c9e40f45da5ed4e27081ff970caea4bc49` |
