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
DHCP waits for physical carrier rather than starting during autonegotiation.
Carrier appearing starts discovery immediately or revalidates an existing
lease. Disconnect/resume events reach lwIP, and `ip link` reports actual carrier.

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
`DHCP requested`, or `waiting for carrier before DHCP`. A failed startup names
reset, OOB FIFO, EPHY/ERI or PHY/firmware setup. `link down` can be normal while
autonegotiation runs;
later link changes are logged. No `rtl8169:` line means no matching PCI
device was offered, or another physical network interface already owns the
stack. PCI devices and binding status are also available under
`/sys/bus/pci/devices` and `/sys/bus/pci/drivers/rtl8169`.

Until a lease is installed, every five seconds an `awaiting DHCP` line reports
PHY/command registers, interrupt errors, TX queued/completed/pending counts
and RX accepted/dropped counts. A link that stays down indicates carrier or
PHY negotiation trouble. Pending TX descriptors that never complete point
to the controller/DMA path; completed TX with no RX means replies are not
reaching the receive path. The counters narrow the failure; they do not by
themselves prove what packets reached the cable or DHCP server.

Validation: the V register fixture exercises both supported revisions and
the actual bundled firmware, RX/TX ring wrap, rejected RX frames, short-frame
padding, distinct CPU/DMA addresses, allocation failure, indirect-access
timeouts, suspend/resume/reset, failed stack attachment and removal. It also
checks delayed carrier, immediate DHCP output on carrier, reconnect/resume,
bus mastering before RX/TX enable and retained C+ normal-mode bits. The
bootlog fixture checks wraparound and snapshot ownership. Both kernel
architectures build. QEMU bootlog and e1000 binding tests pass on both
architectures; the x86 Intel IOMMU test passes with real packet exchange.
An opt-in kernel selftest drives the production attachment/link API and the
real lwIP DHCP state machine; the `net-carrier` QEMU scenario verifies it and
then obtains a real lease and exchanges a TFTP packet through e1000. QEMU
does not emulate RTL8168G/GU. Adapter discovery has been reported working on
an E470; the DHCP changes still require a physical retest.

```sh
v run tests/rtl8169/run.v
v run tests/kernel-bootlog/run.v
tests/hardware-platform/run --arch x86_64 --kernel /path/to/vinix --scenario bootlog
```

For `--scenario net-carrier`, build a separate test kernel with
`VFLAGS='-exclude @vlib/builtin/float.c.v -d net_carrier_selftest'`.
