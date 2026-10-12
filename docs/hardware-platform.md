# Hardware platform and power management

This is the record for roadmap workstream 4: what the kernel now does to find
devices, bind and recover drivers, isolate DMA, load firmware, manage power
and sleep, and what it does not do yet.

Everything described here was built for both architectures -- suspend to RAM
and suspend to disk for x86-64 only -- and exercised in QEMU guests (x86-64
under TCG, AArch64 under HVF). **None of it has run on a physical machine.** The
hardware-specific paths that no emulator has -- the Intel, AMD and Apple
frequency registers, processor temperature sensors, MWAIT idle states -- are
covered by host unit tests of their arithmetic and are otherwise unverified.
The embedded controller driver has run only against a simulated controller:
its protocol on the host, and the whole of it but the two port instructions
in a guest. Which machine is
qualified for what is kept in [the qualification matrix](hardware-qualification.md);
this document does not qualify anything.

## Devices and drivers

`kernel/devcore` keeps the machine's devices and drivers. A bus adds what is
on it, a driver registers what it drives, and the core brings the two
together. A driver is a table of functions, all optional but `probe`:
`matches`, `probe`, `remove`, `suspend`, `resume`, `shutdown`, `reset`.

Order is registration order: a bus adds a device after the device it hangs
off, and drivers register in the order they used to be started. Suspend and
shutdown walk the devices last to first, resume first to last.

`/sys` shows it in Linux's layout:

```
/sys/devices/pci0000:00/0000:00:03.0/   vendor device class revision config modalias uevent
                                        driver -> ../../../bus/pci/drivers/e1000
                                        state health dma        (Vinix's)
                                        reset remove            (write 1)
                                        power/wakeup power/wakeup_count power/runtime_status
/sys/bus/pci/devices/0000:00:03.0 ->    the same directory
/sys/bus/pci/drivers/e1000/             bind unbind, and a link per bound device
/sys/bus/platform/...  /sys/bus/acpi/...
```

`/sys` itself gained the calls this needs (`kernel/fs/sysfs_dynamic.v`):
another module can publish a file whose text it makes when read and takes
when written, a directory or a link, and remove it again. Removal waits for
calls into the owner to return, so the owner may then free what the file
pointed at.

| Driver | Bus | Binds through the core | remove | suspend / resume | shutdown | reset | DMA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `e1000` | PCI | yes | yes | yes | yes | yes | per-device domain |
| `rtl8169` (x86 G/GU) | PCI | yes | yes | yes | yes | yes | per-device domain |
| `ahci` | PCI | yes | no (mounted disks) | yes | flush, STANDBY IMMEDIATE, stop | port COMRESET | per-device domain |
| `nvme` | PCI | yes | no | yes: flush and shutdown notification, set up again from nothing | shutdown notification | no | all of memory |
| `ata` | PCI | yes | no | yes: requests held, drives waited for | no | no | all of memory |
| `hda` | PCI | yes | no | yes: streams, rings and codec paths programmed again | streams stopped, controller in reset | no | all of memory |
| `xhci` | PCI | yes | no | yes: left running for a suspend to idle, set up again from nothing after a loss of power | no | no | all of memory |
| `virtio_*` (AArch64 MMIO) | platform | listed from the device's own status | no | no | no | no | not behind an IOMMU |
| `battery`, `ac`, `button` | ACPI | listed as claimed | no | -- | -- | -- | -- |
| `ec` | ACPI | listed as claimed | no | holds its events back when it may not wake | stops taking events | asks a failed controller one question | -- |
| `i8042`, `psmouse`, `serial8250` (x86-64) | platform | listed as claimed | no | set up again after a loss of power | -- | -- | -- |

A driver without `remove` cannot be unbound and `/sys` has no `unbind` file
for it. Apple's platform drivers (SMC, ANS, DART, DCP, AGX, Wi-Fi, speakers,
SPI keyboard, Type-C) still start the way they did and are **not listed** on
the platform bus.

### USB keyboards and pointers

There is no USB core. There is one driver, `kernel/dev/xhci`, that does as
much of xHCI as a keyboard and a pointer take: one controller, one
interrupter, polled, the boot protocol for keyboards and the report
descriptor for pointers. It began as AArch64's, for VirtualBox, and is now
x86-64's as well, with a half for each (`xhci_arm64.v`, `xhci_amd64.v`): on
x86-64 a key is given to the console as the scancode the same key has on a
PS/2 keyboard, a pointer moves `/dev/pointer`, and a thread polls every
8 ms. A PC with no PS/2 port has a keyboard; and a PC with no keyboard
controller at all no longer has a thread waiting on one for ever.

Through a sleep the controller is left in D0 and goes on being asked, so
that a key ends a suspend to idle; after a sleep that cut its power it is
found halted and set up again from nothing, its pages given back.
`/sys/bus/usb/xhci` counts what it has and what it has said.
`vinix.usb=off` leaves the controller to firmware.

Startup requests firmware ownership before resetting the controller, forces
the BIOS semaphore clear after a one-second handoff timeout, and disables
legacy SMIs. Controllers with per-port power switching have every root port
powered before connection debounce and enumeration. The boot log reports
powered and connected port counts, so an unpowered port can be distinguished
from a device that failed enumeration. The register fixture in
[`tests/xhci-startup`](../tests/xhci-startup/README.md) covers power-off startup
and stuck firmware, which QEMU's USB input scenario does not reproduce.

What it does not do, each of which a real machine will meet:

- **Hubs.** A keyboard behind a hub -- a dock, a monitor, the front panel of
  many desktops, the internal hub of some laptops -- is not seen.
- **Hotplug.** What is plugged into a root port when the controller is
  started is what there is, until the next start or the next suspend to RAM.
- **Firmware's own keyboard.** Taking the controller from firmware (the
  legacy-support handoff) ends firmware's emulation of a PS/2 keyboard for
  USB ones. A keyboard that worked through that emulation and sits behind a
  hub stops working; `vinix.usb=off` gives it back.
- A second controller, interrupts instead of polling, anything that is not a
  keyboard or a pointer, and isolation behind an IOMMU (the controller is
  allowed all of memory).

Tested with QEMU's `qemu-xhci`, `usb-kbd` and `usb-mouse` only
(`usb-input`, both architectures, with no other keyboard in the machine).
No physical controller has been tried on x86-64.

### Waiting and recovery

Waits on hardware are bounded by the clock (`devcore.spin_until`,
`sleep_until`, `deadline`), not by counts of register reads. Two waits that
had no end have one: the IDE identify loop compared against a counter it never
incremented, and the HD Audio command wait had no limit. The wait for
firmware to hand an AHCI controller over is bounded too.

A driver that sees a timeout or a fatal error reports it
(`devcore.report_timeout`, `report_failure`) and fails the request. A worker
thread then tries, in order: the driver's `reset`; unbinding and probing
again; marking the device failed. A device is reset at most three times a
minute. A failed device stays listed with its history in `health` and can be
reset or bound again by hand, so one broken device costs the machine that
device and not the boot.

### PCI hotplug and rescan

A PCI device can arrive and leave while the machine runs
(`kernel/devcore/hotplug.v`, `kernel/pci/hotadd.v`, `kernel/pci/window.v`).
One thread makes every change to which PCI functions exist, whatever asked
for it:

- **A port the kernel runs.** A PCI Express root or downstream port with a
  hot-plug slot is looked at twice a second, as Linux's `pciehp` does in its
  polling mode. A card that appears is given power, its link is waited for,
  its functions are found, given addresses and handed to the device core,
  whose drivers bind as at boot. The slot's button starts five seconds in
  which a second press calls it off; then the drivers let go, the functions
  are removed and the slot's power is cut. A card pulled without asking is
  removed the same way, with its registers already reading all ones.
- **A port firmware keeps (x86-64, `kernel/x86/acpihp`).** Each PCI host
  bridge is asked through `_OSC` to hand over its ports. Where firmware keeps
  them, it announces a device through a `Notify` on the device's namespace
  node -- look here (1), wanted back (3), look behind this bridge (0). The
  node's place on the buses is worked out from the `_ADR` of each node up to
  the host bridge; the device is found or let go of as above, and `_EJ0` then
  tells firmware it can leave. Such a machine's slot registers are not
  touched. A machine with no `_OSC` is taken to have handed its ports over,
  as Linux takes it.
- **A rescan.** Writing 1 to `/sys/bus/pci/rescan` tries every address on
  every known bus; a function nobody has is treated as an arrival. This is
  how a device removed through its own `remove` file comes back.

A function that arrives has nothing in its base address registers. Each is
sized, and the sizes are placed, largest first, in the windows firmware left
on the port: prefetchable 64-bit registers in the prefetchable window, the
rest in the 32-bit one, after whatever functions already there occupy. A
register that does not fit is left unset and said so; the driver finds out.
A function found again with its addresses still inside the windows is left
exactly as it is.

The record a driver holds for a PCI function is never freed or moved: the
list is made at boot with room for 64 more, a function that leaves has its
record marked absent, and the next arrival at that address uses it again --
unless the departed function's driver could not let go, in which case the
record is retired and the arrival gets a new one.

```
/sys/bus/pci/slots/<number>/   address adapter power state events
/sys/bus/pci/rescan            write 1
```

`power` takes 0 (take the card out of use, as the button does but without
the wait) and 1 (bring it back).

