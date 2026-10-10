# Hardware and power tests

Boots a built kernel in QEMU with a small V program as its only process, lets
that program exercise the kernel's device and power interfaces, and judges
the result on the host: by the lines the guest prints on the serial port, by
what QEMU reports over its machine protocol (QMP), and where a scenario asks
for it by what is left on a disk image afterwards.

The controller (`run.v`, module `hwhost`) and the guest (`guest/`) are V.
`run` is a thin shell launcher that compiles and starts the controller
through `build-support/run-v-tool.sh`. Nothing here is Python, and nothing
here runs any.

## What it covers

| Scenario | Architectures | What must hold |
| --- | --- | --- |
| `devices` | aarch64, x86_64 | Every link in `/sys/bus/pci/devices` leads to a device with `vendor`, `device`, `class` and `state`. The e1000 is `bound` and has a `driver` link; unbinding makes it `unbound`, removes the link and leaves `dma` at `domain: none`; unbinding again fails; binding restores it. After 105 warm-up cycles and the kernel's grace period for deferred frees, 100 more unbind/bind cycles may leave at most 30 more live kernel heap objects (the allowance is the test program's own growing heap; one object lost per cycle would be 100) and no more large-allocation pages. `reset` shows as `resets: 1` in `health` with the device `bound` again; `remove` makes the device's directory disappear. |
| `ahci` | x86_64 | A 64 KiB pattern written to `/dev/sd0` at 1 MiB, synced and read back; the controller reset through its sysfs `reset`, `health` showing `resets: 1`; a second pattern at 2 MiB. After the machine is off, the controller finds both patterns in the disk image, and the image still starts with the bytes it was created with. |
| `iommu-intel`, `iommu-amd` | x86_64 | The machine has an Intel VT-d or an AMD-Vi unit (`-device intel-iommu`, or `-device amd-iommu,dma-remap=on` -- QEMU's AMD unit translates nothing without the option) and is booted with `vinix.iommu=1`. The unit must be on; the e1000 and the AHCI controller must each report a domain of their own (`domain: dmar0 isolated`); the network must work, shown by a read from QEMU's built-in TFTP server, which needs nothing outside QEMU; a pattern must go to the disk and come back; twenty unbind/bind cycles of the card must leave it isolated and working; and the unit must have recorded no fault. |
| `iommu-off` | x86_64 | The same machine without `vinix.iommu=1`: no unit is listed, both devices report `domain: direct`, and network and disk work. |
| `iommu-intel-selftest`, `iommu-amd-selftest` | x86_64 | Need a kernel built with `-d vtd_selftest` or `-d amdvi_selftest`. At boot that kernel makes a card try what the plain scenarios cannot show: DMA to a page outside its domain, which must fault, name the card, and leave the page intact; the same page once mapped, which must be reached; and once unmapped, not. The scenario reads the verdict from the unit's `selftest` file. |
| `cpu-power` | aarch64, x86_64 | Every CPU has its idle states in `/sys`; each CPU's `usage` and `time` grow across an idle second, and the busiest still waited at least half of it; a state switched off through `disable` is not entered until it is switched on again; 1,600 timed sleeps, 2,000 pipe round trips and two computing threads all finish with the right totals, which a lost wake-up would prevent; and a machine with no frequency control says `none` and refuses a governor and a profile. |
| `cpu-power-simulated` | aarch64, x86_64 | Booted with `vinix.cpufreq=simulate`, a frequency driver with memory in place of registers: `performance`, `powersave` and a profile each reach every CPU's own register write. |
| `thermal` | aarch64, x86_64 | A machine with no sensors has no zones, a limit of 100 and no polling thread. On x86-64, a model-specific register that does not exist fails cleanly when read, here and on another CPU, instead of faulting. |
| `thermal-selftest` | aarch64, x86_64 | Needs a kernel built with `-d thermal_selftest`, which has a zone whose temperature the guest sets. Heating past the passive trip lowers the limit on CPU performance ten points per rising reading (90, 80, 70, 60); a steady reading costs nothing more; cooling gives it back; the hot trip drops it to 10 at once; a sensor that stops answering disables the zone and leaves the limit alone. The guest then reports and takes the zone past its critical trip, and the kernel must turn the machine off by itself. |
| `firmware` | aarch64, x86_64 | The firmware loader, driven through `/sys/firmware/loader`: a 100 KiB image under `/lib/firmware` is read whole and unchanged (name, size, checksum and holder count in `loaded`); keeping it twice changes nothing; a copy under `updates/` is the one read; names that leave the directory, are absolute, have an empty component or an odd character are refused, as are an image that is not there, a link to a device, and one over the 64 MiB limit; fifty load/drop cycles leave the kernel heap's live objects and large pages where they were. |
| `acpi-power` | x86_64 | QEMU's PC has no battery, charger or lid, so the controller writes an ACPI table describing all three (`hwhost/acpi_bench.v`, assembled by `hwhost/aml.v`) and QEMU loads it with `-acpitable`. They act out a script, advanced each time the battery is asked for its state: charging, the charger pulled, a steady 12 W drain to 2%, the lid shut and opened on the way. The guest checks what the battery is (capacities, voltage, chemistry, maker, cycle count), `Charging` with the charger online then `Discharging` with it offline, a charge that only falls, `time_to_empty_now` within 2% of charge over rate, a sleep when the lid shuts (ended by the wake alarm), `capacity_level` `Low`, and finally the request to power off that a critical battery makes of init -- which one reading that says "critical" with most of the charge left, given once on the way down, must not bring about. |
| `acpi-thermal` | x86_64 | The controller writes a table with a thermal zone and four fans (`hwhost/thermal_bench.v`): one fan that takes any level, one that takes the levels it lists, one switched by its own `_PS0`/`_PS3` and one by a power resource. The zone's temperature follows a script as the kernel reads it -- 40, then one reading that is no temperature at all and one of 105 that is gone when the kernel looks again (neither may switch the machine off, and the kernel must count them for what they were), then 40, 55, 75, 85, 60, 40 and finally 105 degrees for good, against active trips at 50 and 70, a passive trip at 80 and a critical one at 100 -- and it stays at 75 until both switched fans really run, and does not leave the last 40 while either still does. The guest, which never reads the temperature, must see in order: every fan off; the two with levels at half (level 50, and 60 as the nearest listed level, read back as 2000 and 2400 rpm); every fan flat out; the limit on CPU performance below 100 with the fans still flat out; half again with the switched fans off; everything off and the limit back at 100. It then reports, the script passes the critical trip, and the kernel must turn the machine off by itself. |
| `acpi-ec-absent` | x86_64 | An ordinary kernel and a table (`ec-absent` in `hwhost/acpi_bench.v`) that describes an embedded controller at ports 0x62 and 0x66, where QEMU has nothing and every read is 0xff, with two batteries, a charger, a lid and a thermal zone whose methods read it. The kernel must find the controller (its ports, its `_UID`, and a `_GPE` given as a package that names a block of events this kernel does not drive, so `events` says `polled`); give it up after one exchange (`failed` 1, `failure` `output buffer would not empty`) and mark the device `failed`; and go on. The battery that shows itself without asking the controller is listed, not present, and `Unknown`; the battery and the thermal zone that ask the controller are not taken on; no read in `/sys` takes half a second; writing 1 to the device's `reset` tries exactly one more exchange and leaves it failed; and the machine powers off. |
| `acpi-ec-off` | x86_64 | The same table with `vinix.ec=off`: there is no controller device and no `ec` driver, and the battery never shows itself, because `_REG` never ran. |
| `acpi-ec-selftest`, `acpi-ec-selftest-dsdt` | x86_64 | Need a kernel built with `-d acpiec_selftest`, in which a simulated controller answers in place of the two ports; see [below](#the-embedded-controller-self-test). |
| `suspend-deep-ec` | x86_64 | Needs the same kernel (`-d acpiec_selftest`) and uses `acpi-ec-selftest`'s machine and tables. The chipset's event reaches the driver before any sleep; then, after a suspend to RAM ended by the alarm, a value set in the simulated controller is read through `/sys/class/power_supply` with no exchange timing out, and an event the chipset raises (the host adds a processor) is heard -- its enable bit went with the power, and only the way back from S3 sets it again. A second sleep, with `power/wakeup` of the device `disabled`, must leave a lid that shut for it found on resume by exactly one query, and the chipset's event heard once more afterwards. The simulated controller must have seen no breach of the protocol. The controller is the kernel's own memory and loses no power: this is about the chipset's general purpose events and the driver's suspend and resume across S3, not about a controller. |
| `qmp-powerdown` | aarch64, x86_64 | The guest waits, with no handler for the power-off request; the controller sends `system_powerdown`; the kernel powers the machine off within 30 s. |
| `power-button-init` | aarch64, x86_64 | The guest is an init that handles the power-off request (`SIGUSR2`). The controller sends `system_powerdown`; the press must reach init as that signal instead of turning the machine off under it, and init then powers off. |
| `restart` | aarch64, x86_64 | `reboot(2)` with the restart command resets the machine: QEMU's `SHUTDOWN` event must say `guest-reset`. |
| `suspend` | aarch64, x86_64 | Suspend to idle through `/sys/power/state`: a rehearsal (`pm_test` = `devices`) that suspends and resumes every device; a sleep ended by the wake alarm after 2 s, during which a counting thread of the guest must stand still; a sleep ended by a key the controller sends; a sleep ended by the power button, which must wake the machine and not turn it off; and a sleep with the keyboard not allowed to wake, where the key is ignored and the alarm ends it after 3 s. After each, `suspend_stats` must name the right wake source; at the end it must show five successes, no failure, and five comparisons of the CPU's protection registers with no change. |
| `screen-sleep` | aarch64, x86_64 | The controller takes a picture of the screen (QMP `screendump`) at five moments and judges them once the machine has ended: before a sleep the console's text must be on it; a second and a half into a four-second sleep ended by the alarm every pixel must be black; after the sleep the text must be back; in the middle of a rehearsal (`pm_test` = `devices`) it must be black again, and lit after it. The guest checks that `suspend_stats/screen_dark` counted the sleep and the rehearsal and that `screen_lit` stayed 0. |
| `pci-hotplug` | aarch64, x86_64 | The machine boots with an empty PCI Express port, which the kernel watches itself, and no network card. The port's slot must be in `/sys/bus/pci/slots`, `empty`, without power or a card. The controller adds an e1000 behind the port (`device_add`): it must appear as `0000:01:00.0`, bound to the e1000 driver, with an address inside the port's memory window, decoding it and allowed to master the bus, the slot `occupied` with power; and the network must work through it (the TFTP read). Then 105 warm-up and 100 measured cycles of removing the card through its `remove` file and finding it again by a rescan, which may leave at most 30 more live heap objects and no more large pages, the network still working afterwards. The controller asks for the card back (`device_del`, which presses the slot's button): within the button's five seconds and the removal the card must be gone and the slot `empty`. Both steps are then repeated, the second card taking the first one's place. QEMU must have reported `DEVICE_DELETED` twice: it lets go of a card only when the guest has cut the slot's power. On x86-64 the machine is started with `-global ICH9-LPC.acpi-pci-hotplug-with-bridge-support=off`, without which QEMU's firmware keeps its ports. |
| `pci-hotplug-acpi` | x86_64 | The same machine as QEMU makes it by default: firmware keeps the ports, refuses to hand them over through `_OSC`, and announces the card and asks for it back with ACPI notifications. No slot may be listed; everything else holds as in `pci-hotplug`, and `DEVICE_DELETED` twice here means the kernel evaluated `_EJ0` after letting go of the card. |
| `pci-hotplug-iommu` | x86_64 | `pci-hotplug-acpi` on a machine with an Intel IOMMU and `vinix.iommu=1`: the card that arrives must report a domain of its own (`isolated` in its `dma` file) each time it is found, the network must work through it, and at the end the unit must have recorded no fault. |
| `pci-d3` | aarch64, x86_64 | The network card is an Intel 82574L (`e1000e`), which has a power management capability QEMU acts on: in D3hot its registers are taken out of the machine's memory map. The guest goes through a rehearsal and a suspend to idle, six seconds each, and three seconds into each the controller asks QEMU for the memory map as it is laid out (`info mtree -f`): the card's registers must not be in it, and before and after each sleep they must be. After each sleep the card must say it is in D0 (`power_state`), have one more sleep in `power/d3_count`, be bound, and bring a TFTP block back; `/sys/power/pci_d3` must show one function put down, none refused and none stuck. On x86_64 a suspend to RAM follows, entered with the card in D3hot. Then 40 rehearsals are measured: the kernel's live heap objects must not have grown. QEMU's card forgets nothing in D3hot, so the kernel must find no register changed. |
| `pci-d3-off` | aarch64, x86_64 | The same machine with `vinix.pci_d3=off`: three seconds into a rehearsal the card's registers must still be in QEMU's memory map, nothing is counted as put down, and the card works afterwards. It is also what shows that the controller's look in `pci-d3` tells the two apart. |
| `pci-d3-selftest` | aarch64, x86_64 | Needs a kernel built with `-d pci_d3_selftest`, which clears the card's address registers, command register and interrupt line once it is in D3hot -- what a card that keeps nothing across D3hot has lost by the time it is back. Everything `pci-d3` checks, and the kernel must report registers found changed and written back after each sleep. With the writing back taken out of the kernel the card brings nothing back and the scenario fails. |
| `suspend-deep` | x86_64 | Suspend to RAM (ACPI S3) on a machine with four CPUs, a SATA disk, an e1000 and QEMU's standard VGA. `mem_sleep` offers `deep` and selecting it sticks. Two rehearsals (`pm_test` = `platform`) go the whole way down and back without asking firmware: one undisturbed, which counts as a rehearsal that worked; one during which the controller presses a key, which must be counted as a failed sleep (`last_failed_step` `platform`, a wake source as the reason). Then three sleeps, ended by QEMU's `system_wakeup` (sent only once QEMU has reported `SUSPEND`; QEMU's ACPI shows it as the power button), by the clock's alarm, and by a key. After each: a thread pinned to every CPU runs there and `/proc/stat` bills that CPU for it; 32 MiB of memory is word for word what was written; a pattern written to the disk before reads back, a megabyte of disk the controller filled and nothing had read reads as filled, and a new pattern goes out and comes back; a file comes from QEMU's TFTP server; the monotonic clock did not go back and did not count the time the machine was away, which was added to the wall clock alone, in whole seconds, and is in `last_sleep_ms`; the wall clock moved on by at least the time asleep less a second; the sleep was not billed to the program as processor time; a counting thread stood still; the rounding mode the thread set is still set; what was drawn on the screen is in the framebuffer; `suspend_stats` names the right wake source, counts the sleep as `deep`, and shows the protection registers compared on all four CPUs with no change; and `/sys/power/deep_sleep` shows that the way back found PCI registers and interrupt routes to write back and the display off, which is what says power was lost. After three sleeps a line typed on the keyboard reaches the console and the mouse moves the pointer. Five more sleeps follow one after another, ended by the alarm, and may leave at most 30 more live kernel heap objects (measurement noise; one object lost per sleep with what each sleep allocates would show) and no more large pages. At the end the power button still reaches init. On the host: QEMU must have reported `SUSPEND` and `WAKEUP` eight times each; a picture of the screen taken with `screendump` while QEMU has the machine suspended must be dark; pictures taken before the first sleep, straight after the first wake and after the last must each show the guest's pattern, pixel for pixel, in the same mode; and the patterns written after each resume must be in the disk image. |
| `suspend-deep-bridge` | x86_64 | The same with the network card behind a PCI Express port whose hot-plug slot the kernel watches (`pci-hotplug`'s machine with the card in the port from the start). The bridge's bus numbers and windows must be back before the card can be reached, so the network working after each sleep says they were; and after every sleep the slot must be `occupied`, with its adapter and power reported, and must have counted no arrival, departure or failure. For a card that comes or goes during the sleep see the next two. |
| `suspend-deep-arrival` | x86_64 | `pci-hotplug`'s machine with two CPUs: the kernel watches the port, and its slot is empty. Once QEMU has reported `SUSPEND` the controller adds an e1000 behind the port, and two seconds later wakes the machine. Nothing tells the kernel: the port's record of the change went with its power. After the wake the card must be listed, bound to `e1000`, given an address inside the port's window, and carry a TFTP transfer; the slot must be `occupied` with one arrival counted. The machine then sleeps again with the card in (ended by the alarm) and the card, its addresses and the network must be as before, with no function left unrestored. Last, asked for through QMP, the card must go as in `pci-hotplug` (`DEVICE_DELETED`), which says the port's slot interrupt and power switch were given back. A picture of the screen after the sleeps must show something. Run against a kernel that writes a slot's saved power setting back regardless, it fails: QEMU takes the card off the bus when an occupied slot is switched off. |
| `suspend-deep-departure` | x86_64 | The same port kept by firmware (QEMU's default), with the card in it from boot. During the first sleep the controller asks for the card back; with no system running to agree, QEMU takes it when the machine wakes. The kernel must find one function changed (`pci functions not restored` 1), must not name any device as having failed to resume, and within five seconds must have removed the card from `/sys` and from its driver. During the second sleep the controller puts a card in, of which firmware never sends a notice; after the wake it must be found, addressed, bound and carry traffic. A third sleep with it in must leave it working. QEMU must have reported three `SUSPEND`s, three `WAKEUP`s and `DEVICE_DELETED`. Run against a kernel without the scan after a sleep, the second card is never found. What is not tried: a card pulled from, or exchanged in, a slot the kernel watches (QEMU takes a card out of such a slot only with the guest's help). |
| `suspend-deep-xapic` | x86_64 | The same on processors without x2APIC (`-cpu max,-x2apic`), where the local APICs are driven through memory and INIT and the startup IPI go through the two halves of the command register. |
| `suspend-deep-iommu`, `suspend-deep-iommu-amd` | x86_64 | The same behind Intel VT-d and behind AMD-Vi, booted with `vinix.iommu=1`. In addition the unit must say in its own registers that it is translating through the kernel's tables after every sleep, having been found off on the way back each time; the card and the disk controller must still report a domain of their own; and the unit must have recorded no fault. That a device is *stopped* from reaching other memory after a resume is not shown here: the self-tests that make a card try run at boot only. |
| `suspend-deep-undrawable` | x86_64 | A machine whose screen is on an adapter the kernel cannot set a mode on (QEMU's VirtIO display): `mem_sleep` lists `s2idle` alone, selecting `deep` is refused, `/sys/power/deep_sleep` says the display is why, and `mem` sleeps as suspend to idle. |
| `suspend-deep-forced`, `suspend-deep-headless` | x86_64 | The same machine with `vinix.deep_sleep=force`, and a machine with no display at all: `deep` is offered, and one suspend to RAM ended by the alarm comes back with QEMU reporting `SUSPEND` and `WAKEUP`. |
| `drivers-sleep` | x86_64 | A machine with an HD Audio controller, whose output QEMU records to a WAV file, and a PCI IDE controller with a disk. A thread of the guest plays a square wave the whole time and the main thread changes its height after each of three sleeps -- a rehearsal, a suspend to idle ended by the alarm, a suspend to RAM ended by the alarm -- each begun with the tone playing; after each the player must go on handing sound to the card, and the disk must hold what was written before the sleep and take a new write. The machine must offer `deep`, which it did not while either driver could not bring its device back. Afterwards the controller looks for the four heights in the recording, a third of a second and a half of each, and for the four patterns in the disk image, and QEMU must have reported `SUSPEND` and `WAKEUP`. QEMU's codec keeps its settings through a controller reset, so this shows the controller, its rings and its stream coming back and not that the codec was programmed again. |
| `nvme-sleep` | x86_64 | Needs a kernel built with `PROD=false`: a release kernel does not start the NVMe driver. An NVMe disk through the same three sleeps: before each the controller is flushed and told to shut down, after each it is disabled, enabled and its queues created again; what was written before must be there and a new write must reach the disk image. QEMU's controller has a power management capability, so it must also have spent each of the three sleeps in D3hot. |

Every scenario also fails on a line containing `KERNEL PANIC`,
`FATAL EXCEPTION` or `HWTEST FAIL`, and a scenario whose machine is to power
off passes only if QEMU's `SHUTDOWN` event says the guest shut it down: a
reset makes QEMU exit as well (it runs with `-no-reboot`) and is not a
power-off. A scenario can also name QMP events QEMU must have sent before
the machine ended (`events` in the table; one named twice must have arrived
twice): what the guest prints is its own account, and an event is the
machine's. In the same way a scenario can name pictures of the screen
(`screens`) and recordings of what the machine played (`sounds`: QEMU writes
them with `-audiodev wav`, and a tone of a height nothing else produces is
looked for in them).

A scenario can be marked pending: one the kernel of the branch cannot pass
yet. A default run skips it and says so; naming it with `--scenario` runs it.
None is pending today. `qmp-powerdown` was while the kernel ignored the power
button, and its other purpose still holds: it takes a host action through the
whole path -- a marker from the guest, a QMP command from the host, an
expectation with its own deadline -- and `qmp.log` of a run shows the
conversation.

Each scenario prints one line, `PASS <arch> <scenario> (<seconds>s)` or
`FAIL ...`, followed by what the guest measured (its `HWTEST INFO` lines) and,
for a failure, the reason, the last 40 serial lines and where the logs are.
The last line is a summary. The exit status is 0 when every selected scenario
passed, 1 when one failed, 2 when the run could not start, and 130 when it
was interrupted.

```
PASS aarch64 devices (21.1s)
  3 PCI devices in sysfs
  100 unbind/bind cycles: live heap objects 2377 -> 2380, large pages 58 -> 58, MemFree -112 kB
PASS aarch64 qmp-powerdown (6.5s)
PASS aarch64 power-button-init (6.6s)
PASS aarch64 restart (6.5s)
PASS aarch64 suspend (17.4s)
  rehearsal: 550 ms, devices down in 50 ms, back in 0 ms
  frozen: 1990 counts in 2000 ms asleep, 50391137 per 300 ms awake
  key: woke after 1594 ms
  power button: woke after 1763 ms
hardware-platform aarch64: 5 passed, 0 failed, 0 skipped
```

The unit tests of the controller need no machine:

```sh
~/code/v/v -cc cc test tests/hardware-platform/hwhost
```

### What a run needs

- A V compiler: the launcher picks it as kernel builds do
  (`build-support/find-v.sh`; `V` or `VINIX_V_COMPILER` override it).
- QEMU with its edk2 firmware, found in `share/qemu` beside the binary.
  `VINIX_QEMU_AARCH64` and `VINIX_QEMU_X86_64` name the binaries,
  `VINIX_OVMF_CODE_AARCH64`, `VINIX_OVMF_CODE_X86_64` and
  `VINIX_OVMF_VARS_AARCH64` the firmware files.
- For AArch64: clang and lld with the musl sysroot
  (`build-aarch64-userland/sysroot`, or `VINIX_AARCH64_SYSROOT`;
  `CC_AARCH64` names the compiler), mtools, and Limine's `BOOTAA64.EFI`
  (`boot-image/limine-bin`, or `VINIX_LIMINE_BOOTAA64`).
- For x86-64: a musl cross compiler (`x86_64-linux-musl-gcc`, or `CC_AMD64`)
  and what `build-support/build-amd64-iso.sh` needs (bash, cc, curl,
  xorriso). That script downloads Limine once, into
  `build-amd64-iso/limine`; `VINIX_AMD64_LIMINE_DIR` names another copy.

In a git worktree the sysroot, the boot loader and the Limine download are
taken from the main checkout when the worktree has none of its own.
`VINIX_ROOT` names the checkout if the controller is run from elsewhere.

An AArch64 guest runs under HVF on Apple silicon and under TCG elsewhere;
`VINIX_HWTEST_TCG=1` asks for TCG on a Mac too. An x86-64 guest always runs
under TCG.

### State, logs and disk space

Without `--state-dir` a run works in one directory per architecture,
`<temporary directory>/vinix-hwtest/<arch>`, which the next run empties and
uses again. The images of a scenario (boot volume or ISO, initramfs, test
disks: about 80 MiB on disk for AArch64 and 25 MiB for x86-64) are deleted
as soon as its machine has ended; the logs stay until the next run. A second
run for the same architecture is refused while the first is alive.

With `--state-dir DIR` -- which must be empty or not exist -- nothing is
deleted: `DIR/guest` holds the guest program and each `DIR/<scenario>` has

- `serial.log`: the serial port, as QEMU wrote it;
- `qmp.log`: every QMP line in either direction, with the time since QEMU
  started;
- `qemu.log`: QEMU's command line, then what it printed;
- `image.log`: the output of the tools that built the boot medium;
- the images themselves.

QEMU is stopped (SIGTERM, then SIGKILL after five seconds) and collected
after every scenario, whether it passed, failed, timed out, or the controller
was interrupted with Ctrl-C, SIGTERM or SIGHUP. A controller that is killed
outright (SIGKILL) cannot do that; its QEMU is the one found by
`pgrep -fl 'qemu-system.*<state directory>'`.

## How a scenario is judged

The guest is `/sbin/init` of an initramfs that holds nothing else but
`/etc/hwtest-scenario`, the name of the scenario to run. It prints:

```
HWTEST START <scenario>             the scenario began
HWTEST STEP <text>                  a point the host may act on
HWTEST INFO <text>                  something measured, for the report
HWTEST FAIL <scenario>: <message>   a check did not hold
HWTEST PASS <scenario>              every check held
HWTEST FAIL <scenario>              at least one did not
```

and then powers the machine off. The controller polls the serial log, splits
it into lines, removes escape sequences and carriage returns, and looks for
its markers in whole lines only. A scenario's record in
`hwhost/scenario.v` says which lines are required, which are forbidden, what
to send over QMP when a given line appears -- and, for a machine that has to
be suspended first, once QEMU has reported that it is -- which QMP events
must have been seen, and how the machine is to end:
`poweroff` (by itself, before the timeout) or `running` (the controller stops
it once every marker has been seen).

## Adding a scenario

1. The guest half: a new file in `guest/` with
   `fn scenario_<name>(mut t Test)`. `guest/support.v` has what it is written
   with: `t.check(condition, message)`, `t.step(text)`, `t.info(text)`,
   `read_text`, `read_word`, `write_text`, `list_dir`, `wait_until`,
   `write_pattern`. Return when done; `t.stay_up()` first if the machine is
   to be left running.
2. One line in `run_scenario()` in `guest/main.v`, mapping the name to the
   function.
3. One record in `scenarios` in `hwhost/scenario.v`: name, architectures,
   extra kernel command line and QEMU arguments (`{state}` is the scenario's
   state directory), disks to create and what to fill them with, required
   and forbidden markers, actions, the expected ending, and patterns to look
   for on a disk afterwards. An action can wait for QEMU to have reported an
   event a number of times as well as for its marker (`event`,
   `event_count`, `event_delay_ms`): a machine can only be woken once QEMU
   says it is suspended. An action can also hold QEMU to its answer
   (`answer_has`, `answer_lacks`), which is how the host reads something
   out of the machine instead of doing something to it. A scenario can name
   the events that must have arrived (`events`), list pictures of the screen
   its actions took with `screendump` and what each must show (`screens`:
   dark, or something; the size of another picture; the pattern a guest
   draws with `guest/framebuffer.v`), and ask for more than the default time
   (`timeout`). A record that cannot pass yet gets a `pending` reason.

The table is checked before anything boots (`validate_scenarios`), and
`hwhost/scenario_test.v` pins which scenarios a default run selects on each
architecture: add the new name there.

## What a pass means, and what it does not

A pass is a statement about one kernel binary in one QEMU machine: `virt`
with GICv3 under HVF or TCG for AArch64, `q35` under TCG for x86-64, with
QEMU's models of an 82540EM network card and an ICH9 AHCI controller. It
says the kernel's device core, drivers and power paths behave as the
scenario requires against those models.

It says nothing about physical hardware. An emulated e1000 has no PHY to
lose its link, an emulated disk never times out, and an HVF or TCG processor
has neither the timing nor the firmware of a real board. Nothing here has
been run on an Apple silicon machine booted natively or on a PC.

A pass of a `suspend-deep` scenario says that QEMU suspended the machine,
reset its processors and devices when it was woken, and that OVMF, resuming
from S3, handed the boot processor to the kernel's waking vector with
memory intact; and that the kernel then put back everything the scenario
looks at. What QEMU's wake-up does to a device is a reset, which is not
everything a loss of power does to a real one, and OVMF's is one firmware's
way back among many. A PS/2 key and `system_wakeup` wake this machine
whatever the kernel has armed; on hardware a device wakes a machine only if
its wake event was enabled, which the kernel does for the embedded
controller's event alone and for no device's `_PRW`.

Two further limits:

- An x86-64 kernel built for production prints nothing on the serial port,
  so a panic there appears as a timeout with the marker that is missing,
  not as `KERNEL PANIC`.
- On AArch64 the kernel's messages and the guest's lines share one serial
  port byte by byte. The guest waits a moment before its verdict so that a
  driver's message does not land inside it; a line the kernel did interleave
  is not matched, and the scenario fails with that line shown.

## Scenarios that need a kernel built for them

Three scenarios read the verdict of a self-test compiled into the kernel, and
two more need a kernel with a simulated embedded controller in it (the next
section). All are left out of a default run with the reason. Build such a kernel beside the
ordinary one and name the scenario:

```sh
# x86-64: all three self-tests in one kernel
mkdir -p build-amd64-selftest/obj
rsync -a --delete --exclude /bin/ --exclude /obj/ --exclude /cc-runtime-x86_64/ \
    --exclude /cc-runtime-aarch64/ kernel/ build-amd64-selftest/
make -C build-amd64-selftest ARCH=x86_64 CC=clang AR=llvm-ar LD_X86_64="$(command -v ld.lld)" V="$V" \
    "VFLAGS=-d thermal_selftest -d vtd_selftest -d amdvi_selftest" -j8
tests/hardware-platform/run --arch x86_64 --kernel build-amd64-selftest/bin/vinix \
    --scenario thermal-selftest --scenario iommu-intel-selftest --scenario iommu-amd-selftest

# AArch64
mkdir -p build-aarch64-selftest/obj
rsync -a --delete --exclude /bin/ --exclude /obj/ --exclude /cc-runtime-x86_64/ kernel/ build-aarch64-selftest/
make -C build-aarch64-selftest ARCH=aarch64 CC=clang LIMINE_MP=1 V="$V" "VFLAGS=-d thermal_selftest" -j8
tests/hardware-platform/run --arch aarch64 --kernel build-aarch64-selftest/bin/vinix --scenario thermal-selftest
```

```
PASS x86_64 thermal-selftest (23.1s)
  heating gave limits [90, 80, 70, 60]; hot gave 10; a failed sensor held 90
PASS x86_64 iommu-intel-selftest (14.4s)
  dmar0 result: PASS
  dmar0 checks: 25
PASS x86_64 iommu-amd-selftest (14.9s)
  ivhd0 result: PASS
PASS aarch64 thermal-selftest (20.9s)
  heating gave limits [90, 80, 70, 60]; hot gave 10; a failed sensor held 90
```

### The embedded controller self-test

No machine QEMU has an embedded controller, so what stands in for one is
stated here exactly.

A kernel built with `-d acpiec_selftest` never reads or writes the
controller's two ports. The simulated controller of
`kernel/x86/acpiec/sim_d_acpiec_selftest.v` -- 256 bytes of memory, the read,
write and query commands, a queue of events -- answers instead, on the real
clock. Everything above the two port instructions is the code an ordinary
kernel runs: uACPI's region handler, the lock and the global lock, the
exchanges and their timeouts, the queries, the methods. The controller is
described to the kernel by tables the host writes (`ec-bench` in
`hwhost/acpi_bench.v`, and an ECDT): a `PNP0C09` device with `_CRS`, `_GPE`,
`_GLK` 1, `_REG`, an EmbeddedControl region with byte, word and four-byte
fields, `_Q20` to `_Q24`, and a battery, a charger and a lid whose methods
read the fields. The guest sets the controller's memory, queues its events
and makes it misbehave through `/sys/bus/acpi/devices/PNP0C09:00/ec/selftest`.

**Who raises the general purpose event.** For three events (the steps
`controller event 1` to `3`) the host adds a processor to the running machine
over QMP, which makes QEMU's emulated chipset set general purpose event 2 and
raise the SCI; the tables give the controller that event, so the interrupt,
uACPI's dispatch and the driver's handler run as they would for a controller's
own line. The added processor is never started. For every other event the
self-test calls the driver's handler itself (`raise`, `later`, `storm`). In no
case does a controller raise anything: there is none.

`acpi-ec-selftest` (with an ECDT) checks:

- what was found: ports, `source` `ECDT and namespace`, `_UID`, the event,
  `events` `gpe`, `global_lock` 1; and what was read while booting -- the
  battery's state, charge, capacities, voltage and rate, the charger and the
  lid, with the design voltage read while the table loaded and the cycle
  count read in an `_INI`, which only an early handler makes possible;
- a value with no event: memory, field, method, `/sys/class/power_supply`;
- three events raised by the chipset: a Notify that has the battery's
  capacities read again, and the lid shut and opened, with `gpe_count`,
  `queries` and `methods` each one higher every time -- so the event is
  switched on, and on again after each;
- fields a word and four bytes wide read and written by a method; two events
  behind one raise both taken; an event firmware has no method for counted;
- sleep: the lid shuts, the machine sleeps, the lid opens 2.5 s later and
  wakes it, attributed to `lid`; an event nothing claims does not end a sleep
  and does once the `embedded-controller` source is enabled; with the
  device's `power/wakeup` disabled the event is held until resume;
- 300 events, each with a battery read, leave the kernel heap's live objects
  where they were;
- 150 reads of the battery while a second thread sends the reader signals
  all return an answer;
- a byte left in the output buffer is not an answer; a controller that never
  runs out of events is asked 32 times; an event bit stuck up is asked about
  once; a line raised 66 times at once is switched off and the event bit
  polled, which still finds the lid;
- a controller that stops answering: the battery read takes the two
  exchanges' five seconds, the charger's the third exchange's two and a half,
  then `failed` is 1, every read answers within half a second with `Unknown`,
  and the device is `failed`; made to answer again and `reset`, it is in use
  again;
- and that the simulated controller saw no breach of the protocol.

`acpi-ec-selftest-dsdt` is the same with no ECDT (`source` `namespace`) and
`vinix.ec=clear,dsdt-gpe`: the controller must be queried once at start and
once after each of four sleeps whatever its event bit says.

```sh
mkdir -p build-amd64-selftest/obj
rsync -a --delete --exclude /bin/ --exclude /obj/ --exclude /cc-runtime-x86_64/ \
    --exclude /cc-runtime-aarch64/ kernel/ build-amd64-selftest/
make -C build-amd64-selftest ARCH=x86_64 CC=clang AR=llvm-ar LD_X86_64="$(command -v ld.lld)" V="$V" \
    "VFLAGS=-d acpiec_selftest" -j8
tests/hardware-platform/run --arch x86_64 --kernel build-amd64-selftest/bin/vinix \
    --scenario acpi-ec-selftest --scenario acpi-ec-selftest-dsdt
```

```
PASS x86_64 acpi-ec-selftest (51.6s)
  boot: init 191 ms after the clock started, 36 exchanges, source ECDT and namespace
  events raised by the chipset: 3, queries 3, methods 3
  lid: shut, slept 2446 ms, woken by lid
  unclaimed event: ignored asleep, then ended a sleep after 1008 ms once allowed
  300 events and 3736 exchanges: live heap objects 8018 -> 8021, large pages 157 -> 157
  under signals: 150 reads of the battery, 0 without an answer, 45 signals taken
  the global lock was given up on 6 times while the controller was silent
  silent: battery read 5041 ms, then at most 60 ms a read; device failed
  in all: 5776 exchanges, 508 events, 3 timeouts, 1 stale bytes, protocol violations 0
PASS x86_64 acpi-ec-selftest-dsdt (51.2s)
  boot: init 193 ms after the clock started, 37 exchanges, source namespace
  ...
PASS x86_64 acpi-ec-absent (8.7s)
  init 271 ms after the clock started; slowest read 17 ms; 2 exchanges, 2 failed, 14 callers turned away; reset took under 503 ms
```

What these do not show: anything about a real controller. The simulated one
is this repository's reading of the specification; a pass says the kernel
agrees with that reading from the region handler down to the port functions,
and that ports with nothing behind them do it no harm. The protocol's own
tests, on the host with a simulated clock, are `sh tests/acpi-ec/run.sh`.
A scenario that needs longer than a run's `--timeout` says so in its record
(`timeout`); these two take about 50 s of a 240 s allowance.
