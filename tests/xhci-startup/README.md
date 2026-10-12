# xHCI firmware handoff and root-port power

Run the production startup code against fake controller registers:

```sh
v run tests/xhci-startup/run.v
```

The V launcher copies `kernel/dev/xhci/startup.v` into a temporary module with
the fixture and runs its tests. No kernel dependencies or QEMU are needed.
The fixture covers ports left unpowered by firmware or reset, connection
appearing only after power is enabled, preserving enabled ports and pending
write-one-to-clear status, controllers without switchable power, delayed and
stuck firmware ownership, and capability links outside the mapped registers.

QEMU input and suspend regression checks use the hardware-platform suite:

```sh
tests/hardware-platform/run --arch x86_64 --kernel /path/to/vinix \
  --scenario usb-input --scenario suspend-deep
tests/hardware-platform/run --arch aarch64 --kernel /path/to/vinix \
  --scenario usb-input
```

QEMU leaves its root ports powered and does not reproduce a ThinkPad's
firmware handoff. Passing these tests does not establish that input works on
a particular physical laptop. On that machine, the boot log's `xhci:` lines
show controller discovery, ownership timeouts, powered/connected ports,
enumeration failures and the number of input interfaces. The same startup
path runs after a suspend that cuts controller power.

The driver supports HID keyboards and pointers attached directly to root
ports at startup. USB hubs and hotplug remain unsupported; for a hardware
retest, attach the keyboard and mouse directly before booting.