Limits: the ports are polled, not listened to, so a press or a card is
noticed within half a second and a machine with such a port wakes twice a
second for it; a bridge that arrives is listed and nothing behind it is
found (no bus numbers or windows are made for it); ports are not given more
room than firmware gave them; a device that arrives on the root bus is found
but given no addresses; on AArch64 the ports are watched only in QEMU unless
`vinix.pci_hotplug=1` says otherwise, because what a slot's power switch
feeds on Apple hardware is not known here. Only the `e1000` has been taken
through an arrival and a departure: the other PCI drivers have no `remove`
and would be left holding a device that is gone.

## DMA and IOMMU

`kernel/dma` gives a driver memory *for a device*, with the address to tell
the device, and keeps the list of what each device may reach. What a driver
leaves mapped is unmapped and freed when it is unbound; a driver that gave up
on a device without being able to release it has the device cut off.

An IOMMU driver registers a unit with six operations and the DMA layer keeps
each device's page tables in step with its list. Two are implemented:

- **Intel VT-d** (`kernel/dma/vtd_*_amd64.v`): DMAR parsing, three- or
  four-level second-level tables, a domain per device, register-based
  invalidation, RMRR ranges kept reachable for the devices firmware names,
  faults polled, counted and published in `/sys/class/iommu/dmarN/`.
- **AMD-Vi** (`kernel/dma/amdvi_*_amd64.v`): IVRS parsing, the device table,
  command buffer and event log, a domain per requester id, IVMD unity ranges
  kept, events published in `/sys/class/iommu/ivhdN/`.

Translation is **off unless the kernel command line has `vinix.iommu=1`**. A
unit that is on blocks every device behind it that has no domain, and takes
over the machine's firmware-owned DMA; neither has been tried on a physical
PC, so it is opt-in until one has. With the option, `e1000` and `ahci` run in
domains that hold only their own rings, tables and buffers (`domain: dmar0
isolated` in the device's `dma` file). The other PCI drivers still choose
physical addresses themselves and are given all of memory (`identity`):
they work behind a unit and are not confined by it.

A unit that lost power in a suspend to RAM is brought back before any device
may use the bus again (`kernel/dma/resume_amd64.v`); one that will not come
back stops the machine.

Not implemented: interrupt remapping, queued invalidation (so VT-d units of
version 6 and later are left off), devices behind conventional PCI bridges
under VT-d (refused a domain), ARM SMMU. Apple's DARTs are still set up by
the drivers of the devices behind them (`kernel/apple/dart`) and are not
units of this layer.

## Firmware

`kernel/fwload` reads a firmware image by the name Linux knows it by, from
`/lib/firmware/updates`, `/lib/firmware` or `/usr/lib/firmware`, whole, into
kernel memory. Holders share one copy, which stays while one of them holds
it, so a driver can load its device again after a sleep or a reset without
the disk. An image can be read ahead of its driver and kept
(`/sys/firmware/loader/preload`, `drop`; `loaded` and `stats` report). Names
that are not plain paths below the firmware directories, images over 64 MiB
and anything that is not a regular file are refused.

No driver in the tree asks for firmware through it yet: Apple's Wi-Fi is
still given its images by `wifi-ctl` from userspace, and the other Apple
coprocessors are loaded by iBoot.

## Power off and restart

`reboot(2)` on both architectures goes through `kernel/syspower`: filesystem
caches are flushed (a failure refuses the transition), every device is shut
down through the device core -- an AHCI disk's cache is flushed and the disk
told to stop, an NVMe controller is sent the shutdown notification, the
e1000 stops DMA -- and then firmware is asked. A PC that ignores the ACPI
reset register is reset through the keyboard controller, port 0xcf9 and
finally a triple fault. An Apple SoC is restarted through its watchdog, as
Linux does; switching one off needs a write to the SMC that this kernel does
not make -- the one key it ever writes is the charge limit -- so `poweroff`
there ends halted with devices stopped.

## Firmware events, buttons and the lid

uACPI's handler for the SCI used to be accepted and never installed, and the
work it defers refused, so no ACPI event could arrive. The interrupt now
masks its line and wakes a thread that runs the handler; deferred work has a
queue and a thread; general purpose events and the fixed power and sleep
buttons are enabled once the scheduler runs (`kernel/uacpi/events.v`).

A power button press asks init to power off with the signal `poweroff` sends
(SIGUSR2) if init has a handler for it, and otherwise the kernel powers off
itself. Pressed while the machine sleeps, it wakes it and does nothing else.
QEMU's ARM machine reports its button through the generic event device,
which is polled.

On a PC, `kernel/x86/acpipm` finds the control method battery (`_BIX` or
`_BIF`, `_BST`), the charger (`_PSR`), the lid (`_LID`) and namespace power
and sleep buttons, and listens to each through Notify. Closing the lid
sleeps unless `/sys/power/lid/action` is `ignore`; opening it is a wake
source.

On most laptops those methods read the embedded controller, and the Notify
comes from an event of the controller's; see the next section.

## The embedded controller

A laptop's battery, charger, lid, thermal zones and hotkeys are behind a
microcontroller, reached through two I/O ports. Firmware's methods read it
through fields of an EmbeddedControl operation region, which the interpreter
cannot reach by itself, and it reports a change by raising a general purpose
event and then naming, when asked, a method to run (`_Qxx`).
`kernel/x86/acpiec` is the driver; `protocol.v` in it is the exchange of
bytes, kept free of the kernel so that it runs on the build machine.

**Found** in three steps. If firmware has an ECDT, the handler for the
controller's address space is installed before the namespace is loaded, so
that tables which touch the controller while loading, and `_INI` methods
after them, find it. After the namespace is initialised the `PNP0C09` device
gives the ports (`_CRS`), the event (`_GPE`, a number or a package), whether
the ACPI global lock is needed (`_GLK`) and `_UID`; a machine with no ECDT
gets its handler here; then `_REG` runs. That is Linux's order and Windows':
with no ECDT, `_INI` runs before the controller is there. Where the ECDT and
the device agree about the ports, the ECDT's event number is used; where
they do not, the device is believed. The handler is installed on the root of
the namespace, since firmware declares such regions outside the device's
scope. Once ACPI's event threads run, the controller becomes a device
(`/sys/bus/acpi/devices/PNP0C09:00`), its event gets a handler and is marked
as able to end a sleep, and whatever it had been waiting to say is asked for.
All of this is before the battery, charger and lid are looked for.

**Exchanges** are read (0x80), write (0x81) and query (0x84); the burst
commands are not used. Every wait ends by the clock: an exchange gets five
attempts of 500 ms, Linux's budget. An attempt that wrote everything and ran
out of time is followed by one that only waits, before the command is
written again -- a query asked twice loses an event. A byte found in the
output buffer before anything was asked is taken out instead of being read
as the answer; an output buffer that cannot be emptied fails the exchange at
once, which is what ports with nothing behind them look like.

**Giving up.** A controller that has never answered is given up on after its
first failed exchange, and one that has after three in a row. From then on
every caller is told at once, the methods that needed it fail, and the
battery reads `Unknown`. The device is marked `failed`; writing 1 to its
`reset` file asks the controller one question and puts it back in use if it
answers.

**Locking.** Exchanges are entered from the boot thread, from ACPI's work
thread and from system calls (a read in `/sys` evaluates `_BST`), never from
an interrupt, and are kept apart by a sleeping mutex that is held across
port I/O and waiting only. Where `_GLK` is 1 the global lock is taken
outside it, with a one-second limit, unless the calling thread already has
it through a field declared `Lock`.

**Events.** The general purpose event's handler queues a query on ACPI's
work queue and does nothing else. The work takes events out of the
controller until it has none -- at most 32 in one go -- and runs `_Qxx` for
each with nothing held. An exchange that sees the event bit up queues the
same work. An event bit that stays up while the controller names nothing is
not asked about again until it has been seen down. Where the event cannot be
used -- no `_GPE`, one in a block of events this kernel does not drive, or a
line raised more than 64 times a second for nothing -- a thread looks at the
event bit four times a second instead.

**Sleep.** Suspend to idle leaves the controller working: its event stays
on, and a lid that opens or a battery that runs out is attributed by the
driver that hears the Notify. What the controller reports is also counted
under a wake source of its own, `embedded-controller`, which is off unless
asked for, so that a hotkey or the charger can end a sleep on request and
the battery gauge does not. With `power/wakeup` of the device `disabled` its
event is off for the sleep. On resume, and at start, a controller whose
event bit is already up is asked.

A suspend to RAM (x86-64) takes the driver through the same suspend and
resume. The enable bits of the chipset's general purpose events are lost
with the power and written again by uACPI on the way back, before `_WAK`;
the controller's event is among them, or is switched on again by the
driver's resume if it was off for the sleep. The driver's threads are not
stopped for the sleep, so one of them can be put down in the middle of an
exchange, holding the controller's lock and firmware's global lock, when
the machine goes down. A controller normally keeps its power through S3 --
it is what watches the lid and the power button -- so the exchange would be
finished afterwards, and the driver's timeout, which is measured on a clock
that does not count the time away, would not have run out; what firmware
does on its way back with the global lock taken is not known. None of that
has been seen happen. A kernel with the simulated controller has been
through two suspends to RAM (`suspend-deep-ec`: values read, the chipset's
event heard again after each, an event held for a sleep asked for
afterwards), which says what the chipset's part and the driver's suspend
and resume do, and nothing about a controller, which there was memory that
lost no power.

**Thermal zones.** A laptop's thermal zone usually reads its temperature
from the controller (`_TMP` is a field of its region) and hears of a trip
through a query whose method sends the zone a Notify. Such a zone goes
through the same region handler as a battery's `_BST`, and zones are looked
for after the controller has started. What has been tried of the pair is one
side only: with a controller nothing answers for, a zone whose `_TMP` reads
it is not taken on and delays nothing (`acpi-ec-absent`). A zone read through
a controller that works -- polled once a second beside the battery, tripped
by a query, or losing its controller while it is being polled, where five
failed readings switch the zone off -- has not been run, simulated or real:
the thermal scenario's zone computes its temperature in AML, and the
controller scenarios' working tables have no zone.

**`/sys`** shows the ports, the event, how events are heard, the global
lock, whether the controller has been given up on and why, and counts of
exchanges, timeouts, restarts, stale bytes, queries and methods, in
`ec/` under the device. There is no file that reads or writes the
controller's memory.

**Three faults in the glue between uACPI and the kernel's mutexes**
(`kernel/acpisync`, `kernel/uacpi/uacpi.v`) came out of testing this and are
fixed. None was the controller's, and each affects every method evaluation,
with or without a controller:

- uACPI's reader-writer lock takes a mutex in the first reader and gives it
  back in the last. With two threads reading the namespace at once those are
  different threads, and the kernel refused the release as one by a
  non-owner: the mutex stayed taken and every later evaluation waited for
  ever.
- The same first reader, coming back to write while another thread still
  read, was refused as a thread waiting for a mutex it held: the method it
  was about to run failed with nothing wrong, and a battery read `Unknown`
  about once in ten boots.
- A thread with a signal waiting for it may not sleep, and a read in `/sys`
  evaluates a method in the reader's context: its wait for a mutex another
  thread held ended at once with an error, and the method failed. Such a
  thread now takes turns with the others until the mutex is free.

The first two took two threads using ACPI at once, which a battery's polling
thread and a read in `/sys` are. uACPI 2.0.0 also refuses the number its own
`uacpi_acquire_global_lock()` returns when the lock is given back with it
(it hands out its counter and then advances it); the binding tries that
number and then the next.

What this is not:

- **Not run against hardware.** The protocol runs against a simulated
  controller on the host (`tests/acpi-ec`). In a guest, a kernel built with
  `-d acpiec_selftest` runs everything above the two port instructions
  against the same simulation, with tables that describe a controller; an
  ordinary kernel has only been shown ports where nothing answers. How a
  particular laptop's controller behaves -- how long it takes, what it does
  when asked twice, whether it wants the queries Linux gives Samsung's
  (`vinix.ec=clear`) -- is unknown until one is tried.
- One controller is driven. A second `PNP0C09` device gets a handler that
  refuses its regions.
- Not the SMBus host controller some firmware puts behind the embedded
  controller (`ACPI0001`), so a Smart Battery (`ACPI0002`) is not read.
- A controller reached other than through I/O ports -- in memory, or on an
  I2C bus as hardware-reduced machines have it -- is not driven.
- `_GPE` naming a block of events (`ACPI0006`) is understood and falls back
  to polling: this kernel serves only the FADT's two blocks.
- No per-model quirks. Linux applies its by a table of machines. Here two
  are boot options (`clear`, `dsdt-gpe`); believing the ECDT's event is the
  default, as it is Linux's; and an ECDT whose ports disagree with the
  device's -- the swapped ports Linux corrects on some MSI machines -- loses
  to the device, but only once the namespace has been read.

## Sleep

Writing `freeze` to `/sys/power/state` suspends to idle, and so does `mem`
unless suspend to RAM has been selected (below). `disk`, where it is
offered, is a suspend to disk, which has a section of its own further down;
it begins with the same steps:

1. filesystem caches are flushed;
2. userspace is frozen (every thread parks at its next return to userspace;
   kernel threads continue);
3. devices are suspended last to first -- a driver that refuses stops the
   sleep -- and PCI functions that can come back from it are put into D3hot
   (below);
4. the CPU's protection registers are recorded (CR0, CR4, EFER; SCTLR_EL1,
   TCR_EL1), the screen goes dark, and wake sources start being listened to;
