# Native PlayStation 2 regression

The ARM64 Vinix guest runs the ordinary `vinix-ps2` desktop application and
its Iris emulator. The included MIT-licensed PADDLE homebrew executes on the
emulated Emotion Engine and IOP, draws GS primitives, polls its controller
through SIO2, and reads and writes an actual PS2 memory card.

```sh
python3 tests/ps2/run.py
python3 tests/ps2/run.py --no-build
python3 tests/ps2/frame.py build/ps2/qemu.log build/ps2/gameplay.png
python3 tests/ps2/desktop.py
```

The guest requires detailed changing frames, compares controller input at
equal emulated ages, checks pause/resume and deterministic reset, verifies
that rejected ELF and missing-BIOS requests preserve the previous game, and
requires a clean application exit with its shared surface removed. It verifies
the game's SIO2 save record, changes the saved best score, then starts a fresh
process and requires the IOP to load that score and save an incremented game
count. The frame extractor writes a PNG directly from captured VSF1 pixels.

The runner uses the existing ARM64 kernel and musl test sysroot.
`VINIX_VM_RUNNER_ROOT` selects another checkout's VM runner/kernel,
`VINIX_PS2_TEST_SYSROOT` selects the test sysroot, and `VINIX_PS2_BUILD_DIR`
selects the emulator staging root. The VM's disks, initramfs and game writes
are disposable. The transcript remains in `build/ps2/qemu.log`.

To additionally test your own ELF or disc image:

```sh
python3 tests/ps2/run.py --no-build --game /path/to/game.iso --bios /path/to/ps2.bin --timeout 900
```

The supplied-game check requires a detailed game frame and clean shutdown.
No commercial game or Sony firmware is downloaded by these tests.

`desktop.py` boots the compositor, starts PADDLE using QEMU mouse input,
holds the on-screen controller to move its paddle, checks animation and
pause/resume, and closes the window. Logs and screenshots remain under the
PS2 build directory. It expects a compositor containing the PlayStation 2
catalog entry at `build/vinix-desktop`, or the path supplied with `--desktop`.
The development validation used an isolated compositor at
`build/ps2/vinix-desktop` to leave other sessions' build artifacts intact.
