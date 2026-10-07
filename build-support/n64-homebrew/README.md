# PADDLE Nintendo 64 homebrew

PADDLE is an MIT-licensed brick-breaking game built from V and startup
assembly in this directory. Start begins a game, the D-pad or analog stick
moves the paddle, and A launches the next ball. It includes forty bricks,
three lives, scoring, a game-over screen, new rounds and a saved best score.

```sh
python3 build-support/n64-homebrew/build.py --output build/n64/homebrew
```

LLVM must include its MIPS backend; Apple Clang does not. Pass
`--llvm-bin /path/to/llvm/bin` if needed. The complete source and MIT license
are included. No SDK, downloaded game, Nintendo boot code or firmware is used.

Gameplay, rendering, DMA commands and polling are maintained in
`paddlecore/core.v`. V helpers use declaration-only volatile byte, halfword
and word views and compile to inline native loads and stores. `mmio.S`
supplies only the native `sync` instruction. V has no MIPS target: its
freestanding C backend emits these architecture-independent algorithms using
a 32-bit type model, then LLVM
compiles for the actual MIPS III/o32 big-endian target. Native width, endian
and ISA assertions guard that boundary. Generated C remains a build artifact;
the linked cartridge has no libc, V runtime or heap allocator imports.

The independent 231-line original is
`320172dfefc2c0fd5f849da73e1443fe0b982660:build-support/n64-homebrew/paddle.c`,
blob `77ceeefdd0414734d73c91809d89a82e0ed27e42`, SHA256
`95d85095c99d26492e498f3dfc96bae80120cfd85171941ba9de823d923d2cd4`.
Its 227 V-owned lines exclude original native boundary lines 42, 50, 80
and 196, which receive no V migration credit. Header/entry metadata, IPL3,
font, character and color bytes remain unchanged. Compiled program and
derived CIC checksum bytes change with the translation.

Qualification used the frozen original source and V compiler with LLVM's
actual MIPS III/o32 big-endian backend and strict warning checks. All eight
hardware polling loops retain repeated inline volatile loads in the optimized
MIPS object; initialized globals and all font, character and color bytes
match the original. The V object imports only `n64_sync`, and the linked ELF
has no undefined symbols. A fresh original C build reproduces the original
ROM byte for byte.

Original C and translated V cartridges passed the unchanged full ARM Vinix
guest fixture with the same kernel, native emulator and bridge. All ten
required checks, the additional homebrew check and the final verdict passed;
all nine reported metrics and all three complete exported frames matched
exactly. A separate host pair also passed the bridge's real ROM, reset,
replacement, save and cleanup checks with identical complete save files
(296,960 bytes). Its ASan/UBSan instrumentation covers the bridge and fixture,
with leak detection disabled; it does not instrument the cartridge or the
upstream emulator. These cartridge tests reused a frozen kernel and do not
claim a fresh full kernel build or physical N64 verification.

The first translation used assembly calls for each MMIO load and store.
Although the feature checks passed, the exact frame comparison caught
instruction timing drift in the ball and animated stars. That failed result
is retained in the migration evidence. The qualified implementation uses
inline volatile V accesses and passes the original exact comparison.

An original small IPL3 at cartridge offset `0x40` copies the program from ROM
through PI DMA and jumps to its entry point at `0x80000400`. This IPL3 targets
emulators which already initialize RDRAM; it has not been verified on physical
N64 hardware. The ROM has a conventional big-endian header and CIC-6102
checksum. The advanced homebrew header's cartridge ID `DE` and version `0x30`
request a 32 KiB SRAM cartridge.

The R4300 submits fill-cycle background clears through actual DP DMA and
waits for the RDP's FullSync interrupt. It then draws foreground pixels into
the double-buffered 320×240 RGBA5551 framebuffer and publishes it through VI.
It reads the controller through actual SI/PIF Joybus DMA, and
reads and writes the cartridge's SRAM through PI DMA. The first sixteen SRAM
bytes contain a big-endian `NPAD` record: magic, best score, games started and
an XOR checksum. This private format uses the game's dedicated save file.
