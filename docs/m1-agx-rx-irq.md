# Base M1 G13 mailbox receive IRQ

After successful GPU boot, Vinix enables the mailbox's named
`recv-not-empty` interrupt when the base M1 FDT supplies a matching
level-high AICv1 binding. The binding in pinned Asahi names IRQ 578.
Vinix decodes the IRQ from the device tree and routes it to CPU 0.
Platforms without that binding use the polling path.
[Asahi M1 mailbox binding](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/arch/arm64/boot/dts/apple/t8103.dtsi#L541-L552)
[Asahi AICv1 target setup](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/irqchip/irq-apple-aic.c#L1193-L1203)

The AIC interrupt acknowledgement masks the receive line. Vinix records
the pending notification and lets the existing worker drain the FIFO.
The worker re-arms under the manager lock and checks the FIFO after 1 ms
if a notification is delayed or lost. Ring polling and file retirement
continue on worker passes. Shutdown masks the line before stopping the
ASC. The controller retains the line's reservation so a late interrupt
cannot auto-rearm it. [Asahi AIC acknowledgement](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/irqchip/irq-apple-aic.c#L439-L452)
[Asahi mailbox receive handler](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/mailbox.c#L369-L415)

ARM64 and x86-64 builds and 82 contract test files passed for
`996825ca72f50ad272777a73f82a8336ac3d9e7d` plus the archived patch.
The sanitizer fixture exercised the production AIC dispatcher and worker
against simulated registers. It checked binding validation, CPU targeting,
deferred delivery, timed fallback, shutdown with a late IRQ, and ordinary
IRQ rearm. Five negative controls each failed at the expected assertion.
Generated ARM64 C confirms allocation-free dispatch and worker rearm.
The allocation scan reproduced the 178 baseline findings.

The pinned receive IRQ source gate passed. The full audit remains
`not_equivalent`. IRQ delivery on the physical M1 remains unverified,
and boot and transmit still use polling. No hardware tests or reboots
occurred.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-rx-irq-20261118/`.
The archive and restored copy passed full inventory verification.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `68c7b88c31977009ebec62b039dc61963b5f1d3bca6820558639a7fabed17cf3` |
| `bundle.tar.gz.inventory.txt` | `c9d7746236dc4da00f8a06464cc2cb9274080a0b7aa0f09942c9e8cbe0a0fc2c` |
