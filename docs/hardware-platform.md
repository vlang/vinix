# Hardware platform and power management

This is the record for roadmap workstream 4: what the kernel now does to find
devices, bind and recover drivers, isolate DMA, load firmware, manage power
and sleep, and what it does not do yet.

Everything described here was built for both architectures and exercised in
QEMU guests (x86-64 under TCG, AArch64 under HVF). **None of it has run on a
physical machine.** The hardware-specific paths that no emulator has -- the
Intel, AMD and Apple frequency registers, processor temperature sensors,
MWAIT idle states, a real embedded controller -- are covered by host unit
tests of their arithmetic and are otherwise unverified. Which machine is
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

Not implemented: interrupt remapping, queued invalidation (so VT-d units of
version 6 and later are left off), devices behind conventional PCI bridges
under VT-d (refused a domain), restoring a unit after a sleep that powers it
down, ARM SMMU. Apple's DARTs are still set up by the drivers of the devices
behind them (`kernel/apple/dart`) and are not units of this layer.

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

**There is no embedded controller driver.** On most laptops the battery, lid
and charger methods read the EC, so on real hardware they will fail until one
is written; in QEMU they are exercised against a table with no EC.

## Sleep

Writing `freeze` or `mem` to `/sys/power/state` suspends to idle:

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
sleep button, lid, keyboard, pointer, alarm, network, USB, battery. Each can
be allowed or not; a pointer and the network are not by default. A key going
down wakes and its release does not. `/sys/class/rtc/rtc0/wakealarm` sets an
alarm. `/sys/power/suspend_stats/` reports successes, failures, what failed,
what woke the machine and how long each phase took.

With `devices` in `/sys/power/pm_test` the sequence stops short of sleeping
and comes back after `pm_test_delay_ms`: every driver's suspend and resume
run without depending on a wakeup. This is how a machine's drivers should be
checked before the machine is trusted to sleep.

What this is not:

- **Not suspend to RAM.** `mem` is suspend to idle; `/sys/power/mem_sleep`
  offers only `s2idle`. Nothing loses power, the alarm is the kernel's own
  timer, and on x86 CPU 0 keeps its 1 kHz tick, so the power saved is what
  suspended devices and idle CPUs save and no more.
- **Not hibernation.** There is no memory image and no `disk` state.
- Only `e1000` and `ahci` have suspend and resume. Every other driver keeps
  its device running through a sleep, which is correct for suspend to idle
  and would not be for anything deeper.
- The protection registers are checked on the CPU that carries out the sleep,
  not on every CPU.
- The dark screen is a black picture, not a display switched off: there is
  no backlight class and no display power control (DPMS), so a panel's
  backlight stays lit behind it, and Apple's panel is not darkened at all.

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
instead of faulting. QEMU has none of these registers. There are no ACPI
thermal zones, no fan control, and no Apple (SMC) sensors.

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

## What is not done

Beyond the limits stated in each section:

- PCI hotplug beyond what its section states: no interrupt-driven ports, no
  bridges behind a slot, no resizing of a port's windows, no SHPC or
  conventional PCI slots except through ACPI, and no driver but `e1000` that
  can let go of a device.
- USB: no core, no hubs, no hotplug; xHCI drives boot keyboards and pointers
  on AArch64 PCI only.
- Device power states (D3), runtime power management, wake-on-LAN.
- Suspend to RAM, hibernation, backlight and display power control.
- Restoring an IOMMU, or any driver but `e1000` and `ahci`, after a sleep
  that powers devices down.
- The desktop: Settings and the taskbar still read `/dev/battery`; there is
  no Sleep or Restart in the menu and no idle or lid setting.
- `hwcheck` is built by hand (`tools/hwcheck/build`); no image ships it.

## Qualification record, 2026-10-10

Kernels were built in a git worktree with `make ARCH=aarch64 LIMINE_MP=1` and
`make ARCH=x86_64`, and run on QEMU 11.1.1 on an Apple Silicon Mac: x86-64
`q35` under TCG with 2 CPUs, AArch64 `virt` under HVF with 4 CPUs. The two
are not comparable in speed.

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
| `iommu-intel`, `iommu-amd`, `iommu-off` | pass | -- |
| `cpu-power`, `cpu-power-simulated` | pass | pass |
| `thermal` | pass | pass |
| `firmware` | pass | pass |
| `screen-sleep`: pictures of the screen lit before, dark during and lit after a sleep and a rehearsal | pass | pass |
| `pci-hotplug`: a card put into a port the kernel watches and taken out, twice; 100 remove/rescan cycles | pass | pass |
| `pci-hotplug-acpi`: the same, announced and asked back by firmware | pass | -- |
| `thermal-selftest` (kernel built with `-d thermal_selftest`) | pass | pass |
| `iommu-intel-selftest`, `iommu-amd-selftest` (25 and 21 checks) | pass | -- |

Host unit tests: `tests/hardware-platform/hwhost` (7 files),
`tests/power-supply/run`, `sh tests/cpu-power/run.sh`, `sh tests/thermal/run.sh`,
`tests/pci-hotplug/run`.
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
