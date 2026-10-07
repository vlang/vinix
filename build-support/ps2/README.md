# PS2 build inputs

The ARM64 frontend statically links the [Iris PS2 emulator](https://github.com/allkern/iris)
at **0.15-alpha**, revision `c43cd7e6017656a067acf9a4749480ff35e6fb3a`.
The pinned source archive has SHA-256
`6030d1870917afed3ce60eb2ee374d0c38e18ccc6f6ce60128af270e339b00a6`.
Downloads are size limited, hash verified, and extracted as regular files with
path traversal checks. Sources and generated objects stay in ignored `build/ps2`.

This release retains the portable cached EE interpreter, IOP/VU interpreters,
and software GS rasterizer. No JIT, Vulkan, OpenGL, SDL library or desktop host
frontend is linked. A small SDL types header satisfies the unused software
renderer presentation interface. The Vinix adapter installs the upstream
rasterizer callbacks and sends the actual GS VRAM display to the compositor.
The adapter converts the GS's 12.4 fixed-point screen coordinates at the
single-thread rasterizer boundary, restoring the hardware registers afterwards.
The core uses Iris's default timing scale of 8.
The adapter also substitutes the SPU2 initialization/destruction functions to
disable Iris's process-global `adma.wav` debug capture. Hardware initialization
and audio synthesis retain their upstream behavior; candidate-machine loading
and reset can safely overlap old and new SPU2 instances without sharing a FILE.
The downloaded source stays unchanged; the build renames just those two
upstream symbols and uses the lifecycle functions in `bridge.c`.

File-size queries, ELF validation, bare-metal CPU setup, bounded CPU stepping
and BIOS path patching are maintained in `vbridge/core.v`. The module is built
with `-gc none -manualfree` without the V runtime. Its constant error messages
construct the SDK's native `std::runtime_error`; an instruction-only unwinding
envelope frees unpublished exception storage if that constructor throws.
The remaining C++ bridge keeps the existing machine, frontend and STL ownership
scopes during this migration stage. Native EE scalar writes use byte copies at
offsets checked against the actual C++ EE definition by the SDK compiler.

Iris is MIT licensed. Its original license is staged next to the executable.
The compiled IPU VLC decoder includes attribution to Play!; the BSD license
notices for Play! and its Framework, and the MPEG IDCT copyright notice, are
also staged. Upstream comments and source remain in the downloaded tree. Musl
and the sysroot's GCC/libstdc++ runtimes come from the existing ARM64 userland build.

The adapter boots regular ISO/BIN discs and ELF programs through a supplied
4 MiB PS2 BIOS dump, using Iris's BOOT2/host-file boot mechanism. BIOS code and
commercial game content are not downloaded or bundled. ELF files with OSABI
`0x56` explicitly request bare-metal boot: loadable segments are validated and
copied to EE RAM, and the IOP starts at an idle RAM0 jump. Such a program supplies
its own hardware initialization and IOP code. This path is used by the source
homebrew included in this repository, not by arbitrary PS2 games.

The C ABI in `bridge.h` provides load, bounded frame execution, reset, controller
input, SPU2 audio, memory card flush and destruction. A replacement loads into a
candidate machine; errors preserve the current game. Core `exit()` requests
and assertions become an error returned to the frontend. Host-file IOMAN hooks
close all descriptors with their owning IOP machine. The standard 8 MiB PS2
memory card uses 512-byte sectors plus 16 bytes of ECC. Card writes go to a private working
file; explicit saves replace the persistent card atomically. A new card is
unformatted and can be formatted by PS2 software.
