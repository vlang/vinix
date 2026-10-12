# Realtek RTL8168G/GU driver tests

```sh
v run tests/rtl8169/run.v
```

The launcher stages the production driver with simulated MMIO, PCI,
DMA and stack boundaries. It executes both revision-specific startup paths
and their bundled firmware. Tests cover descriptor ownership and ring wrap,
CRC removal and invalid RX frames, short TX padding, allocation rollback,
indirect-access/reset/OOB timeouts, resume/reset/removal, delayed carrier,
DHCP discovery on carrier and reconnect/resume, lost TxPoll recovery without
reusing hardware-owned buffers, failed stack
attachment and malformed/unbounded firmware programs. DMA addresses differ
from CPU addresses, and the allocator refuses to free while bus mastering
is enabled; RX/TX enable also requires mastering and programmed DMA addresses.
No physical Realtek adapter or RTL8168 QEMU model is used.

Startup and firmware semantics are adapted from the primary Linux v6.6
sources [r8169_main.c](https://github.com/torvalds/linux/blob/v6.6/drivers/net/ethernet/realtek/r8169_main.c),
[r8169_phy_config.c](https://github.com/torvalds/linux/blob/v6.6/drivers/net/ethernet/realtek/r8169_phy_config.c)
and [r8169_firmware.c](https://github.com/torvalds/linux/blob/v6.6/drivers/net/ethernet/realtek/r8169_firmware.c).
These adaptations retain GPL-2.0-only notices.

The microcode is Realtek's unmodified version 0.0.1, distributed as hex words
under the permission in the linux-firmware WHENCE entry. Its copyright and
distribution notice accompany `kernel/dev/rtl8169/firmware_data.v`.
Source: linux-firmware mirror commit
`711d3297bac870af42088a467459a0634c1970ca`, files
`rtl_nic/rtl8168g-2.fw` and `rtl_nic/rtl8168g-3.fw`.
The generator verifies the file checksum and header, then represents the
instruction words without changing them. Keeping static words in the kernel
makes firmware available before the root filesystem and through resume.

SHA-256 of the complete original files:

```text
f878ec719f78e0b104bc73362a9862611858bec893f58a1b3b289a0a57d71d25  rtl8168g-2.fw
e4d5e62b0a5a097af34c7aa3c55f634fd5be2c232e02c6b983ebd7e699cb27e9  rtl8168g-3.fw
```

Regenerate with downloaded copies of those pinned files:

```sh
v run tests/rtl8169/generate_firmware.v rtl8168g-2.fw rtl8168g-3.fw kernel/dev/rtl8169/firmware_data.v
```
