# Apple M1 Air SPI touchpad

## Status and scope

This patch targets `vlang/vinix` **master** at
`cf9d952376ca96af721a182b3604a07742717050`, not the separate `main` branch.
It adds the built-in M1 MacBook Air touchpad to the existing ARM64
`/dev/pointer` interface used by the Vinix framebuffer desktop.

**Host tests and freestanding AArch64 C compilation are validated. The complete
V/kernel build and boot on an actual M1 Air have not been run for this patch.**
The test reports are synthetic protocol fixtures, not captured M1 hardware data.
Treat this as an experimental hardware-driver implementation pending device
validation, not a known-working binary release.

Implemented: one-finger relative movement; contact-lift and discontinuity
rebasing; physical left-button press/release and dragging; signed boot-mouse
fallback reports; native multitouch report-mode setup; bounded fragmented
report assembly; reset handling; and preservation of fast click edges between
userspace reads. The native parser accepts up to 16 contact slots, but only
one active contact drives the cursor.

Not implemented: tap-to-click, two-finger scrolling, secondary-click gestures,
pinch/zoom, momentum, sophisticated palm rejection, haptic configuration,
suspend/resume, an evdev device, or the legacy `/dev/mouse` Xorg protocol.
Multiple active contacts intentionally stop cursor movement. This is not an
M2/M3/M4/M5 DockChannel/MTP driver. The existing platform layer still restricts
probing to an enabled `apple,spi-hid-transport` beneath an `apple,t8103-spi`
controller on an `apple,t8103` machine.

## Checking out and building

From your existing Vinix checkout, with local changes saved:

```sh
git fetch origin touchpad/m1-air
git switch --track origin/touchpad/m1-air
CC=clang SANITIZE=1 ./tests/apple-spi-touchpad/run.sh
```

In the existing working M1 build environment, rebuild the kernel:

```sh
make -C kernel ARCH=aarch64 CC=clang
```

Retain any `V`, `LD_AARCH64`, and other toolchain overrides required by your
working checkout. The kernel's existing dependency setup must already be
present. Its build enumerates the C headers and V module sources, so no
Makefile source-list change is needed. Keep the existing Apple SPI keyboard
support enabled; `-d no_apple_spi_keyboard` disables the shared transport.

Use the same known-working M1 boot/EFI workflow and desktop-containing
initramfs as before, replacing the rebuilt kernel. No new GPU support,
Mesa rebuild, bootloader change, or desktop source change is required for this
input feature. Keep a bootable copy of the previous kernel and a recovery
route before testing. The patch does not mount or write an EFI partition.

The first `/dev/pointer` read requests native touchpad mode. The scheduler's
existing console-input poller performs the SPI transaction; the read itself
does not do SPI I/O. A valid report makes the pointer available. The first
successful snapshot logs:

```text
apple-spi-tp: first valid touchpad report received
```

This message means a report passed validation, not that hardware acceptance
testing is complete. A text terminal alone does not draw a mouse cursor;
run the existing Vinix framebuffer desktop, which consumes `/dev/pointer`.

## Data path and locking

```text
existing device-tree/power/pinmux setup
    -> existing single Apple SPI owner and lock
    -> bounded PIO packet read or feature-command/status transaction
       -> keyboard device 1 -> existing console decoder
       -> touchpad device 2 -> report assembly -> relative pointer state
    -> locked 8-word snapshot -> existing /dev/pointer -> desktop cursor
```

`kernel/c/apple_spi_touchpad.h` contains the internal allocation-free parser
and state machine. It is included by `apple_spi_keyboard.c` so production and
host tests execute the same implementation. `touchpad.v` is a small adapter
inside the existing `apple.spi_keyboard` module, sharing its lock. No second
controller driver, IRQ handler, DMA engine, or competing SPI reader is created.

`pointerdev.v` holds its existing resource lock, then takes the SPI input lock
only to copy a snapshot and consume button edges. The producer does not acquire
the pointer resource lock, so there is no reverse lock ordering. After a valid
Apple report, the Apple snapshot is used; before that, the original VirtIO
snapshot remains the fallback. Simultaneous Apple/VirtIO inputs are not merged.

The public pointer packet remains exactly eight 32-bit words:
`x, y, max_x, max_y, buttons, pressed, released, scroll`.
A final button-release edge survives transport disable. Snapshot reads do not
consume console bytes, drain SPI packets, or trigger unbounded hardware work.

## Protocol and failure handling

A transfer packet is 256 bytes: an 8-byte framing header, 246-byte data region,
and a little-endian CRC-16/ARC. The inner message has an 8-byte header, a
variable report, and its own CRC. Only input packets (`flags=0x20`) for device
2 become touch input. Keyboard packets and write responses cannot alter the
touchpad's in-progress fragments. The parser validates both CRCs, all lengths,
contiguous offsets, a constant total length, and a 100 ms assembly deadline.
The maximum buffered message is 536 bytes (46-byte report prefix plus 16
30-byte finger records and 10 bytes of message framing).

Native reports have ID `0x02`. Finger count is at report offset 30, physical
button state at 31, and finger records begin at 46. Within each record, signed
absolute X/Y are at offsets 4/6 and touch-major at 18. Sensor Y is inverted
before pointer processing. Native mouse-prefix relative bytes are not added
to finger motion, preventing double counting. An 8-byte boot-mouse report
instead uses its signed relative bytes directly.

