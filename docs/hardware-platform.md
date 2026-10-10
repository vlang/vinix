# Hardware platform and power management

This is the record for roadmap workstream 4: what the kernel now does to find
devices, bind and recover drivers, isolate DMA, load firmware, manage power
and sleep, and what it does not do yet.

Everything described here was built for both architectures -- suspend to RAM
for x86-64 only -- and exercised in QEMU guests (x86-64 under TCG, AArch64
under HVF). **None of it has run on a physical machine.** The
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
| `ahci` | PCI | yes | no (mounted disks) | yes | flush, STANDBY IMMEDIATE, stop | port COMRESET | per-device domain |
| `nvme` | PCI | yes | no | no | shutdown notification | no | all of memory |
| `ata` | PCI | yes | no | no | no | no | all of memory |
| `hda` | PCI | yes | no | no | no | no | all of memory |
| `xhci` | PCI | yes | no | no | no | no | all of memory |
| `virtio_*` (AArch64 MMIO) | platform | listed from the device's own status | no | no | no | no | not behind an IOMMU |
| `battery`, `ac`, `button` | ACPI | listed as claimed | no | -- | -- | -- | -- |
| `ec` | ACPI | listed as claimed | no | holds its events back when it may not wake | stops taking events | asks a failed controller one question | -- |
| `i8042`, `psmouse`, `serial8250` (x86-64) | platform | listed as claimed | no | set up again after a loss of power | -- | -- | -- |

A driver without `remove` cannot be unbound and `/sys` has no `unbind` file
for it. Apple's platform drivers (SMC, ANS, DART, DCP, AGX, Wi-Fi, speakers,
SPI keyboard, Type-C) still start the way they did and are **not listed** on
the platform bus.

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
Linux does; switching one off needs the SMC, which this kernel cannot ask,
so `poweroff` there ends halted with devices stopped.

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
driver's resume if it was off for the sleep. Nothing is done about an
exchange cut short by the power going: the driver is not stopped for the
sleep, and one of its threads put down in the middle of an exchange would
come back to a controller that has forgotten it and time out. A kernel with
the simulated controller has been through this (`suspend-deep-ec`: values
read, the chipset's event heard again after each of two sleeps, an event
held for a sleep asked for afterwards), which says what the chipset's part
and the driver's do, and nothing about a controller, which there was
memory that lost no power.

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
unless suspend to RAM has been selected (below):

1. filesystem caches are flushed;
2. userspace is frozen (every thread parks at its next return to userspace;
   kernel threads continue);
3. devices are suspended last to first -- a driver that refuses stops the
   sleep;
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
Apple's, through DCP -- is not reached by this, and its backlight stays on.

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
`ahci` and `e1000` reset and reprogram their devices as they always have on
resume; the keyboard controller, the PS/2 mouse and the serial ports are set
up again only after a loss of power. A deep sleep is **refused while a bound
PCI device's driver has no suspend and resume** (`nvme`, `ata`, `hda`,
`xhci`): such a device would come back blank.

**Hot-plug slots, and what changed during the sleep.** The thread that
watches PCI Express slots is kept off them from before the devices go down
until they are back (`pause_pci_hotplug()`): a port without power, or with
its bus numbers not yet written back, shows cards missing that are there. It
finishes the pass it is in first, and a sleep is refused if it cannot.

Nothing reports what happened on the buses while the power was off: a port
loses the events it latched, and firmware sends no `Notify` for what it saw
with no system running. So after such a sleep (`compare_buses()` in
`kernel/devcore/hotplug.v`):

- a function that no longer answers with the vendor and device it had is
  not written to, **its driver is not asked to resume it**, and the thread
  removes it as it removes a card pulled without warning;
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

**What ended it** is read on the way back: the clock's alarm (PM1 status),
a byte waiting in the keyboard controller (keyboard or pointer), the power
or sleep button. In a deep sleep it is the platform that decides what may
wake the machine; the `enabled` setting of a wake source only decides
whether the alarm is armed. QEMU reports its `system_wakeup` command as the
power button.

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
  firmware, MTRRs and microcode on the other processors, wake-up from
  devices that need a wake GPE armed (none is), and the AMD IOMMU's own PCI
  capability are all untested assumptions.
