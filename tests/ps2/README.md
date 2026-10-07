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

The guest algorithms are maintained in `guestfixture/core.v`. The native
header supplies libc declarations and scalar/layout constraints. The runner
generates a temporary C build artifact from V with no builtin runtime and
links it against the actual ARM64 musl SDK. Set `VINIX_V_COMPILER` to select
the V compiler. `--prebuilt-init /path/to/init` permits an explicit original/V
native comparison while preserving the same workload and marker gate.

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

The guest port preserves the original 413-line fixture at
`5dcac6ee869844a123ef125e56c0330976f2a3f1:tests/ps2/guest.c`, including all
40 failure conditions and eight ordered verdict strings. Permanent frame
banks, synchronous stack payloads, the acquired surface pin around the copy,
30-second EINTR-aware pipe polls and 500 ten-millisecond reap attempts retain
their original ownership and bounds. The child must exit and be reaped before
the surface is unmapped and its file-removal check runs. Native pointer-event,
ELF-header, ELF-segment and card-record buffers remain 28, 84, 32 and 16 bytes.

Strict original-C/V builds passed both the actual ARM LLVM musl SDK and genuine
x86 musl GCC SDK, with no implicit allocator imports in the generated fixture.
The native ARM pair used the same frozen emulator, homebrew and kernel. Both
passed all six required checks, the optional PADDLE executable and the final
verdict; all five gameplay metrics and three complete exported RGB/PNG frames
matched exactly. Frame artifacts retain the original 160×120 sampling; the
fixture's pixel assertions inspect the full 640×480 surface. The maintained
runner also built and passed its normal V guest; its generated source, object
and ELF were reproduced byte for byte using the actual build profile.

Additional original-C/V controls kept the same guest and predicates but linked
the data directory into disposable persistent EXT2 storage for offline card
readback. Both passed the original checks and offline e2fsck; the complete
8,650,752-byte card files matched byte for byte. This filesystem adapter and
its timing differ from the ordinary tmpfs deployment and do not replace that
qualifying pair. The adapter remains a cache-only validation artifact.

Receipts, original Git blobs, generated artifacts and raw logs are frozen under
`firstparty-only-20261006-011023/ps2-v-fixture-stage` in the local migration
cache, including `original.json`, `source-audit.json`, `sdk-builds.json`,
`native-comparison.json`, `default-profile-validation.json` and
`persistent-card-comparison.json`. These tests
reuse a recorded kernel and emulator; they do not claim a new kernel build,
x86 emulator execution, host sanitizers or operation on physical PS2 hardware.
