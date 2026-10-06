# PADDLE PS2 homebrew

PADDLE is an MIT-licensed brick-breaking game, built from the C and startup
assembly in this directory. Start begins a game, Left and Right move the
paddle, and Cross launches a new ball after losing a life. It has forty bricks,
three lives, scoring, a game-over screen, another round after clearing the
court, and a saved best score.

```sh
python3 build-support/ps2-homebrew/build.py --output build/ps2/homebrew
```

The compiler must include LLVM's MIPS backend; Apple Clang does not. Pass
`--llvm-bin /path/to/llvm/bin` if needed. No SDK, downloaded game, or Sony code
is used. The build compiles the IOP's MIPS-I program first and embeds its load
segments in the Emotion Engine's MIPS-III ELF. The complete build inputs and
MIT license are in this directory.

The Emotion Engine sends ordinary source-chain GIF DMA packets containing
GS sprite primitives. Its IOP worker polls a DualShock through SIO2 and
returns button states through the SIF registers. Saves also use the emulated
SIO2 memory-card protocol: sector 16 contains a `VPAD` record with best score,
games started, and an XOR checksum. This private record is intended for the
game's dedicated card, rather than a PS2 Browser filesystem.

The ELF has OSABI `0x56`, which requests the frontend's explicit BIOS-free
bare-metal protocol. Both CPUs start with interrupts disabled. The IOP idles
at RAM address zero; the Emotion Engine uploads its worker through the shared
IOP RAM window, then replaces the idle branch. Standard PS2 SDK homebrew and
disc games use their normal BIOS boot path and require a dumped PS2 BIOS.
