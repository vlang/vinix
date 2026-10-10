# Apple M1 SPI keyboard bring-up

This first-pass driver connects the built-in Apple SPI keyboard to the ARM64
console's existing idle-poll path. Console and termios initialization precede
driver initialization; the driver releases its lock before its output is fed
into the console. UART and VirtIO input remain in place.

## Scope

The V platform layer requires an `apple,t8103` root and an enabled
`apple,spi-hid-transport` node under an `apple,t8103-spi` controller. It resolves
and validates SPI registers, a fixed input clock, chip select, `spien-gpios`,
pinmux groups and PMGR dependencies before hardware initialization. There are
no hard-coded physical MMIO addresses. Unsupported or incomplete device trees
are not probed. A compatible GPIO in `interrupts-extended` can gate polling;
when present it fully gates reads, while device trees without one use timer
polling.

The native V transport uses bounded PIO transfers, packet and message CRC
validation,
20-byte keyboard-message reassembly, press/release tracking and software repeat.
Console encoding covers a US layout, independent left/right modifiers, logical
Caps Lock, Control bytes, Option-as-Escape, navigation, application cursor mode,
function keys and Fn-navigation/Fn-Delete. The shared poller also handles
touchpad reports and bounded mode commands. Three consecutive SPI transfer or
ready-packet framing errors reset
the shared transport after a bounded cool-off instead of disabling it for the
rest of the boot.

This does not implement keyboard backlight, Caps Lock LED, Touch
Bar, suspend/resume, USB keyboards or newer DockChannel/MTP keyboards.

## Host tests

Run from the repository root:

```sh
CC=clang sh tests/apple-spi-keyboard/run.sh
```

The independent keyboard and touchpad assertions now live in V. The runner compiles the
immutable original C fixture from Git outside the checkout and compares every
output line against V while linking the same production V provider. Both actual
Darwin ARM and x86 host ABIs run with AddressSanitizer and
UndefinedBehaviorSanitizer; no allocator imports are permitted in the fixtures.
The 21 keyboard groups retain framing, modifier/repeat behavior, all fragment
splits, output guards, FIFO transfers, reset polarity, chip-select timing,
timeouts, recovery, GPIO gating and 100,000 deterministic mutated packets.
The 19 touchpad groups retain wire-mode goldens, native and boot-mouse motion,
click edges, all 85 fragment splits, 16-contact reassembly, interleaved keyboard
traffic, malformed packets, mode retry, continuous chip select, staged FIFO
failures, frozen counters, final releases and 100,000 mutated messages.

```sh
python3 tests/apple-spi-keyboard/run.py --host-arch amd64
python3 tests/apple-spi-keyboard/run.py --suite keyboard --arch aarch64 \
  --kernel-dir /path/to/validated/kernel --guest-state-dir /tmp/spi-arm
python3 tests/apple-spi-keyboard/run.py --suite keyboard --arch x86_64 \
  --kernel-dir /path/to/validated/kernel --guest-state-dir /tmp/spi-x86
```

Native checks use both real musl SDKs and run complete original-C/V model pairs
with every 21-keyboard or 19-touchpad group marker. Select `--suite touchpad`
for the touchpad native pairs. ARM uses the full provider. The private x86 model
omits five unexecuted ARM hardware definitions; `provider.py` records their
body hashes and call sites and verifies that every retained source byte is
unchanged. It does not add x86 production support. Use `--state-dir` to retain
source hashes, generated objects, allocator audits and golden outputs.

No M1 hardware test has been performed. These injected models do not prove
physical SPI keyboard or touchpad operation.

## Kernel and hardware validation

With the normal Vinix build dependencies installed:

```sh
make -C kernel ARCH=aarch64 CC=clang
```

To build without probing the SPI keyboard:

```sh
make -C kernel clean
make -C kernel ARCH=aarch64 CC=clang VFLAGS='-d no_apple_spi_keyboard'
```

Keep a known-working boot image available during bring-up. The initialization
message ending in `awaiting reports` only indicates controller setup. Actual
receipt is logged separately:

```text
apple-spi-kbd: first valid keyboard report received
```

Verify typing and Enter at the shell, Backspace, both Shift keys independently,
Caps Lock, Control combinations, arrow keys, Fn-navigation, repeat and release.
Inspect `apple-spi-kbd:` diagnostics when no valid report is received. A missing
or incomplete DT node must be fixed in the bootloader handoff, not bypassed with
guessed register addresses.

## Native fixture controller

`run.v` owns the frozen-source inventory, source hashes, compiler arguments,
allocator guards, exact golden comparisons, native artifact inputs and selected
guest command. The Python entry point retains argument parsing and ownership
of the work directory. It imports the existing V provider and module producer
directly; the independent C/V fixture sources and assertions remain unchanged.
The serial object producer remains an unchanged dependency.

The transfer removes the original 8,408-byte, 106-line controller block and
original-revision binding. Fixture literals contribute zero algorithm credit.
The final receipt reports the net Python reduction including the frontend.

Qualification compares both controllers with instrumented compiler inputs and
real subprocess/filesystem ownership on ARM64, x86-64 and ARM ASan/UBSan, plus
actual cold CLI builds. Literal Unix backslashes in caller work paths remain
filename bytes during recursive directory creation. The unmodified SPI consumer still fails on generated
`memdup` calls with V 0.5.2 `6d549c2f` and `c6bb06f`; the frozen original
controller has the same failure. This stage makes no new successful SPI
fixture, kernel, QEMU or physical-hardware claim.
