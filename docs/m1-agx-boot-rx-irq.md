# Base M1 G13 RTKit boot receive IRQ

With a valid base M1 AICv1 mailbox binding, Vinix claims the receive
line before the RTKit handshake. The probe owns the GPU manager until
initialization completes. When an empty FIFO needs another receive
notification, the probe waits with both the manager and RTKit locks
released. It rechecks the FIFO after 100 μs if the notification has
yet to arrive. The existing one-second phase budgets and polling path
for machines without a claimed line are preserved.
[Asahi mailbox startup](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/rtkit.c#L1159-L1172)
[Asahi RTKit boot](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/rtkit.c#L1348-L1390)

The AIC handler records a pending flag. The probe reads the FIFO,
and the existing worker inherits the same line after boot. Failed
initialization masks the line before stopping the ASC and releasing
backing. Independent review found no blocker in the lock release,
ownership, or failure sequence. [Runtime receive IRQ](m1-agx-rx-irq.md)

ARM64 and x86-64 builds and 82 contract test files passed for
`a582a0abf637c873e8f9076d536541221e21d7a1` plus the archived patch.
The sanitizer fixture exercised IRQ delivery and polling fallback
on both G13 firmware ABIs, and verified the silent-firmware timeout
and cleanup. Five negative controls caught waits under either lock,
a missed rearm, a late fallback and unmasked failure cleanup.
Generated ARM64 C confirms allocation-free waits and failure masking
before ASC stop. The allocation scan reproduced 178 baseline findings.

The pinned boot receive source gate passed. The full audit remains
`not_equivalent`. Transmit still uses polling. IRQ delivery during
boot on the physical M1 remains unverified. No hardware tests or
reboots occurred.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-boot-rx-irq-20261118/`.
The archive and restored copy passed full inventory verification.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `555456df8a7e9aa93b25653b0a3dcf407bfd85bc461c698d6706277c830db352` |
| `bundle.tar.gz.inventory.txt` | `cf9afaa8b8c5becf05141d55da6e01995d39bc18592e761d0700157e6afdab05` |
