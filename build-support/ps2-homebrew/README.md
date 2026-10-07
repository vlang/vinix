# PADDLE PS2 homebrew

PADDLE is an MIT-licensed brick-breaking game, built from the V and startup
assembly in this directory. Start begins a game, Left and Right move the
paddle, and Cross launches a new ball after losing a life. It has forty bricks,
three lives, scoring, a game-over screen, another round after clearing the
court, and a saved best score.

```sh
python3 build-support/ps2-homebrew/build.py --output build/ps2/homebrew
```

The build uses the V compiler selected by `build-support/find-v.sh`, with
`-gc none -manualfree`. LLVM must include its MIPS backend; Apple Clang does not. Pass
`--llvm-bin /path/to/llvm/bin` if needed. No SDK, downloaded game, or Sony code
is used. V emits an intermediate build artifact using its 32-bit type model;
LLVM enforces the native little-endian MIPS-I/o32 IOP and MIPS-III/n32 Emotion
Engine ABIs. The build compiles the IOP program first and embeds its load
segments in the Emotion Engine ELF. The complete build inputs and
MIT license are in this directory.

The packet bank contains 8,192 permanent, 16-byte aligned entries. Controller
request and response buffers are permanent too; number digits and save
records use stack storage. Native declaration headers preserve volatile MMIO
widths. The two EE ordering instructions use `eecore/sync.S`; gameplay,
drawing, controller transactions and card-record handling live in V.

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

The 2026-10-07 port preserves the original sources at
`c411ab6a2ef22933e613924d76f1b4693c8b2006:build-support/ps2-homebrew/`:
199 lines in `paddle.c` and 85 in `iop.c`. Of these, 282 original lines move
to V; the two original `sync` lines remain instruction-only assembly and
receive no V algorithm credit. Strict actual MIPS builds check pointer,
scalar, volatile-access and packet layouts. Optimized instructions retain
the three EE polling loops, the IOP mailbox loop and both ordering boundaries.
Both final ELFs have no unresolved imports or allocator calls.

Original-C and V homebrew passed the same complete native ARM emulator
fixture, including the six required verdicts, optional executable check and
final verdict, under its unchanged 600-second deadline. Both used the same
qualified V fixture, emulator and kernel. All five gameplay metrics and three
complete exported RGB/PNG frames matched byte for byte. The full-surface
assertions remain 640×480; exported frames retain their 160×120 sampling.

Additional paired controls placed the data directory on disposable EXT2
storage for offline card readback. Both passed the complete fixture and
e2fsck; the full 8,650,752-byte cards matched each other and the previous
original baseline. This filesystem adapter and its timing differ from the
ordinary tmpfs deployment and do not replace that qualifying pair.

Frozen source, strict builds, optimized instructions, independent lifetime
reviews and native receipts are under
`~/.cache/vinix-c-to-v/firstparty-only-20261006-011023/ps2-v-homebrew-stage/`,
including `source-native-review-ready.json`, `native-comparison.json` and
`persistent-card-comparison.json`. The kernel source is unchanged; these tests
reuse the qualified default kernel. They make no fresh kernel build, x86
emulator, host sanitizer, commercial-game or physical PS2 execution claim.