5. the machine waits for a wake source;
6. the screen comes back; the registers are compared with what was recorded
   -- a difference is restored, and a failure to restore panics -- devices
   are resumed first to last, and userspace thaws.

The screen (`kernel/term/sleep.v`): where it is the boot loader's
framebuffer -- a PC with no display driver, a virtual machine -- its picture
is copied away page by page, the framebuffer is painted black, and the
picture is copied back on waking, so the console or the compositor finds
what it drew. Console text that arrives meanwhile is not drawn (it still
reaches the serial port); a panic is. If there is no memory for the picture
the screen stays lit, and `suspend_stats/screen_lit` counts it
(`screen_dark` counts the others). A panel with a driver of its own --
Apple's, through DCP -- is not reached by this.

**The backlight.** Behind a black picture a panel's backlight is still lit,
and it is most of what a lit screen draws. Where firmware can set it -- a
panel in the ACPI namespace with `_BCL` and `_BCM`, the video extensions --
`kernel/x86/acpipm/video.v` lists it under `/sys/class/backlight/acpi_videoN/`
by Linux's names (`brightness`, `max_brightness`, `actual_brightness`,
`bl_power`, `type`; `kernel/brightness` is the class), puts it at its dimmest
level when the devices are suspended and gives it its level back when they
resume. A panel that cannot say what level it is at (no `_BQC`, or an answer
that is not on its list) is left as it is for a sleep until it has been set
once: nothing knows what to give it back. The levels are sorted out as Linux sorts them, the two firmware
prefers told from the list. Firmware's brightness keys are a Notify to the
panel -- brighter, dimmer, around, darkest -- and are acted on in the kernel,
so they work with nothing running; the bus is told (`_DOS`) that brightness
is not firmware's to change. `bl_power` 4 is the dimmest level, which
firmware rarely makes dark. `vinix.acpi_backlight=off` leaves the panels
alone.

A panel whose `_BCM` hands the work to the graphics driver -- Intel's, through
the OpRegion, on most laptops of the last decade -- is listed and takes
levels that change nothing: there is no such driver. That, and whether any
real panel dims, is not known. QEMU has no panel; the test gives it two in a
table and reads what their methods were given off a port QEMU records
(`acpi-backlight`: the levels, both keys, off and on, a sleep, 200 changes
that leave the heap flat; `acpi-backlight-off`: nothing said). Apple's panel
has a driver of its own and a device node (`/dev/apple-panel-bl`) and is not
in this class.

Wake sources (`kernel/wakesrc`, `/sys/class/wakeup/wakeupN/`): power button,
sleep button, lid, keyboard, pointer, alarm, network, USB, battery, embedded
controller. Each can be allowed or not; a pointer, the network and the
embedded controller are not by default. A key going
down wakes and its release does not. `/sys/class/rtc/rtc0/wakealarm` sets an
alarm. `/sys/power/suspend_stats/` reports successes, failures, what failed,
what woke the machine and how long each phase took.

With `devices` in `/sys/power/pm_test` the sequence stops short of sleeping
and comes back after `pm_test_delay_ms`: every driver's suspend and resume
run without depending on a wakeup. This is how a machine's drivers should be
checked before the machine is trusted to sleep.

With `platform` in `pm_test`, and `deep` selected (below), the rehearsal goes
the whole way down for a suspend to RAM -- processors parked, everything
read out -- and comes back after the delay without asking firmware. It is the
way back from a sleep that firmware refused, with nothing having lost power.
A wake source that reports during it ends it as a failed sleep.

### PCI power states

