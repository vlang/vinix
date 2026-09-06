#!/usr/bin/env python3
"""Rasterise the Roboto faces the desktop draws with into a V source file.

Vinix has no font files and no rasteriser, so the glyphs travel with the
binary: every face is baked here into an 8-bit coverage atlas and emitted as
base64, which keeps font_data.v small enough to compile quickly while staying
plain text in the repository.

Each face is a (weight, pixel size) pair. The desktop picks the closest one to
what a text style asks for rather than scaling, because a stretched bitmap
atlas looks worse than one a couple of pixels off.

Every face carries the printable ASCII block followed by the supplemental code
points in EXTRA_RUNES that the font actually has a glyph for. A candidate the
font is missing is dropped here rather than baked as a .notdef box, which is
why the list can name more than Roboto covers.

Run from the repository root after changing a size, a face or the rune list:

    python3 desktop/tools/genfont.py

Roboto is licensed under the SIL Open Font License 1.1; the atlas is a
derivative of it and carries the same license (see desktop/FONT-LICENSE.txt).
"""

import base64
import os
import sys

from PIL import ImageFont

FIRST_CHAR = 32
LAST_CHAR = 126
ASCII_COUNT = LAST_CHAR - FIRST_CHAR + 1

# A code point in the Private Use Area, which no text font has a glyph for.
# Whatever the font draws for it is its .notdef, and any candidate rune that
# rasterises to the same thing is one the font does not really have.
NOTDEF_PROBE = 0xE000

# Candidates beyond ASCII. Being here is a request, not a promise: see above.
EXTRA_RUNES = [
    0x00B0,  # ° degree
    0x00B1,  # ± plus-minus            (ui2's calculator example)
    0x00B7,  # · middle dot
    0x00D7,  # × multiplication
    0x00F7,  # ÷ division              (ui2's calculator example)
    0x2013,  # – en dash
    0x2014,  # — em dash
    0x2018,  # ' left single quote
    0x2019,  # ' right single quote
    0x201C,  # " left double quote
    0x201D,  # " right double quote
    0x2022,  # • bullet
    0x2026,  # … ellipsis
    0x2190,  # ← left arrow
    0x2192,  # → right arrow
    0x2212,  # − minus sign
    0x2713,  # ✓ check mark
]

FONT_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "..", "third_party", "ui2",
    "assets", "fonts",
)

# (name, file, pixel size, bold). The sizes are the ones the desktop's own
# chrome uses, those ui2's calculator example asks for (18 for its keys, 28 for
# its display), and one monospaced face for the terminal.
#
# A face whose file name contains "Mono" is marked monospaced in the generated
# data, which is how a text style asking for that family finds it.
FACES = [
    ("small", "Roboto-Regular.ttf", 11, False),
    ("ui", "Roboto-Regular.ttf", 13, False),
    ("bold", "Roboto-Bold.ttf", 13, True),
    ("clock", "Roboto-Bold.ttf", 17, True),
    ("large", "Roboto-Regular.ttf", 18, False),
    ("large_bold", "Roboto-Bold.ttf", 18, True),
    ("display", "Roboto-Regular.ttf", 28, False),
    # Monospaced, for the terminal. A terminal that does not line its columns
    # up is not a terminal.
    ("mono", "RobotoMono-Regular.ttf", 13, False),
]


def open_font(file_name, size):
    path = os.path.join(FONT_DIR, file_name)
    if not os.path.exists(path):
        sys.exit("font not found: %s" % path)
    return ImageFont.truetype(path, size)


def rasterise(font, code_point):
    """Return (width, height, bearing_x, bearing_y, advance, pixels)."""
    ch = chr(code_point)
    bbox = font.getbbox(ch)
    advance = int(round(font.getlength(ch)))
    mask = font.getmask(ch, mode="L")
    width, height = mask.size
    if width == 0 or height == 0:
        return 0, 0, 0, 0, advance, b""
    # getbbox measures from the top of the line box, which is where the
    # renderer places a run, so no baseline arithmetic is needed at runtime.
    return width, height, bbox[0], bbox[1], advance, bytes(mask)


