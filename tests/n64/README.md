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

The guest is maintained in the freestanding V module `guestfixture`. The
normal runner generates temporary C outside the checkout with the existing
native fixture compiler and links against the actual musl SDK. Its header
contains native declarations and ABI layout assertions only. It preserves
the original 45 failure guards, ten required feature verdicts, optional
supplied-game check, frame geometry, input ages, SRAM record and cleanup.

The independent C comparison is frozen at
`8d172d266a10d6ebd65fbd879c7dd67203c628fa:tests/n64/guest.c` (blob
`44d28703eb58cfd265e07ba6d3c88f7460ea7e99`, SHA256
`161a8b0a597981cc8b30f82a9bc585fe02adce6c27c6e81af8d783c90eb5daf9`).
Recover that comparison only outside the maintained checkout. An explicit
native comparison can boot its SDK-built executable using
`--prebuilt-init /path/to/init`; the default runner builds the V module.
ARM64 native execution covers the emulator regression. The guest fixture
also builds with the genuine x86 musl SDK; the current emulator payload is
ARM64, so that build does not establish native x86 emulator support.

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