A driver's suspend makes its device quiet; it is still fully powered. Between
steps 3 and 4 above, each PCI function that can come back from it is put into
D3hot, in which it answers in configuration space and nowhere else, and
before the first driver resumes in step 6 it is brought back to D0 and given
its configuration space again, as after a loss of power: a function need keep
nothing across D3hot, and most forget their address registers
(`kernel/devcore/pci_power.v`, after Linux's `pci_set_power_state()`).

Which functions: those with a power management capability, bound to a driver
that has both a suspend and a resume (the test that decides whether the
machine may be suspended to RAM at all), in D0, and not allowed to wake the
machine -- nothing arms a function to signal from D3. Bridges stay in D0. A
function that does not take the state is left in D0; one that does not come
back is not resumed, and is handed to recovery like any device that stopped
answering. The same is done before a suspend to RAM, where D3hot is what the
platform expects to find when it cuts the power. And before the image
of a suspend to disk is taken, which no scenario has with a function that
goes down: it was run once by hand with the 82574L in the machine of
`hibernate`, twice down and back.

`/sys/bus/pci/devices/<address>/power_state` is the state a function says it
is in, `power/d3_count` how many sleeps it has spent in D3hot, and
`/sys/power/pci_d3` what the last sleep and all sleeps did: functions put
down, functions that refused, functions that did not come back, registers
found changed and written back. `vinix.pci_d3=off` keeps every function in
D0.

What is tested, and what is not:

- QEMU's 82574L (`e1000e`) is the one card in these machines with the
  capability whose state QEMU acts on. While the machine sleeps, the test's
  controller asks QEMU for its memory map, and the card's registers are not
  in it; before and after, they are (`pci-d3`, both architectures, for a
  rehearsal and a suspend to idle, and on x86-64 a suspend to RAM entered
  from D3hot). With `vinix.pci_d3=off` they stay (`pci-d3-off`).
- QEMU's NVMe controller has the capability too: `nvme-sleep` takes it
  through the same three sleeps in D3hot. Its AHCI, IDE and HD Audio
  controllers and its 82540EM have none and stay in D0.
- QEMU's card forgets nothing on the way back, so there the writing back
  finds nothing to do. A kernel built with `-d pci_d3_selftest` clears the
  card's address and command registers while it is down, which is what a
  real one does to itself; the card works afterwards only because they were
  written back (`pci-d3-selftest`).
- No real device has been through it. Devices that misbehave in D3hot exist
  -- Linux carries a list -- and there is no list here, only the option.
  D1, D2 and D3cold (power resources, `_PS3`) are not used, nothing is put
  down while the machine runs, and no function is armed to wake it (PME).

### Suspend to RAM (x86-64)

`/sys/power/mem_sleep` chooses what `mem` means: `s2idle`, the default, or
`deep`, ACPI's S3, where memory keeps its power and nothing else does. With
`deep` selected the sequence above carries on past step 4 (`kernel/syspower/deep_amd64.v`):

1. the thread moves to the boot processor, the one firmware resumes;
2. firmware prepares (`_PTS`) and is given the address to resume at;
3. an alarm that is set is handed to the battery-backed clock;
4. every other processor is parked, and PCI configuration space, the
   display mode and the screen's contents are read out;
5. with interrupts off, the interrupt controllers and clocks are read out,
   the processor is saved, and firmware is asked for S3.

On the way back firmware runs first, then the kernel's own real-mode entry,
and execution continues after step 5 as if a call had returned.

**The real-mode entry.** A processor that wakes from S3, or is sent a
startup IPI, begins in real mode below 1 MiB. Eight pages there -- the
highest free run, away from the firmware data at the bottom -- are taken
out of the allocator before its first allocation. One holds a trampoline
(`kernel/asm/x86_64/wake_trampoline.S`) that climbs from real mode through
protected mode to long mode; the others hold a page table of the kernel's
own that maps that one page onto itself beside the kernel's half of the
address space. Its address goes into the FACS waking vector; the 64-bit
vector is left empty.

**The processor that sleeps** saves what it holds and gets it back
(`kernel/asm/x86_64/wake_context.S`, `kernel/x86/wake/context.v`): the
callee-saved registers and the stack; CR0, CR2, CR3, CR4 and EFER; the GDT,
IDT, task and LDT registers and the segment registers; the FS, GS and kernel
GS bases; STAR, LSTAR, CSTAR, SFMASK and the PAT; XCR0 and the floating
point state of the thread that asked for the sleep; IA32_SPEC_CTRL and
IA32_MISC_ENABLE where present; its local APIC (mode, spurious vector, local
vectors, timer divider); and VMX operation. The debug registers, SYSENTER
registers and TSC_AUX are not saved because the kernel never loads them.
**MTRRs and microcode are left to firmware**, as they are at boot.

**The other processors** are not given a saved context. An idle processor in
this scheduler holds no thread, no lock and nothing on its stack, so each is
made idle and kept there (`kernel/sched/park_amd64.v`): `may_run_here()`
refuses every thread on it, the thread it ran is put down at its next
scheduler interrupt, and from `await()` it goes offline under the TLB
shootdown lock, reads out its local APIC and halts with interrupts off.
Afterwards each is started with INIT and a startup IPI through the same
trampoline, set up by the code that set it up at boot
(`x86.cpu.initialisation.reinitialise()`: descriptor tables, TSS, page
table, SYSCALL, PAT, GS, CR0.WP, SMEP, SMAP, UMIP, extended state,
speculation controls from the policy chosen at boot, VMX), given its local
APIC back, and enters the idle loop as it did at boot. This happens the same
way whether or not the power went, so a sleep that firmware refused runs the
same code as one that happened.

**Time.** The counter the kernel keeps time with stops or starts again with
the power; the battery-backed clock does not. The counter is made to carry
on from exactly where it stopped, so the monotonic clock never goes back and
**does not include the time the machine was away**: no deadline in the
kernel -- a watchdog, a network timeout, a driver's wait -- finds hours gone
by at once, and nothing is billed to the thread that asked for the sleep as
processor time. (A suspend to idle is different: the counter keeps running
there and the monotonic clock includes the sleep.) The battery-backed clock
is read before and after, and the difference is added to the wall clock
alone (`time.advance_realtime()`), **to within a second**, which is what
that clock counts in; timers set for a time of day are looked at straight
away. `last_sleep_ms` includes it. An alarm is handed to that clock at least
two seconds ahead, and set again if getting the machine down used the time
up; its day and month registers, where the FADT names any, are set to match
any day. An alarm more than a day ahead cannot be given to the clock and
does not wake the machine from S3.

**Devices,** in the order they come back. With interrupts still off and one
processor running: the 8259s are masked and every I/O APIC redirection entry
written back; the PIT is reprogrammed; the counter is set going; and **IOMMU
units are brought back** (root or device table, command and event rings,
translation on) -- before anything on the bus can move, and stopping the
machine if one will not come back. While that one processor has interrupts
off, an ACPI lock that is held is not waited for. Then the other processors
are started and interrupts go on, and before firmware's wake method (`_WAK`)
runs, since it may reach for any device: **PCI configuration space** of
every function is restored (`kernel/devcore/pci_state.v`: D0 first, address
registers and bridge windows before the command register, MSI and the MSI-X
control word, the PCI Express control registers with a port's slot power
and lights), and the display's mode is set again. After `_WAK` the fixed
power and sleep button events are enabled again, and the drivers resume:
`ahci`, `e1000`, `nvme`, `ata` and `hda` reset and reprogram their devices as
they do on every resume; the keyboard controller, the PS/2 mouse and the
serial ports are set up again only after a loss of power. A deep sleep is
**refused while a bound PCI device's driver has no suspend and resume**:
such a device would come back blank. Every PCI driver has both now.

**Hot-plug slots, and what changed during the sleep.** The thread that
watches PCI Express slots is kept off them from before the devices go down
until they are back (`pause_pci_hotplug()`): a port without power, or with
its bus numbers not yet written back, shows cards missing that are there. It
finishes the pass it is in first, and a sleep is refused if it cannot.

Nothing reports what happened on the buses while the power was off: a port
loses the events it latched, and firmware sends no `Notify` for what it saw
with no system running. So after such a sleep (`compare_buses()` in
`kernel/devcore/hotplug.v`):

- a function that no longer answers with the vendor and device it had --
  given a second to, once for all functions, since a device may be that slow
  after its reset -- is not written to, **its driver is not asked to resume
  it**, and the thread removes it as it removes a card pulled without
  warning;
- a watched slot left with nothing on its bus is treated as empty, so a card
  now in it -- another card, or one put into a slot that was empty -- is
  brought in by the pass over the slots that follows;
- every bus is then scanned, as a write to `/sys/bus/pci/rescan` does, which
  is what finds a device firmware would have announced.

A slot whose presence bit differs from before the sleep does not get its old
power switch and lights written back with the rest of its port: that setting
was for what was in it then.

**The display.** Firmware does not set the mode again after S3, and the
kernel has no graphics driver, so `deep` is only offered where the kernel
can bring the picture back itself: there is no framebuffer, or it is on the
adapter QEMU's `std` VGA and `bochs-display` have (PCI 1234:1111), whose
mode registers are read out before the sleep and written back after it
(`kernel/syspower/display_amd64.v`). The picture itself is handled as for
any sleep: put away and painted black before the machine goes down, and
copied back once it is awake -- which for a suspend to RAM is after the mode
is back. On any other machine with a screen `mem_sleep` lists `s2idle`
alone, and `/sys/power/deep_sleep` says why. `vinix.deep_sleep=force` offers
it anyway, for a machine run without a screen or whose firmware restores the
mode; the screen is then whatever firmware leaves. `vinix.deep_sleep=off`
never offers it.

**What may end it** is the platform's to carry out, and has to be arranged
before the machine goes down: every firmware event is switched off for a
suspend to RAM but those marked as able to wake the machine. The lid, the
power and sleep buttons that are devices, and the keyboard say in `_PRW`
which event that is and from how deep a sleep. Each is found once and its
event marked (`kernel/x86/acpipm/wake.v`, after Linux's
`acpi_enable_wakeup_devices()`); then, before firmware is told of a suspend
to RAM, each whose wake source is allowed (`/sys/class/wakeup`) and which
can end a sleep that deep has its power resources switched on, is told
through `_DSW` (or the older `_PSW`), and has its event left enabled; after
the machine is back it is told it need not any more. A power resource
switched on for this is left on. The embedded controller's event is marked
by its own driver. `/sys/power/acpi_wakeup` lists the devices, how each is
told and how often it has been armed; `vinix.acpi_wake=off` leaves all of it
undone. After every sleep a lid is asked where it is: firmware does not
always say that it was opened while the machine was down.

QEMU's PC cannot be woken through such an event, so no test wakes a machine
by its lid. What is tested (`suspend-deep-wake`) is what would let one: a
table gives the machine a lid (from S3, `_PSW`), a sleep button (from S4,
`_DSW`) and a power button that can only end S1; while the machine is
suspended the test's controller reads the event enable register, which
holds the lid's and the sleep button's bits and no other, and with the lid
not allowed only the button's; the methods write what they were called with
to a port QEMU records, and the record is compared. With
`vinix.acpi_wake=off` the register holds nothing and no method runs
(`suspend-deep-wake-off`). PCI devices are not armed (PME), and a USB
keyboard ends a suspend to idle but not a suspend to RAM: its controller is
without power like the rest.

**What ended it** is read on the way back: the clock's alarm (PM1 status),
a byte waiting in the keyboard controller (keyboard or pointer), the power
or sleep button; a lid found open that was shut is taken for the cause
when none of those is. The `enabled` setting of a wake source decides
whether the alarm is armed and whether a device is armed as above; the
fixed power button and the keyboard controller wake the machine whatever
it says. QEMU reports its `system_wakeup` command as the power button.

`/sys/power/deep_sleep` also counts the suspends to RAM and says what the
way back from the last one had to write back (PCI registers, interrupt
routes, the display, IOMMU units), and `suspend_stats` has
`last_failed_reason`, `last_depth`, `deep` and `security_cpus`. A kernel
built with `-d wake_trace` writes each step of a sleep to the first serial
port.

What this is not:

- **Not tried on a physical machine.** Suspend to RAM has run only in QEMU
  (q35, OVMF, TCG). On real hardware nothing here is known to work: the
  firmware's resume path, the A20 gate (assumed open), low memory surviving
  firmware, MTRRs and microcode on the other processors, a wake-up by the
  lid or a key (their events are armed as firmware describes them, and no
  machine has been woken that way), and the AMD IOMMU's own PCI capability
  are all untested assumptions.
- **Not a suspend to disk**, which is the next section: it uses all of
  this for the way back, and adds an image of memory, a device to keep it
  on and a boot that goes back into it.
- `e1000`, `ahci`, `nvme`, `ata`, `hda`, the keyboard controller, the PS/2
  mouse and the serial ports come back from a loss of power. A machine with
  a bound PCI driver that cannot is refused deep sleep and left with suspend
  to idle; none of x86-64's is left. Sound that was queued when the machine
  went down is dropped, and what QEMU cannot show is not shown: its codec
  keeps its settings through a controller reset, so that the codec's paths
  are programmed again after a sleep is by inspection only.
- On x86-64 the protection registers (CR0, CR4, EFER, IA32_SPEC_CTRL) are
  recorded and compared on every online processor, each asked by an
  interrupt, for both kinds of sleep. On AArch64 they are checked on the
  CPU that carries out the sleep only.
- A processor that does not start again after a sleep is logged, counted
  once and left out; the machine carries on without it, later sleeps do not
  wait for it or try it again, and threads that may only run there do not
  run. This path has never run: no processor has failed to start here.
- **If firmware accepts the request for S3 and then neither sleeps nor
  returns**, the machine hangs with interrupts off: uACPI polls the
  wake-status bit without a limit, and that code is shared with other work
  and was not changed.
- Of what can change on the buses during a sleep, QEMU allows two things to
  be tried, and both are: a card put into a slot the kernel watches, and a
  device firmware manages being taken away or put in. A card pulled from, or
  exchanged in, a watched slot follows the same code and has not run.
- The wall clock is only as good as the battery-backed clock's seconds: each
  sleep can put it up to a second out.
- With no HPET the kernel keeps time by the TSC, and that way through a
  sleep has not run.
- The VMX part (leaving and entering VMX operation around a sleep) has not
  executed: no emulator used here has VT-x.
- The dark screen is a black picture, not a display switched off: there is
  no display power control (DPMS). A backlight firmware can set is put at
  its dimmest (above); any other stays lit behind the picture, and Apple's
  panel is not darkened at all.
  The desktop turns its display off before it asks for a sleep -- a black
  frame of its own, and the backlight at its minimum where it can set one --
  which on such a panel is all that goes dark; a sleep asked for any other
  way leaves it as it was.

### Suspend to disk (x86-64)

`disk` in `/sys/power/state` writes an image of memory to a device, switches
the machine off, and on the next start goes back into the image: the write
that asked for it returns then, in the same process, in a machine that has
been without power. It is offered only when the kernel command line names a
device for the image:

```
vinix.hibernate=sd1        the name the device has in /dev, with or without /dev/:
                           a whole disk or a partition
```

```
/sys/power/state       freeze mem disk
/sys/power/disk        [shutdown]   -- what happens once the image is written;
                                       the only way there is
/sys/power/hibernate   available, or unavailable: and why; the device; what the
                       last boot found on it, and a device an image is still
                       waiting on; the last image's pages, bytes and times;
                       what the kernel that loaded it reported
/sys/power/suspend_stats/disk, and last_depth `disk`, last_wake `resume-from-disk`
```

It is a suspend to RAM with the RAM taken out
(`kernel/syspower/hibernate_amd64.v`, `kernel/hibernate/`): everything the
section above describes is used again, and what is new is where memory goes
and how it comes back.

**The device** is the image's and nothing else's, and is the only thing
hibernation ever writes. The kernel does not choose one: with no
`vinix.hibernate=` there is no `disk` state, writing it fails, and no disk
is written to. What is named is found once, when the disk drivers have
brought their disks up, and reached through its node's resource -- the read
and write an open of `/dev/sd1` ends in, with no filesystem or cache between.
Before the first image the device has to be one of two things: blank over
its first and last megabyte, or already carrying a header of this system's.
A device with anything else on it is left exactly as it is and `disk` is not
offered, so a root filesystem named by mistake is not written over; it is
looked at again before every image, once userspace is frozen. The installer that takes a blank disk
for the system (`vinix.disk=auto`) never takes the named one. Its node is
made mode 0600, and so is the disk a named partition is on: **the image is a
copy of memory with every secret the kernel had, it is not encrypted, and
whoever can read the device can read them** -- root, and anybody with the
disk in their hands.

On the device (`kernel/hibernate/format.v`): a 4 KiB header -- signature,
version, a checksum of itself, the number of pages, checksums of the list
and of the pages, how to enter the image, when it was taken, and the
machine it was taken on -- then the frame number of every saved page, then
the pages. The checksums tell a whole image from a torn one; they are not a
signature.

**Going down.** Caches are flushed, userspace is frozen, the hot-plug thread
is kept off the buses, the devices are suspended, the protection registers
are recorded and the screen's picture is put away, as for any sleep. Then:

1. the thread moves to the boot processor;
2. tables are made and a free page is taken for every page in use, with
   some to spare, and for everything writing the image will need
   (`hibernate.prepare()`). Whether there is room is worked out before any
   page is taken -- the rest of the kernel is still running, and much of it
   stops the machine when it is refused memory. If memory is too full for a
   copy of itself the page cache gives back what it can read again; if it
   is still too full, or the image would not fit the device, the sleep
   fails with the reason;
3. the other processors are parked, PCI configuration space and the display
   mode are read out;
4. with interrupts off the interrupt controllers and clocks are read out and
   the processor is saved exactly as for S3 -- and where S3 asks firmware
   for the sleep, every page is copied (`hibernate.take_snapshot()`).

*Which* pages is read off the allocator and the boot loader's memory map:
of usable memory, every page the allocator has handed out (its own bitmap,
and hibernation's tables, among them); all of what the boot loader marked
reclaimable, which this kernel never reclaims and still reads its answers
from; and all of the kernel and its modules. Free memory, firmware's
regions, ACPI's tables and the framebuffer are not saved.

Two kernels come out of step 4. The one that took the copy carries on as
from a sleep firmware refused: processors started, devices resumed, userspace
still frozen. It writes the device -- first a header that describes no
image, so that an old image cannot be entered once it is partly written
over; then the list and the pages; a flush; and last the header, which is
read back and compared -- and switches the machine off. If anything fails
before that header is written, the device holds no image, everything taken
is given back, and the machine thaws as from any failed sleep with the
reason in `suspend_stats`. One failure is different: the last header
written, not confirmed by the flush or the reading back, and then not
replaceable either. Nobody knows what the device holds then, and if it is
the image, it is an image of the disks as they are at that moment. The
machine is switched off all the same: the next start goes back into the
image or finds none and starts afresh, and either is right so long as
nothing more is changed.

**Nothing else reaches a disk after the snapshot.** The image holds every
mounted filesystem as it was at that instant; a block allocated or a page
swapped out afterwards would be a change the image knows nothing of. So
every block driver passes a fence before it writes or discards
(`kernel/block/fence`): from the snapshot on, a write that is not the
image's is held there until the machine is off -- or until hibernation has
failed, when it goes through. A request that had passed the fence and was
waiting for its disk to wake when the snapshot was taken is asked again
with the disk's lock held; and the page cache holds a writer before it
takes its own lock, so that nothing is held at a driver's door with a lock
another thread could need. The power-off itself is `transition()`'s
without its first step, the flush of the filesystems, for the same reason:
they were flushed before the snapshot, and the devices' own caches are
flushed by their shutdown.

**Coming back.** In `kmain_thread`, straight after the IDE and AHCI drivers
have their disks and before the verified root or the system disk is looked
for (`hibernate.resume_at_boot()`): nothing on a disk has been mounted,
replayed or written. That is also checked rather than trusted: the block
drivers count every write they are asked for from boot, and a kernel that
has made any does not enter an image.

A whole image is entered only by a boot that matches it. Compared, each
with its own reason when it differs:

| What | Why |
| --- | --- |
| the kernel: its length and a digest of its code and constants | the image is entered at an address in the kernel |
| the kernel command line | the two kernels were configured alike: an IOMMU on in one is on in the other |
| the SATA and IDE disks and the partitions on them, each by name and size | a filesystem the image holds in memory belongs to the disk it was on |
| the memory the machine has, as runs of addresses | every saved page goes back into its frame |
| every region that is not such memory -- firmware's, ACPI's, the framebuffer -- by place, length and kind | the kernel inside believes its own map |
| where the kernel is mapped, the direct map's offset, the depth of the page tables | pointers |
| the processors: how many, their APIC numbers in order, their features | they are started again by number |
| ACPI: the root pointer, every table's address, length, name and contents; the FACS by address | uACPI holds pointers into the tables and runs their methods in place |
| the framebuffer: address and geometry | the kernel draws on what firmware set up |
| the pages under 1 MiB processors start on | they are started there |

Anything else -- a damaged header, a list or pages that do not match their
checksums, a frame that is not memory here, no memory to load it -- and the
reason is printed and kept in `/sys/power/hibernate`, **the device is given
a header that describes no image**, and the machine starts afresh. The same
header is written, flushed and read back just before an image is entered:
an image is entered once, and a crash on the way in cannot be gone back
into.

**An image nobody went back into.** A start that is not told of the image
-- no `vinix.hibernate=`, or the name now belongs to another disk -- would
mount the system's disk, change it, and leave behind an image that a later
start goes back into: a kernel that then corrupts the disk from what it
remembers. So every start that has its disks up and has not gone back into
an image reads the first block of each disk and partition for one that
still could be (`look_for_images()`; reads, nothing else). If there is one
-- on a device it was not told of, on the named device when the image could
not be discarded, or the named device cannot be read at all -- **the
system's disk is not mounted**: the machine runs from memory, the kernel
says which device and what to do, `/sys/power/hibernate` has it under
`waiting`, and `disk` is not offered. The image is not touched, since its
device was not named this time. A verified root, which is only read, is
mounted regardless.

Three things are deliberately *not* compared, because two boots of the same
QEMU machine already differ in them: how the boot loader divided memory
between itself, the modules and free memory (it moved by two pages between
consecutive boots); where it put the kernel (it moved by sixteen); and the
contents of the ACPI tables BGRT and FPDT, which describe the boot and not
the machine. The image depends on none of the three.

**Loading.** A page whose frame is free in the loading kernel is read
straight into it -- the frame is taken from the allocator by number. A page
whose frame the loading kernel is using is read into a frame the image does
not want, and the pair is written down. Then the image is marked as used,
the devices are suspended so that nothing writes to memory behind the
processor, any IOMMU the loading kernel switched on is switched off, the
other processors are parked, and with interrupts off the last step
(`kernel/asm/x86_64/hibernate.S`) runs from a page of its own, on a stack
and under a page table of its own, all in frames the image does not want:
it turns global pages and tagged address spaces off, which drops every
cached translation; copies the pairs into place, over the loading kernel's
own code, data and page tables; and jumps to the entry a processor woken
from S3 arrives at, with the image's saved processor. Since the image's
kernel need not lie in the frames the loading kernel does, that page table
maps the kernel's addresses onto the image's kernel.

From there it is the way back from a suspend to RAM: descriptor tables,
MSRs and the extended state; the I/O APICs, the timer chip and the clock
from where it stopped; the IOMMUs; the other processors through the
real-mode trampoline; the wall clock moved on by the battery-backed clock;
PCI configuration space as this kernel had it, with a function that is not
what it was left to the hot-plug thread; the display mode; the drivers,
told their devices lost power. What an S3 does with firmware is left out --
firmware was not asked for a sleeping state and has no wake method to run --
and the enable bits of ACPI's events, which the hardware lost and a later
boot had not yet set, are written from the kernel's own record of them.

**What is refused, and when.**

- Before anything is suspended: no device named, or not found when the
  disks came up; a named device that is neither blank nor this system's, or
  that cannot be read; an image from an earlier start still waiting on a
  device; no real-mode entry for the other processors.
- With the bindings frozen: a bound PCI device whose driver cannot bring it
  back from a loss of power, as for a suspend to RAM. None of x86-64's
  drivers is one any more.
- While the copy is prepared: not enough free memory, after the page cache
  has given back what it can; an image that would not fit the device.
- On AArch64 there is no `disk`.
- The display does not decide. A suspend to RAM needs a display the kernel
  can set a mode on because firmware sets none on the way back from S3; a
  machine that is switched off and on gets its mode from firmware and the
  boot loader as on any start, and what the image needs -- the same
  framebuffer in the same place -- is one of the things a boot is compared
  on. `vinix.deep_sleep=` has no part in it.
- An IOMMU is handed over, not refused: the loading kernel switches its
  units off before it enters the image, and the kernel inside switches them
  on with its own tables before any device may use the bus, as after S3.

**Measured** in QEMU (q35, TCG, 1 GiB, 4 processors, an Apple Silicon host
with nothing else running): with a 64 MiB pattern held by the test program
the image is 67,734 pages, 265 MiB; copying it takes 140 ms with the machine
stopped, writing it 380 to 530 ms; the next boot reads it in 390 ms, 0.7 s
after its kernel started -- 33,010 pages straight into their frames and
34,724 by way of another -- and the write to `state` returns 5 to 7 s of
wall-clock time after it was made, most of which is firmware. Without the
pattern the image is 39,526 pages, of which about 19,700 are the boot
loader's reclaimable memory and the kernel. Five suspends to disk one after
another leave the kernel heap where the first left it: 7837 live objects
before the last four and 7850 after, and the same 7850 after ten.

What this is not:

- **Not tried on a physical machine**, and it depends on more of the
  machine staying the same than a suspend to RAM does. On real firmware
  these are assumptions nobody has tested: that two boots have the same
  memory and the same firmware regions at the same addresses; that the ACPI
  tables are at the same addresses with the same contents (a table besides
  BGRT and FPDT whose contents change from boot to boot means every image
  is refused); that firmware which keeps state of its own across a
  power-off -- a boot counter, a pending update, a fast-boot path that
  skips devices -- leaves the machine as the image expects. Where an
  assumption fails the image is refused and discarded, not entered.
- **ACPI's S4 is not used.** The machine is switched off through S5 and
  cold-started. `_PTS(4)` and `_WAK(4)` are not run, the FACS hardware
  signature is not read, and the NVS regions are not saved: what firmware
  keeps there is this boot's, and the methods of a kernel put back from an
  image run against it.
- **The image is not encrypted or signed.** See the device, above.
- **What is on the disks is not compared**, only which disks there are and
  how large. One exchanged for another of the same size while the machine
  was off is used as if it were the one the image knew.
- **Only this kernel knows to leave a waiting image's disks alone.** A
  start of another system, or of a kernel from before this, mounts and
  writes what it likes; started with the option again afterwards, the
  kernel inside the image wakes to disks that have moved on and will
  corrupt them. Nothing in the image records the state of the filesystems
  it holds, so nothing can tell. And this kernel only keeps *itself* from
  mounting the system's disk: a program in a machine running from memory
  can still mount a disk by hand.
- If the device cannot be written when an image is refused, or just before
  one would be entered, the image stays on it. The kernel says so, does not
  enter it and does not mount the system's disk, and can do no more.
- The boot loader's reclaimable memory is saved whole -- 65 MiB of a 1 GiB
  QEMU machine -- because the kernel does not know which part of it holds
  the answers it still reads. The image is not compressed.
- A device that appears after the disks came up is not looked for; a
  partition as the image's device, and an IDE disk, follow the same code
  and have not been tried: the tests use a whole SATA disk. A release
  kernel does not start `nvme`, and where it is started it comes up after
  the image has been looked for, so an NVMe disk cannot hold one.
- What has been through a resume is small: an ext2 root on a SATA disk
  with two files written to it, and the kernel's own state. No swap, no
  journal replay, no filesystem with much in its cache, no desktop.
- Interrupts left pending in the local or I/O APIC by the kernel that
  loaded the image are not cleared before the image's kernel takes them
  over; none has been seen to matter.
- The kernel must be the same build. An image is not carried from one
  kernel to the next, and an updated system discards it.
- No part of the image is read back before the machine is switched off but
  its header; a page the device took and did not keep is found by the
  checksum on the way back, when the image is refused.
- The other limits of a suspend to RAM hold here as well: wake-up is by
  switching the machine on and by nothing else; an alarm does not start a
  machine that is off.

## Power supplies

`kernel/psupply` is the class a battery or charger driver registers with. It
keeps readings no more than a second old, publishes
`/sys/class/power_supply/<name>/` by Linux's names and units, and smooths
the rate into an estimate of the time left (`time_to_empty_now`,
`time_to_full_now`): a burst of load moves the estimate only in proportion
to how long it lasted, and a battery that reports no rate has one derived
from how its charge moves.

A battery at the low threshold (10%) is logged and shows `Low` in
`capacity_level`. One at the critical threshold (3%) while discharging, or
that says so itself, asks for the shutdown the power button asks for -- once
per discharge, waking the machine first if it sleeps. It is not taken at one
reading's word: the battery is asked again every two seconds and believed
once it has said so for five, because a gauge or an embedded controller that
was busy can return one wrong answer, and the answer to this one is the
machine going off. The thresholds are in
`/sys/class/power_supply/policy/`. Going onto the battery selects the
power-saving CPU profile and back onto the charger the balanced one, unless
`/sys/power/profile_policy` is `manual`.

A battery that says itself how full it is has that figure as `capacity`, and
the thresholds are held against it, rather than its charge divided by its
full charge: the percentage a maker shows is not always that quotient.

The drivers are ACPI's and Apple's. **Apple's SMC** is a battery
(`macsmc-battery`) and a charger (`macsmc-ac`) here, beside the two device
nodes it always was ([M1 battery](m1-battery.md)): status by Linux's reading
of the SMC's flags, the SMC's own percentage and time estimates, charge now,
full and by design, current, voltage and cycle count. Its figures are held to
what a battery can say before the class sees them -- a percentage that jumps
is believed at the second look, the firmware's "about to give out" flag
after two -- and an SMC that stops answering leaves the battery `Unknown`
with no figures instead of its last ones. **It has run against a simulated
SMC only, on the build machine and in QEMU; never on a Mac.**

`charge_control_end_threshold` exists only where a driver can set a charge
limit. One can: Apple's, on firmware that has the `CHWA` key, where it takes
80 or 100 and nothing else, is written only when a program writes the file,
and is read back before the write is called done. No ACPI battery has one.

## CPU idle and frequency

`kernel/cpuidle` counts and chooses the idle states CPUs wait in
(`/sys/devices/system/cpu/cpuN/cpuidle/`): HLT or MWAIT C-states on x86-64
with intel_idle's tables for the client models it knows, WFI on AArch64
where the scheduler already used it. `kernel/cpufreq` has policies,
governors, an energy preference and profiles
(`/sys/devices/system/cpu/cpuN/cpufreq/`), with drivers for Intel HWP and
SpeedStep, AMD CPPC and Apple cluster DVFS. See
[tests/cpu-power](../tests/cpu-power/README.md) for the options and for
exactly what has and has not executed.

In short: under QEMU the idle driver is `halt` or `wfi` and the frequency
driver is `none`. The masked MWAIT entry, every state deeper than C1 and
every frequency register have never run. On a physical Apple machine the
idle loop still polls instead of waiting (`vinix.apple_idle=wfi` changes
that, untried) and frequency control is off (`vinix.apple_cpufreq=1`,
untried).

## Thermal

`kernel/thermal` has zones with passive, hot and critical trips and one
polling thread. Above a passive trip the limit on CPU performance
(`cpufreq.set_thermal_limit`) drops ten points per rising reading and comes
back step by step below the hysteresis; the hot trip drops it to the floor
at once; a critical trip turns the machine off, storage flushed and devices
stopped. A sensor that stops answering disables its zone after five failures
and leaves the limit where it was. `/sys/class/thermal/`, `/sys/class/hwmon/`
and `/sys/class/powercap/` follow Linux.

Sensor drivers: Intel's digital thermal sensors (coretemp), AMD's k10temp,
and RAPL energy counters, each read through an MSR accessor that fails
instead of faulting. QEMU has none of these registers.

The zones and fans a PC's firmware describes (`kernel/x86/acpipm/thermal.v`):
every ACPI thermal zone with a `_TMP` becomes a zone of type `acpitz`, its
`_PSV`, `_HOT` and `_CRT` the zone's passive, hot and critical trips. Its
active trips (`_AC0` to `_AC9`) drive the fans their `_ALx` list each time
the zone is read: a fan runs for the hottest trip at or below the
temperature that lists it -- flat out for `_AC0`, a step slower for each
trip below -- and stops two degrees under the last. Fans (`PNP0C0B`) of
both kinds are driven: one that takes a level (`_FSL`; a percentage where
`_FIF` allows any value, otherwise the nearest level `_FPS` lists) and
reports its speed (`_FST`, shown as `fanN_input`), and one that is on or
off through `_PS0`/`_PS3` or the power resources of `_PR0`. Each is among
the zone's fans in hwmon and can be set by hand through `pwmN` until the
zone next changes its mind; `/sys/class/thermal/acpi_fans` lists what each
was last told. A `Notify` that trips or fan lists changed reads them again.

Firmware's figures are not all believed, because what follows a critical
reading is the machine switching itself off. A reading at or below absolute
zero or of 200 degrees or more is a failed reading, not a temperature; a
trip at or below freezing or at 200 degrees or more is not a trip; and a
reading at or past the critical trip is taken again a twentieth of a second
later, the cooler of the two being the one acted on.
`/sys/class/thermal/acpi_zones` counts what each zone had to disbelieve.
`vinix.acpi_thermal=nocrt` takes the zones without their critical trips, and
`=off` leaves firmware's zones and fans alone, for a machine whose firmware
reports temperatures that are not.

Apple's SMC (`kernel/apple/smc`, [M1 battery](m1-battery.md)) is one zone,
`macsmc`, carrying the four temperatures Linux's device tree gives an M1
laptop -- flash storage, the battery, the charge regulator, the wireless
module -- with their labels in hwmon, and each fan the SMC counts with its
speed and the slowest and fastest it runs (`fanN_input`, `fanN_min`,
`fanN_max`). The zone has no trip points and the fans no `pwmN`: the SMC
gives no limit for these sensors and runs its fans itself, so the kernel
shows both and decides nothing by them. A reading that is not a number, at
or below absolute zero or of 200 degrees or more reads as nothing. An M1
MacBook Air has no fan and gets no fan files. As with the battery: tested
against a simulated SMC on the build machine and in QEMU, never on a Mac.

Not done: the zone's own passive constants (`_TC1`, `_TC2`, `_TSP` -- the
stepping above is used), `_TZD`, `_TZP`, counting the users of a power
resource two fans share, and fans a laptop's embedded controller runs
without telling ACPI (most laptops). Of Apple's SMC: its power, voltage and
current sensors, the sensor list of the device tree's `apple,smc-hwmon` node
(the kernel has its own table of four), and the temperature of the SoC
itself, which the SMC keys Linux names do not include.

## Boot options

| Option | Effect |
| --- | --- |
| `vinix.iommu=1` | switch on Intel VT-d or AMD-Vi units (default off) |
| `vinix.iommu_igfx=1` | also switch on a VT-d unit that only covers integrated graphics |
| `vinix.cpuidle=off\|halt\|mwait`, `vinix.max_cstate=N` | x86-64 idle driver and depth |
| `vinix.cpufreq=off\|simulate` | no frequency driver, or one with memory for registers |
| `vinix.apple_idle=wfi`, `vinix.apple_cpufreq=1` | Apple hardware only; untried |
| `vinix.apple_battery=0` | Apple hardware only: do not drive the SMC at all |
| `vinix.apple_smc=legacy` | Apple hardware only: the SMC as `/dev/battery` and `/dev/battery-power` alone, with nothing but reads of the percentage and the three telemetry keys sent to it. `nosensors` leaves out temperatures and fans, `nolimit` the charge limit key; the three combine with commas. Untried on a Mac, like the driver |
| `vinix.thermal_sensors=0`, `vinix.tjmax=N` | skip the x86 sensor drivers; state TjMax |
| `vinix.pci_hotplug=0\|1` | leave PCI Express hot-plug ports alone, or watch them where the kernel would not by itself |
| `vinix.acpi_thermal=off\|nocrt` | leave firmware's thermal zones and fans alone, or take them without the trip that switches the machine off |
| `vinix.ec=off` | do not drive the embedded controller |
| `vinix.ec=clear` | at start and on resume, query the controller until it names no event, whatever its event bit says (Linux's `EC_FLAGS_CLEAR_ON_RESUME`); untried |
| `vinix.ec=dsdt-gpe` | where the ECDT and `_GPE` name different events, use `_GPE` (Linux's `EC_FLAGS_TRUST_DSDT_GPE`); untried. The three combine with commas |
| `vinix.deep_sleep=force\|off` | x86-64: offer suspend to RAM although the kernel cannot bring the display back; never offer it |
| `vinix.pci_d3=off` | keep every PCI function in D0 through a sleep |
| `vinix.acpi_wake=off` | x86-64: do not arm the lid, buttons and keyboard to end a suspend to RAM |
| `vinix.acpi_backlight=off` | x86-64: leave the panels whose backlight firmware sets alone |
| `vinix.usb=off` | leave the xHCI controller, and with it any USB keyboard, to firmware |
| `vinix.hibernate=<device>` | x86-64: the block device, by its name in `/dev`, that an image of memory is written to for a suspend to disk. It is overwritten, and looked at for an image at every start. Without the option there is no `disk` state and no disk is written to |

## What is not done

Beyond the limits stated in each section:

- PCI hotplug beyond what its section states: no interrupt-driven ports, no
  bridges behind a slot, no resizing of a port's windows, no SHPC or
  conventional PCI slots except through ACPI, and no driver but `e1000` that
  can let go of a device.
- USB beyond keyboards and pointers on the root ports of one xHCI
  controller: no core, no hubs, no hotplug, no storage; see its section.
- Device power states beyond D3hot for a sleep: D1, D2 and D3cold, runtime
  power management, PME and wake-on-LAN.
- Behind the embedded controller: a second controller, the SMBus host and
  Smart Batteries, controllers not on I/O ports, events in a block of their
  own. And the controller itself on any real laptop.
- Suspend to RAM and suspend to disk on anything but QEMU's PC: see their
  sections for what is untested. For a suspend to disk also: ACPI's S4,
  an image that is encrypted, signed or compressed, an image carried from
  one kernel build to another, and any of it on AArch64. Display power
  control, and a backlight that is not firmware's to set: one that needs
  the graphics driver, and Apple's in the class the others are in.
- Apple's SMC on a Mac. The battery, charger, temperatures, fans and charge
  limit are tested against a simulated SMC on the build machine and in
  QEMU; **no physical run**, of this or of the device nodes before it. Past
  that: the `CHLS` charge limit of firmware without `CHWA`, the charge
  inhibit keys, a wake from the SMC's notifications (a battery that runs out
  during a sleep is not noticed), switching the machine off through the SMC,
  an interrupt-driven mailbox (each exchange is a busy wait, some fifteen a
  second), and the SMC after a sleep that cut its power.
- Coming back from a loss of power for Apple's drivers;
  restoring a display the kernel has no mode-setting for; wake-up by a PCI
  device (PME), or over USB from a suspend to RAM; an RTC alarm more than a
  day ahead.
- **Desktop.** The native desktop uses these interfaces now, and none of
  that has run against a kernel: it is tested on the host, against the text
  the kernel writes and a machine the tests stand in for. Settings and the
  taskbar read the first present battery in `/sys/class/power_supply` with
  its status and the kernel's time estimates, and fall back to `/dev/battery`
  where there is none. An Apple laptop now has one (`macsmc-battery`), so
  there too the desktop takes the first path -- which, like the rest of
  this paragraph, no kernel has been run to show. The Start menu
  has Restart, and Sleep where `/sys/power/state` offers `mem`. Settings >
  Power has the lid action, the performance profile (disabled where the
  kernel takes none, as in every virtual machine) and two idle timeouts,
  after which the compositor turns the display off and puts the machine to
  sleep; the saved lid action and profile are written back when the desktop
  starts. Both timeouts are Never until somebody chooses a time: turning the
  display off has not been run in a virtual machine or on a machine, and is
  not a default until it has been. What it still does not do:
  - Nothing can ask for the display to stay on. There is no inhibit
    interface, so a film watched without input is turned off like anything
    else.
  - There is no screen lock: a display that comes back on, and a machine
    that wakes, show the session as it was left.
  - Display off is a black frame, with the backlight at its minimum where
    the desktop can set one (`/dev/apple-panel-bl`; it does not use
    `/sys/class/backlight` yet). No panel is powered down. The desktop does the same before a sleep, beside the kernel's own
    dark screen, which reaches only a boot framebuffer.
  - Only the first battery is shown, and the kernel's low and critical
    thresholds are not announced on screen.
- `hwcheck` is built by hand (`tools/hwcheck/build`); no image ships it.

## Qualification record, 2026-10-10 and 2026-10-11

Kernels were built in a git worktree with `make ARCH=aarch64 LIMINE_MP=1` and
`make ARCH=x86_64`, and run on QEMU 11.1.1 on an Apple Silicon Mac: x86-64
`q35` under TCG with 2 CPUs (4 for the `suspend-deep` and `hibernate`
scenarios, with the edk2 firmware QEMU ships, which is what resumes the
machine from S3 and starts it again after a suspend to disk),
AArch64 `virt` under HVF with 4 CPUs. The two are not comparable in speed.

```sh
tests/hardware-platform/run --arch x86_64 --kernel build-amd64-kernel/bin/vinix
tests/hardware-platform/run --arch aarch64 --kernel kernel/bin/vinix
```

| Scenario | x86-64 | AArch64 |
| --- | --- | --- |
| `devices`: sysfs, unbind/bind/reset/remove, 100 cycles leave the heap flat | pass | pass |
| `ahci`: I/O before and after a port reset, data on the disk afterwards | pass | -- |
| `qmp-powerdown`, `power-button-init`, `restart` | pass | pass |
| `suspend`: rehearsal, alarm, key, power button, a source not allowed to wake | pass | pass |
| `acpi-power`: scripted battery, charger and lid | pass | -- |
| `acpi-thermal`: a scripted thermal zone, four fans of every kind, the passive limit, critical power-off | pass | -- |
| `acpi-backlight`, `acpi-backlight-off`: two scripted panels -- levels, brightness keys, off and on, down for a sleep and back, what firmware was told read off a recorded port -- and none of it with `vinix.acpi_backlight=off` | pass | -- |
| `acpi-ec-absent`, `acpi-ec-off`: a described embedded controller that nothing answers for; the driver switched off | pass | -- |
| `iommu-intel`, `iommu-amd`, `iommu-off` | pass | -- |
| `cpu-power`, `cpu-power-simulated` | pass | pass |
| `thermal` | pass | pass |
| `firmware` | pass | pass |
| `screen-sleep`: pictures of the screen lit before, dark during and lit after a sleep and a rehearsal | pass | pass |
| `usb-input`: a USB keyboard and mouse behind xHCI with no other keyboard in the machine -- typing, the pointer, a suspend to idle ended by a key, and (x86-64) the controller set up again after a suspend to RAM | pass | pass |
| `pci-hotplug`: a card put into a port the kernel watches and taken out, twice; 100 remove/rescan cycles | pass | pass |
| `pci-hotplug-acpi`: the same, announced and asked back by firmware | pass | -- |
| `pci-hotplug-iommu`: the same behind Intel VT-d, the card isolated each time it arrives | pass | -- |
| `pci-d3`: a card put into D3hot for a rehearsal, a suspend to idle and (x86-64) a suspend to RAM; QEMU asked for its memory map while the machine is down; 40 more sleeps leave the heap flat | pass | pass |
| `pci-d3-off`: `vinix.pci_d3=off`, the card left in D0 and on the bus | pass | pass |
| `suspend-deep`: suspend to RAM with 4 CPUs -- two rehearsals, wakes by `system_wakeup`, alarm and key, five more sleeps; every CPU, memory, disk, network, clocks, keyboard, mouse, power button; the screen dark while down and as drawn afterwards | pass | -- |
| `suspend-deep-xapic`, `suspend-deep-bridge`: the same without x2APIC, and with the card behind a watched hot-plug port | pass | -- |
| `suspend-deep-iommu`, `suspend-deep-iommu-amd`: the same behind VT-d and AMD-Vi, the unit found off and brought back each time | pass | -- |
| `suspend-deep-arrival`: a card put into a watched slot while the machine is suspended to RAM, found after the wake; a sleep with it in; the slot gives it up afterwards | pass | -- |
| `suspend-deep-departure`: with firmware keeping the ports, a card taken during one sleep is removed after it, and a card put in during the next is found | pass | -- |
| `suspend-deep-undrawable`, `suspend-deep-forced`, `suspend-deep-headless`: when deep is offered | pass | -- |
| `suspend-deep-wake`, `suspend-deep-wake-off`: a lid and a sleep button armed to end a suspend to RAM -- their events left enabled, firmware told, the lid found open afterwards -- and none of it with `vinix.acpi_wake=off` | pass | -- |
| `drivers-sleep`: HD Audio playing and an IDE disk through a rehearsal, a suspend to idle and a suspend to RAM; the recording and the disk image checked afterwards | pass | -- |
| `hibernate`: suspend to disk twice with 4 CPUs, three boots of one machine; the same process returns from its write each time with its memory, threads, files, descriptors, pipe and child as they were; every CPU, the clocks, disk, network, screen and power button afterwards; no image left on the device | pass | -- |
| `hibernate-xapic`: the same with page tables four levels deep and no x2APIC | pass | -- |
| `hibernate-iommu`, `hibernate-iommu-amd`: the same behind VT-d and AMD-Vi, which the kernel that loads the image has switched on as well | pass | -- |
| `hibernate-cycles`: five suspends to disk one after another, six boots; the kernel heap after the last four as after the first | pass | -- |
| `hibernate-damaged-header`, `hibernate-damaged-pages`, `hibernate-memory`, `hibernate-disks`: an image damaged while the machine was off, a machine with less memory, and one with a disk more, start afresh, say why, discard the image and work | pass | -- |
| `hibernate-unnamed`, `hibernate-foreign`: with no device named, or one that holds something else, there is no `disk` and both disks are byte for byte as they were made | pass | -- |
| `hibernate-root`: the system installed on a disk; a file written before the image is taken, another by the resumed kernel, both read back by a third start afresh from the disk | pass | -- |
| `hibernate-waiting`: the same, started once without the option in between: the image is found waiting and left whole, the system's disk is not mounted, no disk is written to; the next start goes back into the image | pass | -- |
| `thermal-selftest` (kernel built with `-d thermal_selftest`) | pass | pass |
| `iommu-intel-selftest`, `iommu-amd-selftest` (25 and 21 checks) | pass | -- |
| `acpi-ec-selftest`, `acpi-ec-selftest-dsdt` (kernel built with `-d acpiec_selftest`: a simulated embedded controller) | pass | -- |
| `suspend-deep-ec` (the same kernel): the controller's driver through two suspends to RAM | pass | -- |
| `nvme-sleep` (kernel built with `PROD=false`): an NVMe disk through the same three sleeps | pass | -- |
| `pci-d3-selftest` (kernel built with `-d pci_d3_selftest`): the same card made to forget its address and command registers in D3hot, which are written back | pass | pass |
| `apple-smc-selftest` (kernel built with `-d applesmc_selftest`: a simulated Apple SMC; run 2026-10-11): battery, charger, four temperatures and a fan in `/sys` and in the device nodes; garbage readings that change nothing; the charge limit; a sleep; low, critical and the power-off request; an SMC that stops answering | -- | pass |
| `apple-smc-selftest-bare`, `-options`, `-legacy` (the same kernel): no fan and no charge limit; `vinix.apple_smc=nosensors,nolimit`; `vinix.apple_smc=legacy` | -- | pass |

Host unit tests: `tests/hardware-platform/hwhost` (10 files),
`tests/power-supply/run`, `sh tests/cpu-power/run.sh`, `sh tests/thermal/run.sh`,
`tests/pci-hotplug/run`, `sh tests/acpi-ec/run.sh` (40 tests of the embedded
controller's protocol against a simulated controller),
`sh tests/apple_smc/run-host.sh` (51 tests of the SMC client against a
simulated SMC), `sh tests/hibernate/run.sh` (what makes a suspend-to-disk
image valid, and on what two machines are compared).
See [the suite's README](../tests/hardware-platform/README.md) for what each
scenario checks and for its recorded output.

Measured for retention, after the kernel's grace period for deferred frees:
100 unbind/bind cycles of the e1000, 100 cycles of removing a hot-added
e1000 and finding it again by a rescan, and 50 load/drop cycles of a 100 KiB
firmware image leave the kernel heap's live objects and large pages where
they were, on both architectures. On AArch64, 16 passes of the Apple SMC's
thread with 5700 reads of its files in `/sys` and of its two device nodes do
the same (4234 live objects before and after).

`tests/kernel-allocs/run.sh` already reported about 170 allocation sites not
in `allowed.txt` before this work, in files it did not touch, and still
exits 1; `allowed.txt` was left alone. The existing Python-driven suites
(`qemu-core`, `process-smp`, `storage-volumes` and the rest) were not run:
the repository's rules no longer allow running Python.

These runs establish that the mechanisms work against QEMU's emulated
devices. They say nothing about any physical controller, firmware or
battery, and they do not qualify a driver.
