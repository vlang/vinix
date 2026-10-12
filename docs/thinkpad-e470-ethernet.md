# ThinkPad E470 Ethernet

Lenovo's [E470 specifications](https://psrefstuff.lenovo.com/syspool/Sys/PDF/ThinkPad/ThinkPad_E470/ThinkPad_E470_Spec.PDF)
list a Realtek R8111GUS Gigabit Ethernet adapter. Previously the x86 kernel
only registered the Intel e1000 driver, so this Realtek device never attached
to the network stack and `ip link` showed only `lo`. DHCP and Settings
cannot configure an interface that has no driver.

`kernel/dev/rtl8169` now registers PCI `10ec:8168`, verifies the silicon XID
in TxConfig, and drives RTL8168G/8111G (XID 0x4c0) and RTL8168GU/8111GU
(XID 0x509). Other revisions are reported and left unbound. Startup leaves
the firmware's out-of-band receiver, resets the MAC, programs EPHY/PHY
settings, applies bundled Realtek microcode, and starts autonegotiation.
ASPM and EEE are disabled. The polled RX/TX rings use the device's DMA
domain; software checksums and a 1500-byte MTU are used. The stack currently
supports one physical interface. The expected userspace interface is `eth0`.

Boot the new kernel, with the Ethernet cable connected, then run:

```sh
cat /proc/bootlog
ip link
ip addr
```

`/proc/bootlog` retains the latest 256 KiB of kernel console output,
including driver messages, even while the desktop owns the framebuffer.
It is readable without Settings or the session broker. Each open gets a
consistent snapshot; reopening shows newer messages. It is a text snapshot,
not the Linux streaming `/proc/kmsg` interface. To keep a copy:

```sh
cat /proc/bootlog > /tmp/ethernet-boot.log
```

Look for `rtl8169: PCI ...`, its TxConfig/MAC version, station address and
`ready, DHCP requested`. A failed startup names reset, OOB FIFO, EPHY/ERI or
PHY/firmware setup. `link down` can be normal while autonegotiation runs;
later link changes are logged. No `rtl8169:` line means no matching PCI
device was offered, or another physical network interface already owns the
stack. PCI devices and binding status are also available under
`/sys/bus/pci/devices` and `/sys/bus/pci/drivers/rtl8169`.

Validation: the V register fixture exercises both supported revisions and
the actual bundled firmware, RX/TX ring wrap, rejected RX frames, short-frame
padding, distinct CPU/DMA addresses, allocation failure, indirect-access
timeouts, suspend/resume/reset, failed stack attachment and removal. The
bootlog fixture checks wraparound and snapshot ownership. Both kernel
architectures build. QEMU bootlog and e1000 binding tests pass on both
architectures; the x86 Intel IOMMU test passes with real packet exchange.
QEMU does not emulate RTL8168G/GU; the physical E470 remains unverified.

```sh
v run tests/rtl8169/run.v
v run tests/kernel-bootlog/run.v
tests/hardware-platform/run --arch x86_64 --kernel /path/to/vinix --scenario bootlog
```
