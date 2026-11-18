# Base M1 G13 RTKit boot send-empty IRQ

During private RTKit negotiation on the base M1, Vinix uses the named AICv1
`send-empty` interrupt to recheck a full transmit FIFO before the next 100 μs
poll. Both the GPU manager and RTKit locks are released during this wait. The
mailbox lock covers each FIFO status check and the two ordered word writes.
The AIC handler latches the notification, and the sender rechecks FIFO space
before publishing either word. A stale notification prompts a rearm within
the same 500 ms budget. The transmit line is masked when the wait ends.
[Pinned M1 mailbox binding](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/arch/arm64/boot/dts/apple/t8103.dtsi#L541-L552)
[Pinned Asahi transmit path](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/mailbox.c#L269-L369)

Vinix uses timed polling for IRQ-masked callers, missing or invalid interrupt
bindings, and sends after negotiation. A missed IRQ still permits polling
within the same budget. An unsent endpoint-start message still gets one retry.
[RTKit management send failures](m1-agx-rtkit-management-send.md)

ARM64 and x86-64 builds and all 82 contract test files passed for
`b0a1ae17ef44e2c47625e08d8b928511ab03177c` plus the archived patch.
The ASan/UBSan fixture exercised early, stale and missing interrupts, a full
FIFO timeout, masked callers, and boot dispatch for both G13 firmware ABIs.
Five negative controls caught a missing mask, arming with IRQs disabled,
aborting on a stale IRQ, skipping the arm, and skipping boot TX dispatch.
The generated ARM64 C confirms the lock boundaries, write order and
allocation-free wait. Independent lifetime review found no blocker. The
allocation scan reproduced the 178 baseline allowance findings.

The selected source gates passed. The full audit remains `not_equivalent`.
Asahi uses an interruptible completion wait for eligible runtime sends.
Physical M1 IRQ delivery and timing remain unverified. This work used host
fixtures and cross-builds and did not boot or reboot a machine.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-boot-tx-irq-20261118/`.
The archive and restored copy passed full inventory verification.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `53b54ddec23f9b81d49c5fc75060cdab72a3da07964c4d60c071f75bc31a6bb6` |
| `bundle.tar.gz.inventory.txt` | `eb2bcd702b648511f2615d29c14f45bde806695c0a871adc3b3c6b6849b5ea47` |