The mode command is `SET_REPORT` (`0x52`), device/report 2, feature payload
`02 01`, response length 2, with independently sealed inner/outer CRCs. The
256-byte write and 4-byte status read occur under **one chip-select assertion**,
with a 200 microsecond delay between them. The expected status is `ac 27 68 d5`.
Status alone is not treated as proof of native touch reports.

Mode setup is requested lazily by `/dev/pointer`; up to three attempts are
spaced one second apart. It never interrupts an in-progress keyboard or
trackpad message. A failed mode command does not disable keyboard reads.
A valid native report stops retries; controller boot or touch reset report
`0x60` clears the motion/button state and schedules mode setup again.

Each FIFO stage has a 5 ms time bound and a separate iteration cap. Every
exit stops the engine and releases chip select at the transaction boundary.
Existing keyboard read-error backoff/disable behavior is preserved. Known
input discontinuities clear the motion baseline and release held buttons;
quiet stationary clicks do not time out artificially.

## Cursor calibration

The pointer uses a virtual `65535 x 40959` coordinate range with a centered
initial position. This is a **logical 16:10 cursor space**, not a measured
sensor range. `TP_GAIN=8` scales each native coordinate delta; `TP_BOOT_GAIN=32`
scales boot-mouse deltas. The desktop maps this space to its framebuffer.
These defaults have not been calibrated on hardware.

The first single-contact report establishes a baseline without moving the
cursor. A lift, multiple active contacts, a report gap of at least 100 ms,
a malformed report, or a delta larger than 2048 sensor units rebases movement.
This limits jumps where no documented stable contact ID is available. It is
not a substitute for full multitouch tracking or palm rejection. Rebuild after
changing the constants in `apple_spi_touchpad.h` to tune speed/thresholds.

## Reproducible tests

```sh
# Both suites, AddressSanitizer + UndefinedBehaviorSanitizer:
CC=clang SANITIZE=1 ./tests/apple-spi-touchpad/run.sh

# Both suites, optimized host build without sanitizer dependencies:
CC=gcc ./tests/apple-spi-touchpad/run.sh

# Target-compile the actual production C transport, not the host-test branch:
clang --target=aarch64-none-elf -D__AARCH64__ -D__vinix__ \
    -std=gnu99 -ffreestanding -fno-stack-protector -fno-strict-aliasing \
    -march=armv8.4-a -mgeneral-regs-only -Wall -Wextra -Werror -O2 \
    -c kernel/c/apple_spi_keyboard.c -o /tmp/apple-spi-aarch64.o
```

The last command uses Clang's freestanding headers. It verifies C target code
generation, not the V adapter, the full kernel link, or MMIO behavior on M1.

The unchanged upstream keyboard suite has 17 groups and 100,000 mutated
packets. The new touchpad suite has 19 groups and 100,000 mutated messages.
It checks an independently specified feature-command byte vector; signed
coordinates; lifting and discontinuities; button edges; all splits of a
one-finger message; maximum-size three-packet reports; device interleaving;
bad lengths/CRCs; retry/reset rules; and the actual shared PIO implementation
against a register model. The model checks chip-select timing, the write and
status stages, timeouts, invalid FIFO counts, and frozen-timer iteration bounds.
All fixtures are synthetic; passing them does not verify the physical device.

## M1 Air acceptance checklist

1. Boot the new kernel with the same device-tree handoff and initramfs that
   already boot successfully. Verify that the built-in keyboard still works.
2. Start the framebuffer desktop. Watch for the first-valid-touchpad-report
   log. Move one finger in both axes; confirm orientation and useful speed.
3. Lift and reposition repeatedly. The cursor should stay put on initial
   contact, then move from that point rather than jump to an absolute position.
4. Physically click, hold, drag, and release. Verify a click pressed and
   released between frames is not lost. Tap-to-click is intentionally absent.
5. Place two fingers down and lift one; cursor movement should pause and
   rebase, not jump between fingers. Two-finger scrolling is not implemented.
6. Type while moving the pointer. Confirm keyboard input, modifiers, and key
   repeat remain usable. Verify cold boot as well as a subsequent warm boot.

When diagnosing a stationary cursor, distinguish no valid reports from bad
motion scaling: absent first-report log means transport/mode/format discovery
has not succeeded; a first-report log with movement but wrong direction/speed
points to report/calibration behavior. The internal state tracks report,
native-report, bad-packet, reset, mode-attempt, and mode-error counts for a
debugger. These counters are not exposed through a new userspace ABI.

## Primary references and provenance

- Vinix base tree: `https://github.com/vlang/vinix/tree/cf9d952376ca96af721a182b3604a07742717050`.
- Existing transport: `kernel/c/apple_spi_keyboard.c` and
  `kernel/modules/apple/spi_keyboard/spi_keyboard.v` in that tree.
- Existing pointer ABI/consumer: `kernel/modules/dev/pointerdev/pointerdev.v`
  and `desktop/input.v` in that tree.
- Asahi Linux SPI framing, feature-request mapping, and write/status timing:
  `https://github.com/AsahiLinux/linux/blob/asahi/drivers/hid/spi-hid/spi-hid-apple-core.c`.
  Reviewed blob: `2ed909895391c80c45a016985e6d1bb2bcd8c46e`.
- Asahi Linux M1 Air mode feature and SPI native report/reset layout:
  `https://github.com/AsahiLinux/linux/blob/asahi/drivers/hid/hid-magicmouse.c`.
  Reviewed blob: `a770ceccabde6b860dae675589e5701f5c2ee9fd`.

The original patch was prepared from GitHub-fetched source files. The three
edited upstream files and unchanged keyboard test were verified byte-for-byte
against their Git blob hashes before modification.
