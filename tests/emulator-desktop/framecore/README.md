# Native framebuffer extraction

The N64, PS1, PS2 and iOS PPSSPP `frame` commands compile and run V directly.
They need a V compiler and the host C compiler; Python and Pillow are not needed.
Select a compiler with `V` or `VINIX_V_COMPILER`, as for other host tools.

Each command takes `LOG OUTPUT [--frame INDEX]`. The default selects the last
frame; negative indices count backwards. PNGs contain the captured eight-bit
RGB pixels, with CRC-protected IHDR, IDAT and IEND chunks. The native compressor
may produce different compressed bytes from Python's zlib while preserving
the same decoded pixels. A malformed selected frame fails before creating
the output. Header dimensions must be between 1 and 8192, and every row must
contain exactly six lowercase hexadecimal characters per pixel.

Run the maintained parser and PNG checks with:

```sh
v -cc cc test tests/emulator-desktop/framecore
```

Qualification compared the removed Python scripts from commit `8635209b`
against the native commands for frame selection, frame boundaries, malformed
rows, extreme dimensions, Unicode decimal headers and invalid UTF-8 around
serial markers. PNG dimensions, CRCs and decompressed pixels were checked.
These checks cover extraction; they do not establish a new guest-emulator run.
