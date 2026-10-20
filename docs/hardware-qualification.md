# Hardware qualification matrix

Which machines Vinix runs on, what on each of them works, and on what
evidence. It is the published matrix roadmap workstream 4 asks for, and it
follows the roadmap's rules:

- A capability is `open` (nothing there), `partial` (some of it), `implemented`
  (written and tested in a way that is named) or `qualified`.
- **Only a completed [physical checklist](#the-physical-checklist) on the
  machine itself makes something `qualified`.** A host unit test, a virtual
  machine and a physical machine are different evidence and are kept apart
  here: `host`, `VM` and `physical`.
- A row is about the machine named, not about a family. "Works on the M1 Air"
  says nothing about an M1 Mac mini.

As of 2026-10-11 **no machine is qualified for anything**: no checklist has
been completed and recorded. The repository's own documents say of every
hardware driver that it has not been validated on the machine it is for; this
matrix does not improve on what they record.

## Machines

| Class | Machine | How it boots | State | Evidence |
| --- | --- | --- | --- | --- |
| x86-64 VM | QEMU `q35`, UEFI (OVMF) or BIOS, 2-4 CPUs | Limine from the ISO | implemented | VM: [hardware-platform](../tests/hardware-platform/README.md) on QEMU 11.1.1 (TCG); the release ISO checks in `scripts/test-iso.sh` |
| x86-64 VM | QEMU `pc` (i440fx), BIOS, 1 CPU | Limine from the ISO | implemented | VM: `scripts/test-iso.sh` only; none of the power or device scenarios |
| x86-64 VM | VirtualBox, BIOS, SATA | ISO | implemented | VM: `scripts/test-iso.sh --virtualbox` in CI; none of the power or device scenarios |
| AArch64 VM | QEMU `virt`, GICv3, UEFI (EDK2), 4 CPUs | Limine from a FAT disk | implemented | VM: hardware-platform on QEMU 11.1.1 (HVF) |
| AArch64 VM | VirtualBox, EFI | ISO | partial | VM: boots from memory; "Vinix has no driver for the disk controllers VirtualBox gives an arm64 VM" (README) |
| Intel PC | none named | -- | open | none. A Tiger Lake Core i5-1135G7 laptop is the i915 work's target ([linux-i915](linux-i915.md)); no boot of it is recorded |
| AMD PC | none named | -- | open | none |
| Apple M1 | MacBook Air (J313, t8103) | m1n1, U-Boot, UEFI, Limine | partial | physical target of the installer and of every Apple driver; no completed checklist. Each driver's document says it has not been validated on the machine |
| Apple M1 | Mac mini (J274), MacBook Pro 13 (J293), iMac (J456, J457) | the same | open | none. The installer accepts any base M1 by its brand string, but Wi-Fi and speakers match J313 only, and no boot of these is recorded |
| Apple M1 Pro/Max, M2-M4 | -- | -- | open | refused by the installer |
| Apple M5 Max (t6050) | Mac17,6 | `apple-boot` | open | host and emulator work only ([apple-boot](../apple-boot/README.md)); one CPU, no keyboard, no storage |

"AArch64 VM" and "x86-64 VM" are machines in their own right: for them the
checklist is run on the hypervisor product, and the scenarios above are part
of it, not all of it.

## Platform and power, by machine

State and evidence for the capabilities of [hardware-platform](hardware-platform.md).

| Capability | x86-64 VM (QEMU q35) | AArch64 VM (QEMU virt) | Intel / AMD PC | Apple M1 Air |
| --- | --- | --- | --- | --- |
| Device list, driver binding, `/sys` | implemented (VM) | implemented (VM) | implemented, untried | partial: PCI and the SMC (`apple-smc`, driver `macsmc`); Apple's other drivers are not listed |
| Unbind, remove, reset, failure recovery | implemented (VM: e1000, ahci) | implemented (VM: e1000) | untried | open |
| PCI hotplug, rescan | implemented (VM: a PCIe port the kernel polls, and a card announced by firmware through ACPI; e1000 only) | implemented (VM: a PCIe port the kernel polls; e1000 only) | untried | open: ports are not watched on Apple hardware |
| DMA domains | implemented (VM) | implemented (VM), no IOMMU | untried | open: Apple drivers program their DARTs themselves |
| IOMMU isolation | implemented (VM: VT-d and AMD-Vi, opt-in) | open (no SMMU driver) | untried; opt-in `vinix.iommu=1` | partial: DART per driver, not through `dma` |
| Firmware loader | implemented (VM) | implemented (VM) | untried | open: Wi-Fi firmware still comes from userspace |
| Power off, restart with devices stopped | implemented (VM) | implemented (VM) | untried | partial: restart through the watchdog untried; power off needs the SMC and ends halted |
| Power button | implemented (VM) | implemented (VM, polled) | untried | open |
| Embedded controller | implemented (VM: a simulated controller in a self-test kernel; an ordinary kernel only against ports nothing answers at) | -- (no ACPI on this kernel) | host: the protocol against a simulated controller; untried | -- (Apple's is the SMC) |
| Lid | implemented (VM: scripted ACPI lid, and one read through the simulated embedded controller) | open | untried; read through the embedded controller on most laptops, and that driver has met only a simulated one | open |
| Suspend to idle, wake sources, alarm | implemented (VM) | implemented (VM) | untried | open: untried, and the idle loop polls |
| Suspend to RAM | implemented (VM: ACPI S3 under OVMF with QEMU's standard VGA; e1000, AHCI, PS/2 and serial only; behind VT-d and AMD-Vi) | open (no platform sleep to ask for) | untried: no firmware's way back has been met, wake-up devices are not armed, and it is offered only where the display can be brought back or `vinix.deep_sleep=force` | open |
| Hibernation (suspend to disk) | implemented (VM: an image on a named SATA disk, the machine switched off and the image gone back into at the next start under OVMF; behind VT-d and AMD-Vi; with four- and five-level page tables; not encrypted) | open (no `disk` state) | untried: it needs two boots to have the same memory, firmware regions and ACPI tables at the same addresses, which no firmware has been asked; ACPI S4 is not used; opt-in `vinix.hibernate=<device>` | open |
| Screen sleep, backlight | partial (VM: the boot framebuffer is dark during a sleep; a backlight firmware sets -- ACPI `_BCM` -- is dimmed for a sleep and its keys work, against scripted panels only; no display power control, no backlight that needs the graphics driver) | partial (VM: the same) | untried | partial: brightness through DCP, opt-in ([M1 AGX](m1-agx-bringup.md)); the panel is not darkened for a sleep |
| Battery, charger, time left | implemented (VM: scripted ACPI battery, and one read through the simulated embedded controller) | implemented (VM: a simulated Apple SMC in a self-test kernel; the machine itself has no battery) | untried; read through the embedded controller on most laptops, and that driver has met only a simulated one | implemented (host, VM): status, the SMC's percentage and time estimates, charge, current, voltage and cycles in `/sys`, and the percentage and telemetry in `/dev`, against a simulated SMC ([M1 battery](m1-battery.md)); **no physical run** |
| Charge limit | open | implemented (VM: the simulated SMC's `CHWA`, 80 or 100) | open | implemented (host, VM) on firmware with `CHWA`, written only on request and read back; whether this machine's firmware has the key is not known; no physical run |
| CPU idle states | implemented (VM: HLT) | implemented (VM: WFI) | host: MWAIT tables; untried | open by default (polls); `vinix.apple_idle=wfi` untried |
| CPU frequency | implemented (VM: simulated driver) | implemented (VM: simulated driver) | host: HWP, SpeedStep, CPPC encodings; untried | host: cluster DVFS sequence; off by default, untried |
| Temperature, thermal limit | implemented (VM: made-up zone, and a scripted ACPI thermal zone) | implemented (VM: made-up zone, and a simulated Apple SMC's sensors) | host: coretemp, k10temp, RAPL decoding; ACPI thermal zones untried, and none has been read through an embedded controller, simulated or real | implemented (host, VM): four SMC temperatures in one zone with no trip points, shown and not acted on, against a simulated SMC; the SoC's own temperature is not among them; no physical run |
| Fans | implemented (VM: scripted ACPI fans of each kind, driven by a zone's active trips) | partial (VM: a simulated Apple SMC's fan, shown and not driven) | untried; a laptop's fans are usually its embedded controller's and not in ACPI | -- (this machine has none; the SMC's fans of an M1 with one are shown, not driven, and only a simulated one has been read) |

## Device families, by machine

What each reference machine class needs, and the driver that is or is not
there. "VM" evidence is a named test or the release ISO checks; where a
driver has none, that is said.

### x86-64 VM and PC

| Family | Device | Driver | State | Evidence and limits |
| --- | --- | --- | --- | --- |
| Storage | AHCI SATA | `dev/ahci` | implemented (VM) | hardware-platform `ahci`; [storage volumes](storage-volumes.md). Started when the image is to keep its system on a disk, or in a development kernel. No physical controller tried |
| Storage | NVMe | `dev/nvme` | partial | development kernels only: "the NVMe driver is not fit for a release kernel yet". Host mock tests; a guest attempt panicked ([storage volumes](storage-volumes.md)). This is the disk of nearly every current PC |
| Storage | IDE (PIIX) | `dev/ata` | implemented (VM) | ISO checks on QEMU `pc` and VirtualBox |
| Storage | USB mass storage, SD, eMMC | none | open | |
| Ethernet | Intel 8254x, 82574L | `dev/e1000` | implemented (VM) | hardware-platform `devices`, `iommu-*`; polled, one interface. These are the cards hypervisors emulate; no physical card tried |
| Ethernet | Realtek RTL8168G/GU, RTL8111G/GU (ThinkPad E470 R8111GUS) | `dev/rtl8169` | implemented (host fixture), physical unverified | V startup/firmware/DMA tests; [E470 diagnostics](thinkpad-e470-ethernet.md). One polled interface |
| Ethernet | Other Realtek revisions, Intel I219/I225, any other | none | open | |
| Wireless | any (Intel iwlwifi, Realtek, MediaTek) | none | open | |
| Bluetooth | any | none | open | |
| Graphics | firmware framebuffer | `dev/fbdev/simple` | implemented (VM) | the display on every x86 machine today; no mode setting, no acceleration, no blanking |
| Graphics | Intel (i915) | LinuxKPI port | partial | "initial kernel API support, not a working Intel graphics driver" ([linux-i915](linux-i915.md)) |
| Graphics | AMD, NVIDIA | none | open | |
| Audio | Intel HD Audio | `dev/hda` | implemented (VM) | playback through QEMU's controller and codec is recorded and checked, across every kind of sleep (`drivers-sleep`); no recording, no jack detection, no physical codec tried |
| Input | PS/2 keyboard and mouse | `dev/console`, `dev/mouse` | implemented (VM) | ISO checks; hardware-platform `suspend` (wake by key) |
| Input | USB keyboard and pointer (xHCI) | `dev/xhci` | implemented (VM): root ports of one controller, polled | no hubs, no hotplug; taking the controller ends firmware's PS/2 emulation; untried on a PC |
| Platform | ACPI (uACPI), LAPIC, IOAPIC, HPET | `uacpi`, `x86/*` | implemented (VM) | events, power button, sleep states S5; embedded controller (`x86/acpiec`): host tests of the protocol, and hardware-platform `acpi-ec-selftest` with a simulated controller behind uACPI; no physical controller tried |

### AArch64 VM

| Family | Device | Driver | State | Evidence and limits |
| --- | --- | --- | --- | --- |
| Storage | VirtIO block (MMIO) | `aarch64/virtio_blk` | implemented (VM) | the disk-root and storage suites; legacy MMIO transport only |
| Storage | VirtIO block (PCI), NVMe, AHCI | none on AArch64 | open | why VirtualBox's arm64 machine runs from memory |
| Ethernet | VirtIO net (MMIO) | `dev/virtio_net` | implemented (VM) | the default network of every AArch64 test |
| Ethernet | Intel 8254x | `dev/e1000` | implemented (VM) | hardware-platform `devices`, `suspend` |
| Graphics | ramfb, VirtIO GPU | `aarch64/virtio_gpu`, `drm` | implemented (VM) | [kekvm-gpu](kekvm-gpu.md) |
| Audio | VirtIO sound | `aarch64/virtio_snd` | implemented (VM) | `tests/sound`; playback only |
| Input | VirtIO input, USB keyboard and pointer (xHCI, PCI) | `aarch64/virtio_input`, `dev/xhci` | implemented (VM) | no hubs, no hotplug |

### Apple M1 MacBook Air (J313)

Every row is `implemented` at most: each has code and host tests, and each
driver's own document says the machine has not validated it.

| Family | Device | Driver | State | Evidence and limits |
| --- | --- | --- | --- | --- |
| Storage | Apple ANS2 NVMe | `apple/ans` | implemented (host) | opt-in `vinix.apple_ans=1`. "The full V/kernel build and a physical M1 SSD test have not been performed." ([apple-ans](apple-ans.md)) |
| Ethernet | none built in | -- | -- | USB Ethernet has no driver |
| Wireless | Broadcom BCM4378 | `apple/wifi` | implemented (host) | opt-in `vinix.apple_wifi=1`. "Physical BCM4378 operation still needs validation on M1 Air hardware" ([apple-wifi](apple-wifi.md)) |
| Bluetooth | BCM4378 | none | open | |
| Graphics | firmware framebuffer | `dev/fbdev/simple` | implemented | what the machine displays through today |
| Graphics | AGX G13, DCP | `gpu/agx`, `gpu/dcp` | implemented (host) | opt-in. "No step of the sequence above has been run on hardware from this tree" ([M1 AGX](m1-agx-bringup.md)) |
| Audio | speakers (TAS2770) | `apple/speakers` | implemented (host) | opt-in. "None of this has been checked on the machine itself yet" ([M1 speakers](m1-speakers.md)). No headphone jack, no microphones |
| Input | SPI keyboard and trackpad | `apple/spi_keyboard` | implemented (host) | [apple-spi-touchpad](apple-spi-touchpad.md): not built and booted on an M1 Air for that change |
| Input | USB | none on Apple hardware | open | xHCI is driven on PCI only |
| Platform | SMC battery, charger, temperatures, charge limit | `apple/smc` | implemented (host, VM) | on by default; `vinix.apple_smc=legacy` for the device nodes alone. Run against a simulated SMC on the build machine and in QEMU. "No part of this driver, old or new, has run on a Mac" ([M1 battery](m1-battery.md)). Which of its keys this machine has, and whether its firmware has the charge limit key, is not known |
| Platform | Type-C display hotplug | `apple/typec` | implemented (host) | opt-in; display attach and detach only |
| Platform | AIC, PMGR, watchdog, DART | `aarch64/*`, `apple/dart` | implemented | the machine boots through them; four CPUs started |

## Vendor dependencies

What the reference set needs that Vinix cannot write for itself.

| Dependency | Needed for | Where it comes from | Status |
| --- | --- | --- | --- |
| Broadcom BCM4378 firmware, NVRAM, CLM, TxCap | M1 Wi-Fi (and Bluetooth) | the machine's own macOS installation; not redistributable | copied by the user; given to the driver by `wifi-ctl` |
| Apple coprocessor firmware (AGX, DCP, ANS, SMC, SEP) | M1 graphics, display, storage, power | loaded by iBoot before the kernel runs, from the macOS firmware of the machine | version-locked: a driver must match the firmware the machine has |
| Apple iBoot and the device tree | booting any Apple machine | the machine | m1n1 and U-Boot (M1), `apple-boot` (M5) |
| Intel CPU microcode, AMD microcode | correctness and mitigations on PCs | `linux-firmware`; redistributable | not loaded: what firmware loaded is what runs |
| Intel graphics DMC, GuC, HuC | i915 display power states and media | `linux-firmware`; redistributable | no consumer yet; the firmware loader is where it would come from |
| Intel, Realtek, MediaTek Wi-Fi firmware | PC wireless | `linux-firmware`; redistributable | no driver |
| NVIDIA | NVIDIA graphics | proprietary, or nouveau with signed firmware | open; not planned in this workstream |
| ACPI tables and the embedded controller's behaviour | PC battery, lid, keys, thermal | each machine's firmware; per-model quirks | uACPI interprets the tables and `x86/acpiec` drives the controller by the specification and Linux's defaults; no machine's quirks are known, and two of Linux's per-model ones are boot options (`vinix.ec=`) |
| USB-IF, PCI-SIG, NVMe, AHCI, Intel VT-d, AMD-Vi specifications | everything on a bus | public | followed; Linux 6.6 is the reference for behaviour firmware gets wrong |

## The physical checklist

What "qualified" means for a machine. It is run on the machine itself, from
an installed system or the release image, by someone who can see and touch
it. Record the image's `/etc/vinix-release`, the machine's exact model and
firmware version, and the output of each command.

`hwcheck` prints the first half of the record. Build it for the machine and
copy it over (`tools/hwcheck/build aarch64|x86_64 hwcheck`):

```sh
hwcheck --rehearse-sleep > report.md
```

1. **Inventory.** `hwcheck` lists every device with its driver. Every device
   the machine is sold with must be bound, or be named in the record as
   unsupported. No device may be `failed`.
2. **Storage.** Write a file larger than memory, `sync`, restart, compare its
   checksum. Repeat with the power cut instead of a restart, ten times; the
   filesystem must mount and every file that was synced must be whole.
3. **Network.** Each interface: obtain an address, transfer 1 GiB each way
   and compare checksums; pull the cable or leave the access point's range
   and return.
4. **Display, input, audio.** Every built-in display at its native
   resolution; every key, the pointer, gestures; speakers, headphones and
   microphone, by ear and by recording.
   The brightness keys: each press must move
   `/sys/class/backlight/*/brightness` and the panel with it. A panel that
   is listed there and does not change is one whose firmware hands the
   work to a graphics driver this system does not have: record it, and
   `vinix.acpi_backlight=off` takes it out of the way.
   A USB keyboard and mouse plugged straight into the machine at start:
   keys and the pointer work, and `/sys/bus/usb/xhci` counts their
   reports. Then the same through a hub, which is expected not to work, to
   know what the machine's own keyboard is behind; if a keyboard that worked
   before no longer does, `vinix.usb=off` and record it.
5. **Power off and restart.** Twenty of each from the desktop's menu and
   twenty by the power button. The machine must go off, and come back with
   no filesystem repair.
6. **Sleep rehearsal.** `hwcheck --rehearse-sleep` reports every device
   suspended and resumed and none failed, and which PCI functions were put
   into D3hot and that each came back (`/sys/power/pci_d3`: none refused,
   none not back); then use every device again. If one does not work,
   repeat the rehearsal with `vinix.pci_d3=off` on the command line: if it
   works then, the fault is D3hot's and not its driver's resume. Record
   which.
7. **Sleep.** Fifty cycles of each depth the machine offers
   (`/sys/power/mem_sleep`: `s2idle`, and `deep` where it is listed -- where
   it is not, record what `/sys/power/deep_sleep` gives as the reason), by
   menu, by lid and by idle timer, woken by key, by lid, by power button and
   by `wakealarm`, some of them with sound playing. After each: display,
   input, network, audio and storage work, the sound goes on;
   `suspend_stats/fail` and `security_changes` are 0. Leave one sleep of each
   depth overnight and record the charge lost.
   Before the first `deep` sleep record `/sys/power/acpi_wakeup`: the lid
   and the keyboard should be listed, and `armed` should go up for each with
   every sleep. A lid that is armed and still does not wake the machine is
   an event of firmware's that did not arrive: record the line.
8. **Battery.** Compare `capacity`, `status`, `energy_now` and
   `time_to_empty_now` with the firmware's own figures (or another operating
   system on the same machine) at 100%, 50% and 10%. Pull and replace the
   charger and shut the lid: each must be noticed within a second. Run to
   the critical threshold: the machine must shut down cleanly before it
   dies. On a laptop with an embedded controller, record the counters under
   `/sys/bus/acpi/devices/PNP0C09:00/ec/` afterwards: no timeouts, and not
   failed. A battery that counts charge has `charge_now` in place of
   `energy_now`.

   On an Apple machine, first the seven steps of
   [M1 battery](m1-battery.md#on-an-m1), which begin under macOS with
   `tools/apple-smc/smcprobe` and with the kernel started as
   `vinix.apple_smc=legacy`. Then, for this step: `capacity` against
   macOS's percentage read just before the restart; `/dev/battery` the same
   number, read once to its end; `status` with the charger in, out and with
   the battery full; record `/sys/devices/platform/apple-smc/smc/keys` and
   `status`, in which `transport` must be `ok` and `key_errors`,
   `keys_odd_sized`, `implausible` and `percent_jumps` 0 after an hour, and
   `parks` one higher after each sleep. Where there is a
   `charge_control_end_threshold`: write 80, read it back, restart into
   macOS and see that its own setting agrees, then write 100; record the
   charge the battery stops at over a day with the limit on.
9. **Heat.** Compare each temperature with another operating system's
   reading. Under sustained full load the limit must come down before the
   firmware's own protection acts, and the machine must not shut itself off.
   Where firmware describes fans (`/sys/class/thermal/acpi_fans`), they must
   be heard to speed up under load and slow down after it, and `fanN_input`
   must agree with what is heard. On an Apple machine the zone `macsmc` has
   no limit to come down for: record each `tempN_input` of `macsmc_hwmon`
   beside macOS's reading of the same sensor, idle and under load, and on a
   machine with a fan its `fanN_input` beside what is heard and between
   `fanN_min` and `fanN_max`; no file may read empty, and no temperature may
   be one the machine could not be at.
10. **Idle.** Ten minutes idle with the display on: record power drawn (from
    the battery's `power_now`), each CPU's deepest idle state and the time in
    it.
11. **Hotplug.** Twenty connections and removals of each kind of removable
    device the machine has ports for, including while asleep.
12. **A driver failing.** Reset each device through its `reset` file while it
    is in use; unbind and bind those that can be. The machine stays up and
    the device works again.

A capability is `qualified` on a machine when the steps that exercise it
have passed there and the record is linked from this document.

## Completed checklists

None.
