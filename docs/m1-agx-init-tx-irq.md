# Base M1 G13 application startup transmit IRQ

The private G13 probe uses the claimed AIC send-empty line through the
firmware endpoint start, doorbell endpoint start, `MSG_INIT`, device-control
doorbell and firmware kick. This order matches the pinned Asahi startup.
The manager restores interrupts during the sends and reacquires its lock
before starting the worker or cleaning up a failure.
[Pinned Asahi GPU startup](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gpu.rs#L1380-L1400)

Each send retains the 500 ms FIFO budget and checks for space before
writing either word. Endpoint start retries an unsent message once. A missing
or masked IRQ uses timed polling. Runtime sends still use timed polling under
the existing teardown synchronization.
[RTKit negotiation transmit](m1-agx-boot-tx-irq.md)

ARM64 and x86-64 kernel builds and all 82 contract test files passed for
`4a85fd5298103cf951314a416021d42aabd15f47` plus the archived patch.
The x86-64 cross-build used `LD_X86_64=ld.lld`. The ASan/UBSan fixture checked
all five messages and failure exits on both G13 firmware ABIs. Five negative
controls caught a wait under the manager lock, a missing lock reacquire,
an IRQ bypass, a wrong doorbell and a skipped endpoint retry. Generated
ARM64 C confirms the lock and publication order without new allocations.
The allocation scan reproduced the 178 baseline allowance findings.

The selected pinned source gates passed. The full audit remains
`not_equivalent`. Physical M1 delivery and timing remain unverified. The
checks ran offline without boots or reboots.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-init-tx-irq-20261118/`.
The archive and restored copy passed full inventory verification.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `7741d9c19997b99f24d83d4450dede993cd950823bdf28e5195feaa181bd7ba4` |
| `bundle.tar.gz.inventory.txt` | `e8692b0678bf21742c6a9c464bc66e76ab74f4bb6f89d75aaf9c280c45dbfbe9` |
