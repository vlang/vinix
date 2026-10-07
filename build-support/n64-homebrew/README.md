# PADDLE Nintendo 64 homebrew

PADDLE is an MIT-licensed brick-breaking game built from the C and startup
assembly in this directory. Start begins a game, the D-pad or analog stick
moves the paddle, and A launches the next ball. It includes forty bricks,
three lives, scoring, a game-over screen, new rounds and a saved best score.

```sh
python3 build-support/n64-homebrew/build.py --output build/n64/homebrew
```

LLVM must include its MIPS backend; Apple Clang does not. Pass
`--llvm-bin /path/to/llvm/bin` if needed. The complete source and MIT license
are included. No SDK, downloaded game, Nintendo boot code or firmware is used.

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
