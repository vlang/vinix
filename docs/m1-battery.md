# Apple SMC: battery, charger, temperatures and fans (experimental)

An Apple Silicon machine's battery gauge, charger, temperature sensors and
fans are behind its System Management Controller, a coprocessor reached
through a mailbox. `kernel/apple/smc` reads it and shows what it says in two
places:

- two device nodes, `/dev/battery` and `/dev/battery-power`, which the
  desktop and Activity Monitor read;
- the kernel's own classes, in Linux's layout: `/sys/class/power_supply`,
  `/sys/class/thermal` and `/sys/class/hwmon`
  ([hardware platform](hardware-platform.md)).

**None of this has run on a Mac.** It is tested against a simulated SMC, on
the build machine and in QEMU, which has no SMC of its own. What that does
and does not show is under [Validation](#validation); what to look at on the
real machine first is under [On an M1](#on-an-m1).

The driver is on by default on ARM64 and declines a device tree without a
compatible Apple SMC. `vinix.apple_battery=0` on the kernel command line
switches the whole driver off and `=1` on again; the last one wins.
`vinix.apple_smc=` takes words separated by commas:

| Word | Effect |
| --- | --- |
| `legacy` | only the two device nodes, and on the wire only what they need: the address of the shared memory and reads of five keys. No power supply, no zone, no key described or written |
| `nosensors` | no temperatures and no fans: their keys are not asked about |
| `nolimit` | the charge limit key is neither read nor written, and there is no `charge_control_end_threshold` |

Keep a known-good boot entry. This is independent of the GPU and DCP options.

## The device nodes

After a successful probe, `cat /dev/battery` returns a decimal integer in
0..100 followed by a newline: the SMC's `BUIC`, the charge it means to be
shown. Each open-file description captures one snapshot on its first nonempty
read, supports short reads, then returns EOF. Reopen for a fresh sample.
`dup()`/`fork()` share that snapshot. A panel should reopen every few seconds
and treat missing devices, read errors and invalid text as unavailable, never
as 0%.

`/dev/battery-power` is the same kind of node with one text line for each of
`voltage_mv` (`B0AV`), `current_ma` (`B0AC`, signed) and `power_mw` (`B0AP`,
signed); a key the SMC has not got is left out. Its first sample is taken a
tenth of a second after the node appears.

The nodes are mode 0444. Writes and resizing are refused; mmap and control
ioctls are unsupported. A missing device or initially absent BUIC and BRSC
leaves the nodes absent. Registered devices return EIO on failed or stale
samples (two seconds), ENODEV on a later missing key, and EFAULT for invalid
output pointers through checked usercopy. Console diagnostics start with
`apple-smc:`.

Until 2026-10-11 these nodes never reached EOF in a running kernel. They
found their place in the snapshot by the file offset, and the kernel hands a
character device none: every `read()` returned the text from its start
again. A reader that reads to the end, as the desktop's does, could not have
worked. The place is now kept per open, with the snapshot. Nothing had read
the nodes in a running kernel before the test that found this.

## Power supplies

Where the SMC has the percentage the nodes show and says what the battery
holds when full, there is `/sys/class/power_supply/macsmc-battery`; where it
has `CHIS`, `/sys/class/power_supply/macsmc-ac`. The names are Linux's.

| File | From | Notes |
| --- | --- | --- |
| `status` | `CH0R`, `CHCE`, `CHCC`, `AC-i`, `BSFC`, `CHNC`, `CHSC`, `CHWA` | Linux's `macsmc_battery_get_status()`, flag for flag; `Unknown` when a key it rests on could not be read |
| `capacity` | `BUIC` | the SMC's own percentage, the one `/dev/battery` shows, not charge over full charge |
| `charge_now` | `B0RM` | µAh. Big-endian where `BCF0` is four bytes, little-endian where it is one (Linux's rule). Where the order is not known, or the figure is more than a tenth over the full charge, the percentage's share of the full charge stands in: the one figure here that is worked out and not read |
| `charge_full`, `charge_full_design` | `B0FC`, `B0DC` | µAh |
| `current_now` | `B0AC` | µA, without its sign: `status` says which way |
| `voltage_now`, `voltage_min_design` | `B0AV`, `BITV` | µV |
| `cycle_count` | `B0CT` | |
| `time_to_empty_now`, `time_to_full_now` | `B0TE`, `B0TF` | the SMC's minutes, in seconds; only the one for the way the charge is moving |
| `capacity_level` | | from `capacity` and the thresholds in `/sys/class/power_supply/policy/` |
| `model_name`, `serial_number` | `BMDN`, `BMSN` | read once |
| `technology`, `manufacturer` | | `Unknown` and empty: the SMC is not asked |
| `charge_control_end_threshold` | `CHWA` | only where the SMC has the key; see below |
| `macsmc-ac/online` | `CHIS` | |

The battery counts charge, so it has no `energy_*` files; Linux shows both by
multiplying with a nominal cell voltage, which this does not make up.

What the thresholds lead to -- `Low` at 10%, the request to power off at 3%
while discharging, or when the SMC's own flag `BCF0` says the battery is
about to give out -- is the class's business, and so is waiting for five
seconds of agreement before the last. The driver adds its own caution
before that:

- a percentage that moves by more than five points from one second to the
  next is not believed until a second reading bears it out;
- `BCF0` counts only once it has been read set on two passes running;
- a remaining charge more than a tenth over the full charge, a full charge
  of nothing or of more than half again the design charge, and a voltage of
  nothing are left out.

`/sys/devices/platform/apple-smc/smc/status` counts what had to be
disbelieved (`percent_jumps`, `critical_unconfirmed`, `implausible`).

### The charge limit

`CHWA` is a flag: set, the firmware holds the battery between 75 and 80
percent. `charge_control_end_threshold` reads 80 or 100 accordingly and
takes exactly those two values; anything else is `EINVAL` and is not sent.
(Linux's driver takes any number and turns 95 and under into 80.) The file is
root's to write.

This is the only key the kernel ever writes, and only when a program writes
that file. The thread that owns the mailbox writes the key, reads it back,
and the write fails with `EIO` if the SMC refused it or reads otherwise
afterwards. Nothing is written when the driver starts: Linux clears the
charge inhibit keys (`CHTE`, `CH0C`, `CH0I`, `CH0K`, `CH0B`) and switches
the SMC's notifications on (`NTAP`) there, and this does neither.

An SMC with no `CHWA` has no such file. That includes the firmware whose
limit is `CHLS` instead, which is not driven: setting it means writing a
force-discharge bit with it.

## Temperatures and fans

One thermal zone, `macsmc`, and its hwmon device, `macsmc_hwmon`, carry the
temperatures Linux's device tree gives an M1 laptop
(`arch/arm64/boot/dts/apple/hwmon-common.dtsi`, `hwmon-laptop.dtsi`), with
its labels:

| Key | Label |
| --- | --- |
| `TH0x` | NAND Flash Temperature |
| `TB0T` | Battery Hotspot |
| `TCHP` | Charge Regulator Temp |
| `TW0P` | WiFi/BT Module Temp |

The first one found is the zone's own (`thermal_zoneN/temp`, `temp1_input`);
the rest are `temp2` onwards. A key is taken on when the SMC says it is a
`flt ` (a 32-bit float) or an `ioft` (48.16 fixed point), the two types
Linux's driver reads. The list is the kernel's own table; Linux reads it from
the `apple,smc-hwmon` node of the device tree, which this does not look at.

**The zone has no trip points.** The SMC gives no limit for these sensors,
and one made up here could switch a machine off for a figure that was never
a temperature. A reading at or below absolute zero, of 200 degrees or more,
or that is not a number, is not a temperature: the file reads empty for it,
`implausible` counts it, and nothing else happens. Nothing here throttles or
powers off; the SMC and the SoC look after the machine's heat themselves.

Fans are there when `FNum` says how many: an M1 MacBook Air has none and
gets no fan files. Each has `fanN_input` (`F0Ac`), `fanN_label` and, where
the SMC gives them, `fanN_min` and `fanN_max` (`F0Mn`, `F0Mx`, read once).
There is no `pwmN`: the SMC runs its fans, and the kernel only shows them.

Linux's power, voltage and current sensors (`PSTR`, `PDTR`, `VD0R`, ...) are
not shown: the kernel's hwmon view has temperatures and fans only.

## How it works

`kernel/apple/smc/smc.v` discovers an enabled `apple,t8103-smc`, its
translated named SRAM resource, and its zero-argument `mboxes` provider. The
provider must be an enabled `apple,asc-mailbox-v4` with a valid translated
MMIO range. No physical register addresses are guessed. The existing Apple
mailbox implementation provides Device mappings and ordering barriers.

`core/core.v`, which has no kernel in it, negotiates RTKit 11/12, completes
IOP/AP power-state and endpoint negotiation, starts endpoint 32, and requests
the address of the SMC's shared memory. Firmware-owned system buffers must
fit the DT SRAM region; log and IOReport notifications are acknowledged.
Host DMA allocations are unsupported. This separate SMC client does not
change the GPU-oriented shared RTKit implementation. It must be the sole
owner of its mailbox.

The commands sent, as in Linux's `drivers/mfd/macsmc.c`:

| Command | Used for |
| --- | --- |
| GET_SRAM_ADDR (0x17) | once, at start |
| READ_KEY (0x10) | every reading. Up to four bytes come back in the reply; a longer value is in the shared memory |
| GET_KEY_INFO (0x13) | once for each key, at start: its size and type |
| WRITE_KEY (0x11) | the charge limit, when a program sets it |

The shared memory is the firmware's own SRAM, at the address it gave, which
must lie inside the device tree's SRAM region; one page of it is mapped as
device memory and read and written a byte at a time. GET_KEY_BY_INDEX,
RW_KEY and the notifications are not used.

At start the driver asks which keys the SMC has and reads each once
(`core/supply.v`, `discover()`). A key that is absent, or has a size other
than the one it is taken for, is left out, and the files that would have
shown it are not made. `/sys/devices/platform/apple-smc/smc/keys` lists what
was taken on, one `key type size attributes` line each.

One thread owns the mailbox. Ten times a second it takes what the firmware
sent unasked; once a second it reads the percentage and the telemetry of the
device nodes and then what is due of the rest: eight keys every second
(nine where the firmware still has `AC-i`), five more every fifth second in
turn, two that never change once, and half of the temperatures and fans each
second -- about eleven exchanges a second on a MacBook Air beside the four of
the device nodes, each a busy wait for the SMC's answer, since the mailbox's
interrupt is not used. It publishes the result under a spinlock held for a
copy. Everything else -- the classes' read functions, the files in `/sys`,
the device nodes -- copies that out again and never waits for the SMC.

What is given out is at most three seconds old (two for the device nodes).
Past that, and for good once the SMC has stopped answering, the battery
reads `Unknown` with every measured figure 0 -- a full charge of 0 is how a
program tells an unread battery from an empty one -- the charger reads
offline, and a temperature or a fan speed reads empty. What the battery is
(its name, its design charge) and the charge limit last read are not
readings and stay.

Boot negotiation has a two-second counter deadline; commands have 500 ms
deadlines. Receive loops also have iteration caps and do not use WFE to wait
for an uninstalled mailbox interrupt. An exchange that got no answer in
time, a malformed reply to the capacity or telemetry keys, a reset or crash
of the firmware and an invalid firmware buffer end the channel until reboot:
retrying after the four-bit message ID wraps could take a late reply for a
later request's. A key that answers with an error or another size is that
key's matter alone: it is asked again, three times running and then every
thirty seconds.

**If asking for keys at start ends the channel** -- an SMC that does not
answer GET_KEY_INFO in time -- the device nodes go with it, where before this
work they would have gone on. `vinix.apple_smc=legacy` is the way back.

### Sleep

The driver is on the device list (`/sys/devices/platform/apple-smc`, driver
`macsmc`), so a sleep reaches it: from suspend to resume the thread leaves
the SMC alone, and on resume the first reading is waited for (up to a second
and a half) before programs run again. What was last published stands while
the machine is away, so that the kernel's own polling does not take a sleep
for a sensor that failed. The percentage is believed at once after a sleep,
however far it moved.

Nothing of the SMC's can end a sleep: its notifications are not switched on,
so a battery that runs out while the machine is suspended to idle is not
noticed until something else wakes it. Coming back from a sleep that cut the
SMC's power is not handled at all.

## Keys

Every key the driver reads, where its meaning comes from, and what was
checked how. "Seen" means read with `tools/apple-smc/smcprobe` from the SMC
of a MacBook Pro `Mac17,6` (M5 Max, macOS 26.5), the machine this was
written on: it confirms the type, the size and the byte order of a key that
machine has, **not** that an M1 has the key. An M1's keys have not been
read by anything in this repository.

| Key | Size | Read as | Meaning from | Seen on Mac17,6 |
| --- | --- | --- | --- | --- |
| `BUIC` | 1 | percent | macsmc-power.c | `ui8 `, 1 |
| `BRSC` | 2 | percent, where there is no `BUIC` | the original driver | `ui8 `, 1 -- one byte there, where the fallback asks for two |
| `B0AV` | 2 | mV | macsmc-power.c | `ui16`, little-endian |
| `B0AC` | 2 | mA, signed | macsmc-power.c | `si16` |
| `B0AP` | 4 | mW, signed | macsmc-power.c | `si32` |
| `B0RM` | 2 | mAh, order by `BCF0` | macsmc-power.c | `ui16`, big-endian, with `BCF0` four bytes |
| `B0FC`, `B0DC` | 2 | mAh | macsmc-power.c | `ui16`, little-endian |
| `B0CT` | 2 | cycles | macsmc-power.c | `ui16` |
| `B0TE`, `B0TF` | 2 | minutes, `0xffff` for none | macsmc-power.c | `ui16`, both `ffff` when full on the charger |
| `BITV` | 2 | mV | macsmc-power.c | `ui16` |
| `BSFC` | 1 | flag | macsmc-power.c | `flag` |
| `BCF0` | 1 or 4 | flag | macsmc-power.c | `ui32`, 4 |
| `BMDN`, `BMSN` | up to 32 | text | macsmc-power.c | `ch8*`, 32 and 21, NUL padded |
| `CH0R` | 4 | bits | macsmc-power.c | `hex_`, 4 |
| `CHCE`, `CHCC`, `CHSC` | 1 | flag | macsmc-power.c | `ui8 ` |
| `CHNC` | 8 | bits | macsmc-power.c | `hex_`, 8, little-endian |
| `CHIS` | 4 | nonzero for online | macsmc-power.c | `ui32` |
| `CHWA` | 1 | flag | macsmc-power.c (Asahi tree) | absent |
| `AC-i` | 2 | mA | macsmc-power.c | absent; Linux notes that macOS 15.4 firmware dropped it |
| `TH0x`, `TB0T`, `TCHP`, `TW0P` | 4 or 8 | degrees | hwmon-common.dtsi, hwmon-laptop.dtsi | `flt `, 4 |
| `FNum` | 1 | count | not in Linux's driver, which takes fans from the device tree; taken from that machine | `ui8 `, 2, on a machine with two fans |
| `F0Ac`, `F0Mn`, `F0Mx` (and `F1`...) | 4 | rpm | hwmon-fan.dtsi | `flt ` |

`ioft` was confirmed on other keys of that machine (`TG0B`: 48.16,
little-endian). No key of the type `sp78` exists there, and none is decoded.

The Linux sources are those of 2026-10-11: `torvalds/linux` master for
`drivers/mfd/macsmc.c`, `drivers/hwmon/macsmc-hwmon.c` and the device trees,
and the `asahi` branch of `AsahiLinux/linux` for
`drivers/power/supply/macsmc-power.c`, which has the charge limit that
mainline's lacks.

## Validation

On the build machine, with no kernel:

```sh
sh tests/apple_smc/run-host.sh
```

51 tests in three files run the protocol core against a simulated SMC
([tests/apple_smc](../tests/apple_smc/README.md)): how the bytes of each
type are read; the key commands, their errors and what ends the channel;
which keys are found on a laptop with and without a fan and a charge limit;
what is read on each pass; Linux's status logic case by case; the
percentage and `BCF0` filters; implausible figures; and the charge limit.

In QEMU, in a kernel built with `-d applesmc_selftest`, the same simulated
SMC stands behind the driver's mailbox callbacks and the whole driver runs:
the thread, the classes, `/sys` and the device nodes. Four scenarios of
[the hardware tests](../tests/hardware-platform/README.md) check them:
`apple-smc-selftest`, `-bare`, `-options` and `-legacy`.

`tests/apple_smc/run.sh`, the older fixture of the capacity and telemetry
path, is driven by Python and was not run for this work; the calls it covers
are unchanged but for one added argument inside the core.

**What this does not show.** The simulated SMC is this repository's reading
of Linux's driver and of the RTKit start-up the original client was written
against. That a real SMC answers GET_KEY_INFO and WRITE_KEY as it does, that
its shared memory can be read and written through a device mapping, that an
M1 has the keys listed above with the sizes expected, and that eleven more
exchanges a second do it no harm, is shown by nothing here. No part of this
driver, old or new, has run on a Mac.

## On an M1

Before trusting it, in this order:

1. Under macOS on the machine, `tools/apple-smc/smcprobe`: every key the
   driver wants, with its type and size. A key that is `absent` or of
   another size will simply not be shown by the driver; `BCF0`'s size says
   which way round `B0RM` is.
2. Boot with `vinix.apple_smc=legacy` first: the device nodes alone, as
   before. `cat /dev/battery` must print the percentage once and end.
3. Boot without it. The console's `apple-smc:` line says what was found
   (`battery yes, charger yes, 4 temperatures, 0 fans, charge limit ...`);
   `/sys/devices/platform/apple-smc/smc/keys` should agree with step 1, and
   `status` should say `transport ok`, `fresh 1`, and 0 for `key_errors`,
   `keys_odd_sized`, `implausible` and `percent_jumps`.
4. `capacity` against macOS's percentage before the reboot; `status` with
   the charger in and out; `charge_now` no more than `charge_full`; the
   temperatures near what macOS tools show.
5. Leave it an hour and read `status` again: `passes` about 3600, the
   counters still 0, `transport ok`.
6. Only then, and only on firmware that has `CHWA`: write 80 to
   `charge_control_end_threshold`, read it back, reboot into macOS and see
   that its own charge limit setting agrees; then write 100.
7. A sleep (`echo freeze > /sys/power/state` with a wake alarm set): `parks`
   one higher afterwards, `late_parks` 0, and the battery read at once.

## Primary protocol references

- SMC key descriptions: https://asahilinux.org/docs/hw/soc/smc/
- SMC transport: https://github.com/openbsd/src/blob/master/sys/arch/arm64/dev/aplsmc.c
- RTKit and firmware buffers: https://github.com/openbsd/src/blob/master/sys/arch/arm64/dev/rtkit.c
- SMC binding: https://github.com/torvalds/linux/blob/master/Documentation/devicetree/bindings/mfd/apple,smc.yaml
- Mailbox binding: https://github.com/torvalds/linux/blob/master/Documentation/devicetree/bindings/mailbox/apple,mailbox.yaml
- Key commands: https://github.com/torvalds/linux/blob/master/drivers/mfd/macsmc.c
- Battery and charger: https://github.com/AsahiLinux/linux/blob/asahi/drivers/power/supply/macsmc-power.c
- Sensors and fans: https://github.com/torvalds/linux/blob/master/drivers/hwmon/macsmc-hwmon.c

The device nodes were originally prepared against
cf9d952376ca96af721a182b3604a07742717050 and integrated on top of the
subsequent Settings/Display changes without altering them.
