# Native PlayStation regression

The guest runs the native `vinix-ps1` desktop client and its real PS1 emulator
in an isolated ARM64 Vinix VM. It boots the MIT-licensed Tetrade homebrew game,
checks detailed and changing game frames, compares controller input at equal
emulated ages, verifies desktop pointer/button routing, pause/resume and reset,
checks memory-card persistence
across processes, and requires a clean process exit with the shared surface
removed. The test uses the normal muted audio option.

```sh
tests/ps1/run
tests/ps1/run --no-build
tests/ps1/frame build/ps1/qemu.log build/ps1/gameplay.png
tests/ps1/desktop
```

The runner uses the existing ARM64 kernel and musl test sysroot. Build those
first with the ordinary kernel/userland scripts. `VINIX_VM_RUNNER_ROOT` can
point at another checkout's VM runner/kernel, `VINIX_PS1_TEST_SYSROOT` selects
the test sysroot, and `VINIX_PS1_BUILD_DIR` selects the emulator staging root.
The VM's disks, initramfs and game writes are disposable; the transcript stays
at `build/ps1/qemu.log` or the path passed to `--log`.

To additionally boot a PS1 executable or disc you own:

```sh
tests/ps1/run --no-build --game /path/to/game.cue --timeout 600
```

Add `--bios /path/to/scph5501.bin` to use your own BIOS for disc compatibility.

The runner stages relative CUE track and M3U playlist references. The additional
game check requires a nonempty detailed game frame and clean shutdown. The
Tetrade gameplay, controller, pause/resume and reset checks still run first.
No commercial game or Sony BIOS is downloaded by this regression.

`frame --frame 0` selects the first captured frame; the default is the last.
PNG pixels come directly from the VSF1 surface produced by the emulator.

`desktop` uses the built compositor, actual QEMU mouse input and screenshots
to play Tetrade, verify pause/resume and close its window. Its logs and screen
captures are retained under the PS1 build directory. Both VM harnesses keep
their disks and game writes isolated from the running desktop.

The host commands use the native V controller in `tests/emulator-desktop/emulatorhost`.
See [controller qualification](../emulator-desktop/controllers.md).
