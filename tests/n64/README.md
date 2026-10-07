# Native Nintendo 64 regression

The ARM64 Vinix guest runs the ordinary `vinix-n64` desktop application with
the parallel-n64 interpreter and software renderer. Included MIT-licensed
PADDLE homebrew executes real R4300 instructions, clears its background
through DP/RDP and publishes its framebuffer through VI, polls its
controller through SI/PIF and reads and writes cartridge SRAM through PI DMA.

```sh
python3 tests/n64/run.py
python3 tests/n64/run.py --no-build
python3 tests/n64/frame.py build/n64/qemu.log build/n64/gameplay.png
python3 tests/n64/desktop.py
```

The guest checks detailed changing frames, controller effects at equal
emulated ages for both the D-pad and analog stick, batched arrow and WASD
keyboard input, pause/resume, deterministic reset, rejected ROM preservation,
and a clean shutdown with the shared surface removed. It checks the game's
SRAM record, changes its saved best score, then requires a fresh emulator
process to load that score and save an incremented game count. The frame
extractor writes a PNG directly from captured VSF1 pixels.
The same real homebrew also boots in `.v64` and `.n64` byte orders.
An otherwise valid ROM with stalled boot code must report its instruction
limit, stay responsive and run a new valid cartridge in the same process.

The runner uses the existing ARM64 kernel and musl test sysroot.
`VINIX_VM_RUNNER_ROOT` selects another checkout's VM runner/kernel,
`VINIX_N64_TEST_SYSROOT` selects the test sysroot, and `VINIX_N64_BUILD_DIR`
selects the emulator build root. The VM's disks, initramfs and game writes are
disposable. The transcript remains in `build/n64/qemu.log`.

To additionally check your own dumped cartridge:

```sh
python3 tests/n64/run.py --no-build --game /path/to/game.z64 --timeout 900
```

The supplied-game check requires a detailed game frame and clean shutdown.
No commercial game or Nintendo firmware is downloaded by these tests.

`desktop.py` boots the compositor, starts PADDLE using real QEMU mouse input,
holds its on-screen Right button, checks animation and pause/resume, and
closes the window. Logs and screenshots remain in the N64 build directory.
It expects a compositor containing Nintendo 64 at `build/vinix-desktop`, or
the path passed with `--desktop`. Development validation can use an isolated
compositor at `build/n64/vinix-desktop` to preserve shared build artifacts.