- **Not hibernation.** There is no memory image and no `disk` state.
- Only `e1000`, `ahci`, the keyboard controller, the PS/2 mouse and the
  serial ports come back from a loss of power. A machine with another bound
  PCI driver is refused deep sleep, and is left with suspend to idle.
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
  no backlight class and no display power control (DPMS), so a panel's
  backlight stays lit behind it, and Apple's panel is not darkened at all.
  The desktop turns its display off before it asks for a sleep -- a black
  frame of its own, and the backlight at its minimum where it can set one --
  which on such a panel is all that goes dark; a sleep asked for any other
  way leaves it as it was.

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
per discharge, waking the machine first if it sleeps. The thresholds are in
`/sys/class/power_supply/policy/`. Going onto the battery selects the
power-saving CPU profile and back onto the charger the balanced one, unless
`/sys/power/profile_policy` is `manual`.

The only drivers are ACPI's. **Apple's SMC battery is not a power supply
here**: it remains `/dev/battery` and `/dev/battery-power`
([M1 battery](m1-battery.md)), with no status, energy or time. There is no
charge limit on any machine: `charge_control_end_threshold` exists only where
a driver can set one, and none can.

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

Not done: the zone's own passive constants (`_TC1`, `_TC2`, `_TSP` -- the
stepping above is used), `_TZD`, `_TZP`, counting the users of a power
resource two fans share, fans a laptop's embedded controller runs without
telling ACPI (most laptops), and Apple's sensors and fans (SMC).

## Boot options

