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

The independent keyboard assertions now live in V. The runner compiles the
immutable original C fixture from Git outside the checkout and compares every
output line against V while linking the same production V provider. Both actual
Darwin ARM and x86 host ABIs run with AddressSanitizer and
UndefinedBehaviorSanitizer; no allocator imports are permitted in the fixtures.
The 21 keyboard groups retain framing, modifier/repeat behavior, all fragment
splits, output guards, FIFO transfers, reset polarity, chip-select timing,
timeouts, recovery, GPIO gating and 100,000 deterministic mutated packets.
The shared runner also preserves the 19 touchpad oracle groups.

```sh
python3 tests/apple-spi-keyboard/run.py --host-arch amd64
python3 tests/apple-spi-keyboard/run.py --suite keyboard --arch aarch64 \
  --kernel-dir /path/to/validated/kernel --guest-state-dir /tmp/spi-arm
python3 tests/apple-spi-keyboard/run.py --suite keyboard --arch x86_64 \
  --kernel-dir /path/to/validated/kernel --guest-state-dir /tmp/spi-x86
```

Native checks use both real musl SDKs and run complete original-C/V model pairs
with all 21 group markers. ARM uses the full provider. The private x86 model
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
