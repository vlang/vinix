#!/usr/bin/env python3
"""Decide whether a VM screenshot shows the Vinix desktop.

    check-screenshot.py SHOT.{ppm,png}
    check-screenshot.py --changed BEFORE AFTER MIN_PIXELS

QEMU's screendump writes PPM and VirtualBox's screenshotpng writes PNG; both
are read here without third-party modules. The desktop fills the screen with
its wallpaper or its first-run dialog, so it is recognised by what a console
or a hung boot does not have: most of the screen lit, and many colours. A
kernel log or a firmware menu is mostly black and uses a handful of colours.

Prints one line of statistics. Exits 0 for a desktop, 1 otherwise, 2 if the
file cannot be read.

With --changed, it instead compares two screenshots of the same screen and
exits 0 if at least MIN_PIXELS pixels differ: that is how a boot test sees
that typed text or a pointer movement reached the desktop. A blinking caret
alone changes a few dozen.
"""

import struct
import sys
import zlib


def read_ppm(data):
    fields = []
    pos = 0
    while len(fields) < 4:
        while data[pos:pos + 1].isspace():
            pos += 1
        if data[pos:pos + 1] == b'#':
            pos = data.index(b'\n', pos) + 1
            continue
        end = pos
        while not data[end:end + 1].isspace():
            end += 1
        fields.append(data[pos:end])
        pos = end
    if fields[0] != b'P6' or int(fields[3]) != 255:
        raise ValueError('only 8-bit binary PPM is supported')
    width, height = int(fields[1]), int(fields[2])
    pos += 1
    pixels = data[pos:pos + width * height * 3]
    return width, height, 3, pixels


def read_png(data):
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('not a PNG')
    pos = 8
    idat = b''
    width = height = channels = 0
    while pos < len(data):
        length, kind = struct.unpack('>I4s', data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b'IHDR':
            width, height, depth, colour, _, _, interlace = struct.unpack('>IIBBBBB', body)
            if depth != 8 or interlace != 0 or colour not in (2, 6):
                raise ValueError('only 8-bit non-interlaced RGB(A) PNG is supported')
            channels = 3 if colour == 2 else 4
        elif kind == b'IDAT':
            idat += body
        elif kind == b'IEND':
            break
    raw = zlib.decompress(idat)
    stride = width * channels
    out = bytearray(height * stride)
    prev = bytearray(stride)
    src = 0
    for y in range(height):
        filt = raw[src]
        line = bytearray(raw[src + 1:src + 1 + stride])
        src += 1 + stride
        for x in range(stride):
            a = line[x - channels] if x >= channels else 0
            b = prev[x]
            c = prev[x - channels] if x >= channels else 0
            if filt == 1:
                line[x] = (line[x] + a) & 0xff
            elif filt == 2:
                line[x] = (line[x] + b) & 0xff
            elif filt == 3:
                line[x] = (line[x] + ((a + b) >> 1)) & 0xff
            elif filt == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[x] = (line[x] + pred) & 0xff
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return width, height, channels, bytes(out)


def read_image(path):
    with open(path, 'rb') as f:
        data = f.read()
    if data[:2] == b'P6':
        return read_ppm(data)
    return read_png(data)


def changed(before, after, minimum):
    try:
        wa, ha, ca, pa = read_image(before)
        wb, hb, cb, pb = read_image(after)
    except (OSError, ValueError, IndexError, zlib.error, struct.error) as err:
        print(f'cannot read the screenshots: {err}')
        return 2
    if (wa, ha) != (wb, hb):
        print(f'the screen changed size: {wa}x{ha} -> {wb}x{hb}')
        return 0
    count = 0
    for i in range(wa * ha):
        if pa[i * ca:i * ca + 3] != pb[i * cb:i * cb + 3]:
            count += 1
    print(f'{count} pixels changed')
    return 0 if count >= minimum else 1


def main():
    if len(sys.argv) == 5 and sys.argv[1] == '--changed':
        return changed(sys.argv[2], sys.argv[3], int(sys.argv[4]))
    if len(sys.argv) != 2:
        print('\n'.join(__doc__.strip().splitlines()[2:4]), file=sys.stderr)
        return 2
    try:
        width, height, channels, pixels = read_image(sys.argv[1])
    except (OSError, ValueError, IndexError, zlib.error, struct.error) as err:
        print(f'cannot read {sys.argv[1]}: {err}')
        return 2

    total = width * height
    if total == 0:
        print('empty image')
        return 1
    lit = 0
    colours = set()
    # Every pixel for the brightness count, a sample for the palette.
    for i in range(0, total * channels, channels):
        r, g, b = pixels[i], pixels[i + 1], pixels[i + 2]
        if r + g + b > 48:
            lit += 1
        if (i // channels) % 7 == 0:
            colours.add((r >> 3, g >> 3, b >> 3))
    lit_share = lit / total
    desktop = lit_share >= 0.5 and len(colours) >= 24
    print(f'{width}x{height}, {lit_share:.0%} lit, {len(colours)} colours: '
          f'{"desktop" if desktop else "no desktop"}')
    return 0 if desktop else 1


if __name__ == '__main__':
    sys.exit(main())
