# Default QEMU boot and PS/2 input

The release gate (`scripts/test-iso.sh`) includes the plain command:

```sh
qemu-system-x86_64 -m 2048 -cdrom vinix-amd64.iso
```

The V runner adds only headless display, serial logging and a QMP socket. It
checks the first-run desktop, the cursor at both ends of a movement and its
return, and typing into the name field. Cursor checks examine the two cursor
rectangles so a blinking caret or clock cannot make a stuck pointer pass.

Run that check independently with a current V compiler:

```sh
build-support/source-tools/run install-qmp /tmp/vinix-qmp
v run tests/default-qemu/run.v --desktop vinix-amd64.iso /tmp/vinix-desktop-check /tmp/vinix-qmp
```

The smaller fixture reads the actual 32-byte `/dev/pointer` ABI, verifies its
buffer boundary, and checks immediate motion, signed movement, all five button
edges, interleaved keyboard traffic, both wheel directions and consumed
deltas. It sleeps for one millisecond between reads, which also detects a
scheduler that rearms an expired deadline without waking its sleeper.

Build it with a release ISO containing the native musl SDK, Clang/LLD, tar,
xorriso, and an already-built kernel. The builder uses the normal ISO assembly
script and its pinned Limine binaries. All generated files stay outside Git.

```sh
v test kernel/dev/mouse/packet
V=/path/to/v v run tests/default-qemu/build.v vinix-amd64.iso kernel/bin/vinix /tmp/vinix-input-build
v run tests/default-qemu/run.v /tmp/vinix-input-build/input-amd64.iso /tmp/vinix-input-check /tmp/vinix-qmp
```

Every state directory must be new. Extra arguments are passed directly to
QEMU, for example `-machine pc,hpet=off`, `-machine q35 -smp 4`, or
`-accel kvm -cpu host`. For UEFI, append
`-machine q35 -drive if=pflash,unit=0,format=raw,readonly=on,file=/path/to/OVMF_CODE.fd`.
`VINIX_QEMU_X86_64` selects another QEMU executable.

Set `VINIX_INPUT_START_DELAY_MS=500` to compare a settled device with the
default immediate-input test. On the unmodified `iso-2026-11-12` kernel,
immediate motion fails; with the delay, motion and buttons pass but scrolling
fails. Under single-CPU KVM, even the delayed test stops receiving input.
The parser unit tests additionally cover malformed headers, overflow packets,
partial packets, nine-bit signed axes, and both PS/2 wheel packet formats.

## Desktop session diagnostics

`session-entry.v` imports a diagnostic init wrapper. In a disposable test
initramfs, rename the release `/sbin/init` to `/sbin/init-original` and install
this wrapper as `/sbin/init`. Compile with V's `-translated -no-builtin` flags
and link against the release musl SDK, as for the pointer fixture in `build.v`.
It captures the release init and desktop output on COM1 and provides a root
shell on COM2. Attach file logging to the first QEMU serial port and a local
Unix socket to the second. This wrapper must never ship in a normal ISO.

The stylesheet regression tests live in `desktop/tools/tests/memory_test.v`.
Run them with the desktop's host-test staging and `-d track_heap`. They check
40 desktop redraws, 40 frames sharing Calculator's cached declarations, and
closing Calculator before its first frame. All must retain zero allocations.
The session diagnosis and rebuild limitations are recorded in
`session-validation.md`.
