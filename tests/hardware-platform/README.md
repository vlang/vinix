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
| `devices` | aarch64, x86_64 | Every link in `/sys/bus/pci/devices` leads to a device with `vendor`, `device`, `class` and `state`. The e1000 is `bound` and has a `driver` link; unbinding makes it `unbound`, removes the link and leaves `dma` at `domain: none`; unbinding again fails; binding restores it. After three warm-up cycles, twenty more unbind/bind cycles may not shrink `MemFree` by more than 1 MiB. `reset` shows as `resets: 1` in `health` with the device `bound` again; `remove` makes the device's directory disappear. |
| `ahci` | x86_64 | A 64 KiB pattern written to `/dev/sd0` at 1 MiB, synced and read back; the controller reset through its sysfs `reset`, `health` showing `resets: 1`; a second pattern at 2 MiB. After the machine is off, the controller finds both patterns in the disk image, and the image still starts with the bytes it was created with. |
| `qmp-powerdown` | aarch64, x86_64 | The guest waits; the controller sends `system_powerdown`; the machine powers off within 30 s. **Pending**: see below. |

Every scenario also fails on a line containing `KERNEL PANIC`,
`FATAL EXCEPTION` or `HWTEST FAIL`, and a scenario whose machine is to power
off passes only if QEMU's `SHUTDOWN` event says the guest shut it down: a
reset makes QEMU exit as well (it runs with `-no-reboot`) and is not a
power-off.

A scenario marked pending is one the kernel of this branch cannot pass yet.
A default run skips it and says so; naming it with `--scenario` runs it.
`qmp-powerdown` is pending because this branch's kernel ignores the power
button. Its other purpose is fulfilled either way: it takes a host action
through the whole path -- a marker from the guest, a QMP command from the
host, an expectation with its own deadline -- and `qmp.log` of a run shows
the conversation.

## Running it

The kernel is an input: build it first, for the architecture named.

```sh
tests/hardware-platform/run --arch aarch64 --kernel kernel/bin/vinix
tests/hardware-platform/run --arch x86_64 --kernel build-amd64-kernel/bin/vinix
```

One scenario, or several, in the order given:

```sh
tests/hardware-platform/run --arch x86_64 --kernel build-amd64-kernel/bin/vinix --scenario ahci
tests/hardware-platform/run --arch aarch64 --kernel kernel/bin/vinix --scenario qmp-powerdown
```

Other options: `--list` prints the scenarios (with `--arch`, those for one
architecture); `--timeout SECONDS` is how long one scenario's machine may run
(default 120); `--qemu PATH` names the QEMU binary; `--state-dir DIR` keeps
everything, see below.

Each scenario prints one line, `PASS <arch> <scenario> (<seconds>s)` or
`FAIL ...`, followed by what the guest measured (its `HWTEST INFO` lines) and,
for a failure, the reason, the last 40 serial lines and where the logs are.
The last line is a summary. The exit status is 0 when every selected scenario
passed, 1 when one failed, 2 when the run could not start, and 130 when it
was interrupted.

```
PASS aarch64 devices (7.3s)
  3 PCI devices in sysfs
  MemFree before 20 unbind/bind cycles 923760 kB, after 923632 kB (-128 kB)
SKIP aarch64 qmp-powerdown (pending: the kernel on this branch does not handle the power button yet)
hardware-platform aarch64: 1 passed, 0 failed, 1 skipped
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
to send over QMP when a given line appears, and how the machine is to end:
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
   state directory), disks to create, required and forbidden markers,
   actions, the expected ending, and patterns to look for on a disk
   afterwards. A record that cannot pass yet gets a `pending` reason.

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

Two further limits:

- An x86-64 kernel built for production prints nothing on the serial port,
  so a panic there appears as a timeout with the marker that is missing,
  not as `KERNEL PANIC`.
- On AArch64 the kernel's messages and the guest's lines share one serial
  port byte by byte. The guest waits a moment before its verdict so that a
  driver's message does not land inside it; a line the kernel did interleave
  is not matched, and the scenario fails with that line shown.
