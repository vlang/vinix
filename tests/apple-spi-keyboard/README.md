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
otherwise reads are timer-driven.

The C transport uses bounded PIO transfers, packet and message CRC validation,
20-byte keyboard-message reassembly, press/release tracking and software repeat.
Console encoding covers a US layout, independent left/right modifiers, logical
Caps Lock, Control bytes, Option-as-Escape, navigation, application cursor mode,
function keys and Fn-navigation/Fn-Delete. Touchpad and management reports are
ignored. Three consecutive SPI transfer errors disable the driver after retry
backoff.

This does not implement the trackpad, keyboard backlight, Caps Lock LED, Touch
Bar, suspend/resume, USB keyboards or newer DockChannel/MTP keyboards.

## Host tests

Run from the repository root:

```sh
CC=clang sh tests/apple-spi-keyboard/run.sh
```

The tests include the exact production C implementation with mock MMIO and a
mock timer. AddressSanitizer and UndefinedBehaviorSanitizer are enabled by
default; `SANITIZE=0` permits compilers without those runtimes. The 17 test groups
cover framing, modifier/repeat behavior, all two-fragment splits, output bounds,
FIFO transfers, reset polarity, chip-select timing/cleanup, transfer timeouts,
retry backoff, ready-GPIO polling and 100,000 deterministic mutated packets.

At introduction, all 17 host test groups passed with Clang sanitizers, and the
production C source cross-compiled as a freestanding AArch64 object with
`-Wall -Wextra -Werror`. The V integration and complete kernel were not compiled
in the implementation environment; no M1 hardware test has been performed.
These tests are not proof of a working keyboard on hardware.

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