def supported_extras(faces):
    """Runes every face has a real glyph for.

    A rune is kept only if no face falls back to .notdef for it, so the same
    slot means the same character in all of them and the runtime needs one
    shared index.
    """
    kept = []
    for code_point in EXTRA_RUNES:
        ok = True
        for _, file_name, size, _ in faces:
            font = open_font(file_name, size)
            notdef = rasterise(font, NOTDEF_PROBE)
            candidate = rasterise(font, code_point)
            if candidate[5] == notdef[5] and candidate[:5] == notdef[:5]:
                ok = False
                break
            if candidate[0] == 0 and candidate[1] == 0:
                ok = False
                break
        if ok:
            kept.append(code_point)
        else:
            print("  dropped U+%04X (not in every face)" % code_point)
    return kept


def build_face(file_name, size, extras):
    font = open_font(file_name, size)
    ascent, descent = font.getmetrics()

    header = bytearray()
    pixels = bytearray()
    for code_point in list(range(FIRST_CHAR, LAST_CHAR + 1)) + extras:
        width, height, bx, by, advance, mask = rasterise(font, code_point)
        if bx < -128 or bx > 127:
            sys.exit("left bearing out of range for U+%04X" % code_point)
        header += bytes([width, height, bx & 0xFF, by & 0xFF, advance & 0xFF])
        pixels += mask

    return {
        "ascent": ascent,
        "descent": descent,
        "blob": base64.b64encode(bytes(header + pixels)).decode("ascii"),
    }


def wrap(text, width=100):
    return [text[i:i + width] for i in range(0, len(text), width)]


def main():
    print("Checking supplemental runes...")
    extras = supported_extras(FACES)
    print("  kept %d of %d" % (len(extras), len(EXTRA_RUNES)))

    out = []
    out.append("// Generated by desktop/tools/genfont.py. Do not edit by hand.")
    out.append("//")
    out.append("// Coverage atlases for the Roboto faces the desktop draws with, so the")
    out.append("// binary needs no font file on a system that has none. Roboto is licensed")
    out.append("// under the SIL Open Font License 1.1; see desktop/FONT-LICENSE.txt.")
    out.append("module main")
    out.append("")
    out.append("// FaceBlob is one rasterised face. `bold` and `size` are what it was baked")
    out.append("// at, which is how the renderer picks between faces. `ascent` + `descent`")
    out.append("// is the height of a line. `parts` join into base64 of a metrics header")
    out.append("// (width, height, left bearing, top bearing, advance for each glyph)")
    out.append("// followed by every glyph's coverage bytes in the same order. It is split")
    out.append("// because a single literal this long, spelled as one concatenation,")
    out.append("// exceeds what V's checker will descend into.")
    out.append("struct FaceBlob {")
    out.append("\tbold    bool")
    out.append("\tmono    bool")
    out.append("\tsize    int")
    out.append("\tascent  int")
    out.append("\tdescent int")
    out.append("\tparts   []string")
    out.append("}")
    out.append("")
    out.append("// Glyph slots run over printable ASCII first, then over these code points")
    out.append("// in this order, in every face.")
    out.append("const font_first_char = %d" % FIRST_CHAR)
    out.append("const font_last_char = %d" % LAST_CHAR)
    if extras:
        listed = ", ".join(
            ("u32(0x%04x)" % cp) if index == 0 else ("0x%04x" % cp)
            for index, cp in enumerate(extras))
        out.append("const font_extra_runes = [%s]" % listed)
    else:
        out.append("const font_extra_runes = []u32{}")
    out.append("")

    names = []
    for name, file_name, size, bold in FACES:
        face = build_face(file_name, size, extras)
        names.append(name)
        out.append("// %s: %s at %dpx" % (name, file_name, size))
        out.append("const face_%s = FaceBlob{" % name)
        out.append("\tbold:    %s" % ("true" if bold else "false"))
        out.append("\tmono:    %s" % ("true" if "Mono" in file_name else "false"))
        out.append("\tsize:    %d" % size)
        out.append("\tascent:  %d" % face["ascent"])
        out.append("\tdescent: %d" % face["descent"])
        out.append("\tparts:   [")
        for line in wrap(face["blob"]):
            out.append("\t\t'%s'," % line)
        out.append("\t]")
        out.append("}")
        out.append("")

    out.append("// font_blobs is the set the renderer chooses from.")
    out.append("const font_blobs = [")
    for name in names:
        out.append("\tface_%s," % name)
    out.append("]")
    out.append("")

    target = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "font_data.v")
    with open(target, "w") as handle:
        handle.write("\n".join(out))
    print("wrote %s (%d bytes)" % (os.path.normpath(target), os.path.getsize(target)))


if __name__ == "__main__":
    main()
