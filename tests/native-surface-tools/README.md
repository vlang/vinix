# Native surface checks

`surface-probe` replaces the seven embedded Python readers in the Firefox,
Chromium, desktop browser, LibreOffice and OBS guest scripts. Desktop staging
builds the V executable with the real musl SDK and installs it beside
`x-window-check` in `/usr/share/vinix`.

`colors` and `colors-with-size` read the compositor's shared mapping directly:
1,000 sampled 64-byte windows, three-byte prefixes every four bytes. Signed
floor division and negative slice clipping retain the original small-file
behavior, with arithmetic that avoids overflowing a wide product. `damage`
reads the first four little-endian bytes. `crc` folds the original 64 file
samples of up to 4,096 bytes with the IEEE CRC-32 polynomial and seed zero.
Both readers retain the `-1` failure sentinel, and colors report an error for
an empty/unmappable surface. CRC uses a stack table and buffer.

`obs-paint` retains the 25-word big-endian XWD layout, extent checks, 16-pixel
grid, 16-color threshold, 45-second deadline and one-second sleeps. Temporary
color sets are cleared and freed. Every mapping and descriptor has an owner
and an idempotent retirement path.

`obs-capture` resolves the X11 C API directly. C integer slots and the XImage
prefix use `i32`, while windows and plane masks use 64-bit unsigned values.
It retains the two-screen/MIT-SHM/RandR checks, writes the original marker
through the shared compositor mapping, checks Display 1's root image, and
restores the original pixel on every path. It also destroys the owned XImage
before closing the display and dynamic library. `VINIX_SURFACE_XLIB` selects
a compatible SDK library for qualification; normal guests use `libX11.so.6`.

```sh
build-support/run-v-tool.sh tests/native-surface-tools/qualify.v \
  /path/to/qualified/v /fresh/evidence arm # also x86 or san
```

Qualification runs real shared-mapping updates, eight small/normal file sizes,
8,000 signed-offset comparisons, a maximum signed-size offset, unsigned damage
boundaries, an independently captured gzip CRC trailer, immediate XWD paint,
extent failures and timed blank paint. The native V X11 fixture covers success
and nine display/extension/image/data/header/offset failures, checking pixel
restoration and exact image/display retirement. Four cold programs per profile
and both real dynamic-musl guest ELFs are built for ARM, Rosetta x86 and ARM
ASan/UBSan. The actual ARM SDK exposes all seven required X11 symbols as data.

No Python, browser, LibreOffice, OBS, real X11 server or Vinix guest executes.
The X11 tests establish native ABI and ownership behavior with an independent
V fixture; they do not claim a new graphics runtime result. The seven blocks
were embedded in Shell files and receive zero Python-file retirement credit.