| Option | Effect |
| --- | --- |
| `vinix.iommu=1` | switch on Intel VT-d or AMD-Vi units (default off) |
| `vinix.iommu_igfx=1` | also switch on a VT-d unit that only covers integrated graphics |
| `vinix.cpuidle=off\|halt\|mwait`, `vinix.max_cstate=N` | x86-64 idle driver and depth |
| `vinix.cpufreq=off\|simulate` | no frequency driver, or one with memory for registers |
| `vinix.apple_idle=wfi`, `vinix.apple_cpufreq=1` | Apple hardware only; untried |
| `vinix.thermal_sensors=0`, `vinix.tjmax=N` | skip the x86 sensor drivers; state TjMax |
| `vinix.pci_hotplug=0\|1` | leave PCI Express hot-plug ports alone, or watch them where the kernel would not by itself |
| `vinix.ec=off` | do not drive the embedded controller |
| `vinix.ec=clear` | at start and on resume, query the controller until it names no event, whatever its event bit says (Linux's `EC_FLAGS_CLEAR_ON_RESUME`); untried |
| `vinix.ec=dsdt-gpe` | where the ECDT and `_GPE` name different events, use `_GPE` (Linux's `EC_FLAGS_TRUST_DSDT_GPE`); untried. The three combine with commas |
| `vinix.deep_sleep=force\|off` | x86-64: offer suspend to RAM although the kernel cannot bring the display back; never offer it |

## What is not done

Beyond the limits stated in each section:

- PCI hotplug beyond what its section states: no interrupt-driven ports, no
  bridges behind a slot, no resizing of a port's windows, no SHPC or
  conventional PCI slots except through ACPI, and no driver but `e1000` that
  can let go of a device.
- USB: no core, no hubs, no hotplug; xHCI drives boot keyboards and pointers
  on AArch64 PCI only.
- Device power states (D3), runtime power management, wake-on-LAN.
- Behind the embedded controller: a second controller, the SMBus host and
  Smart Batteries, controllers not on I/O ports, events in a block of their
  own. And the controller itself on any real laptop.
- Suspend to RAM on anything but QEMU's PC: see its section for what is
  untested. Hibernation, backlight and display power control.
- Coming back from a loss of power for `nvme`, `ata`, `hda` and `xhci`;
  restoring a display the kernel has no mode-setting for; wake-up GPEs
  (`_PRW`) for devices; an RTC alarm more than a day ahead.
- **Desktop.** The native desktop uses these interfaces now, and none of
  that has run against a kernel: it is tested on the host, against the text
  the kernel writes and a machine the tests stand in for. Settings and the
  taskbar read the first present battery in `/sys/class/power_supply` with
  its status and the kernel's time estimates, and fall back to `/dev/battery`
  where there is none, which is still every Apple machine. The Start menu
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
    the desktop can set one (`/dev/apple-panel-bl`). No panel is powered
    down. The desktop does the same before a sleep, beside the kernel's own
    dark screen, which reaches only a boot framebuffer.
  - Only the first battery is shown, and the kernel's low and critical
    thresholds are not announced on screen.
- `hwcheck` is built by hand (`tools/hwcheck/build`); no image ships it.

## Qualification record, 2026-10-10

Kernels were built in a git worktree with `make ARCH=aarch64 LIMINE_MP=1` and
`make ARCH=x86_64`, and run on QEMU 11.1.1 on an Apple Silicon Mac: x86-64
`q35` under TCG with 2 CPUs (4 for the `suspend-deep` scenarios, with the
edk2 firmware QEMU ships, which is what resumes the machine from S3),
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
| `acpi-ec-absent`, `acpi-ec-off`: a described embedded controller that nothing answers for; the driver switched off | pass | -- |
| `iommu-intel`, `iommu-amd`, `iommu-off` | pass | -- |
| `cpu-power`, `cpu-power-simulated` | pass | pass |
| `thermal` | pass | pass |
| `firmware` | pass | pass |
| `screen-sleep`: pictures of the screen lit before, dark during and lit after a sleep and a rehearsal | pass | pass |
| `pci-hotplug`: a card put into a port the kernel watches and taken out, twice; 100 remove/rescan cycles | pass | pass |
| `pci-hotplug-acpi`: the same, announced and asked back by firmware | pass | -- |
| `pci-hotplug-iommu`: the same behind Intel VT-d, the card isolated each time it arrives | pass | -- |
| `suspend-deep`: suspend to RAM with 4 CPUs -- two rehearsals, wakes by `system_wakeup`, alarm and key, five more sleeps; every CPU, memory, disk, network, clocks, keyboard, mouse, power button; the screen dark while down and as drawn afterwards | pass | -- |
| `suspend-deep-xapic`, `suspend-deep-bridge`: the same without x2APIC, and with the card behind a watched hot-plug port | pass | -- |
| `suspend-deep-iommu`, `suspend-deep-iommu-amd`: the same behind VT-d and AMD-Vi, the unit found off and brought back each time | pass | -- |
| `suspend-deep-arrival`: a card put into a watched slot while the machine is suspended to RAM, found after the wake; a sleep with it in; the slot gives it up afterwards | pass | -- |
| `suspend-deep-departure`: with firmware keeping the ports, a card taken during one sleep is removed after it, and a card put in during the next is found | pass | -- |
| `suspend-deep-undrawable`, `suspend-deep-forced`, `suspend-deep-headless`: when deep is offered | pass | -- |
| `thermal-selftest` (kernel built with `-d thermal_selftest`) | pass | pass |
| `iommu-intel-selftest`, `iommu-amd-selftest` (25 and 21 checks) | pass | -- |
| `acpi-ec-selftest`, `acpi-ec-selftest-dsdt` (kernel built with `-d acpiec_selftest`: a simulated embedded controller) | pass | -- |
| `suspend-deep-ec` (the same kernel): the controller's driver through two suspends to RAM | pass | -- |

Host unit tests: `tests/hardware-platform/hwhost` (8 files),
`tests/power-supply/run`, `sh tests/cpu-power/run.sh`, `sh tests/thermal/run.sh`,
`tests/pci-hotplug/run`, `sh tests/acpi-ec/run.sh` (40 tests of the embedded
controller's protocol against a simulated controller).
See [the suite's README](../tests/hardware-platform/README.md) for what each
scenario checks and for its recorded output.

Measured for retention, after the kernel's grace period for deferred frees:
100 unbind/bind cycles of the e1000, 100 cycles of removing a hot-added
e1000 and finding it again by a rescan, and 50 load/drop cycles of a 100 KiB
firmware image leave the kernel heap's live objects and large pages where
they were, on both architectures.

`tests/kernel-allocs/run.sh` already reported about 170 allocation sites not
in `allowed.txt` before this work, in files it did not touch, and still
exits 1; `allowed.txt` was left alone. The existing Python-driven suites
(`qemu-core`, `process-smp`, `storage-volumes` and the rest) were not run:
the repository's rules no longer allow running Python.

These runs establish that the mechanisms work against QEMU's emulated
devices. They say nothing about any physical controller, firmware or
battery, and they do not qualify a driver.
