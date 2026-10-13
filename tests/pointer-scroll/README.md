# Pointer scrolling

Build an AArch64 kernel with the horizontal pointer axis, then run:

```sh
scripts/build-qemu-input.sh
tests/pointer-scroll/run --kernel-dir=/path/to/worktree/kernel
```

The test compiles a small V guest, boots it on a private temporary disk, and
sends QMP wheel-left, wheel-right, wheel-up and wheel-down events through the
real VirtIO tablet. It checks the direction and separation of both axes, the
original 32-byte read without overwriting the next word, and that a second
read consumes no duplicate wheel deltas. The serial transcript is retained at
`/tmp/vinix-pointer-scroll.log` (override with `--log`). It does not touch a
running desktop VM or its disks.

The macOS launcher selects the patched QEMU automatically. On another host,
set `VINIX_QEMU_BIN` to `build/qemu-horizontal/bin/qemu-system-aarch64`.
Files' scrolling, clipping and theme checks live in
`desktop/tools/tests/files_columns_test.v`; the real compositor/app pipe check
is `files_scroll_process_integration.v`, included in `test-utilities.sh`.
