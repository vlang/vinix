#!/usr/bin/env python3
"""Rasterise Roboto with Chinese and Japanese fallback into V source.

Vinix has no font files and no rasteriser, so the glyphs travel with the
binary: every face is baked here into an 8-bit coverage atlas and emitted as
base64, which keeps font_data.v small enough to compile quickly while staying
plain text in the repository.

Each face is a (weight, pixel size) pair. The desktop picks the closest one to
what a text style asks for rather than scaling, because a stretched bitmap
atlas looks worse than one a couple of pixels off.

Every face carries printable ASCII, the supported supplemental code points in
EXTRA_RUNES, and the characters used by every translation. Noto Sans CJK SC
supplies Chinese catalog glyphs; bundled Noto Sans JP subsets supply
Japanese-only glyphs.

Run from the repository root after changing a size, a face or the rune list:

    python3 desktop/tools/genfont.py

After adding Japanese characters, rebuild the bundled font subsets as well:

    python3 desktop/tools/genfont.py --update-japanese-subsets

The Japanese subset update needs fontTools and a pinned, hash-checked source.
Normal atlas generation uses Pillow, bundled Japanese subsets, and cached
Chinese sources; the first run downloads and verifies the Chinese sources.
See desktop/fonts/README.md and desktop/FONT-SOURCES.md for provenance.
Roboto, Noto Sans JP, and Noto Sans CJK SC use SIL Open Font License 1.1; the
atlases carry that license too (see desktop/FONT-LICENSE.txt).
"""

import argparse
import base64
import functools
import hashlib
import io
import os
from pathlib import Path
import sys
import urllib.request

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
    # What the keyboard layouts in desktop/keyboard_layout.v can type, so a
    # letter typed in Russian, Spanish, French, German or Portuguese is drawn
    # rather than left as a gap: the Latin-1 letters and signs, the Russian
    # alphabet, and the few others on those layouts' keycaps.
    *range(0x00A1, 0x0100),  # ¡ .. ÿ  Latin-1 Supplement
    0x0152, 0x0153,          # Œ œ
    0x0178,                  # Ÿ
    0x0401,                  # Ё
    *range(0x0410, 0x0450),  # А .. я
    0x0451,                  # ё
    0x20AC,                  # € euro
    0x2116,                  # № numero
    0xFFFD,                  # � what Terminal shows for a malformed byte
]

FONT_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "..", "third_party", "ui2",
    "assets", "fonts",
)

# (name, file, logical pixel size, bold). The sizes are the ones the desktop's
# own chrome uses, those ui2's calculator example asks for (18 for its keys, 28
# for its display), and one monospaced face for the terminal. Each is baked at
# both 1x and 2x: enlarging an already-antialiased 1x mask makes its soft edge
# two physical pixels wide on a HiDPI panel.
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

RASTER_SCALES = [1, 2]

DESKTOP_DIR = Path(__file__).resolve().parent.parent
JAPANESE_FONT_DIR = DESKTOP_DIR / "fonts"
JAPANESE_CATALOG = DESKTOP_DIR / "translations" / "ja.tr"
JAPANESE_FONT_COMMIT = "295d98a7a0c17c68f1341eaeea354e7960ea70d3"
JAPANESE_FONT_URL = (
    "https://raw.githubusercontent.com/google/fonts/"
    + JAPANESE_FONT_COMMIT + "/ofl/notosansjp/NotoSansJP%5Bwght%5D.ttf"
)
JAPANESE_FONT_SHA256 = "c2f3b4d463500a2ddcd3849cded1fceeb9fd6d1c32e6cbecd568453ba50fc68f"

NATIVE_LABELS = "中文（简体）日本語"
CJK_REVISION = "523d033d6cb47f4a80c58a35753646f5c3608a78"
CJK_URL = ("https://raw.githubusercontent.com/notofonts/noto-cjk/"
           + CJK_REVISION + "/Sans/OTF/SimplifiedChinese/")
CJK_SOURCES = {
    "NotoSansCJKsc-Regular.otf": "2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b",
    "NotoSansCJKsc-Bold.otf": "b5f0d1a190a7f9b43c310a8850630af12553df32c4c050543f9059732d9b4c0a",
}


def catalog_runes(paths):
    characters = set()
    for path in paths:
        for block in path.read_text(encoding="utf-8").split("-----"):
            lines = block.strip().splitlines()
            if len(lines) >= 2:
                characters.update("\n".join(lines[1:]))
    return {ord(ch) for ch in characters if not ch.isspace() and ord(ch) > LAST_CHAR}


def translation_runes():
    return catalog_runes(sorted((DESKTOP_DIR / "translations").glob("*.tr"))) | {
        ord(ch) for ch in NATIVE_LABELS}


@functools.lru_cache(maxsize=None)
def chinese_runes():
    return catalog_runes([DESKTOP_DIR / "translations/zh.tr"]) | {
        ord(ch) for ch in "中文（简体）"}


def is_cjk(code_point):
    return (0x3000 <= code_point <= 0x303F
            or 0x3400 <= code_point <= 0x9FFF
            or 0xFF00 <= code_point <= 0xFFEF)


def is_chinese_glyph(code_point):
    return is_cjk(code_point) and code_point in chinese_runes()


@functools.lru_cache(maxsize=None)
def cjk_font_path(file_name):
    cache = Path(os.environ.get("VINIX_FONT_CACHE", Path.home() / ".cache/vinix/fonts"))
    path = cache / "noto-cjk-2.004" / file_name
    if not path.exists():
        print("Downloading %s..." % file_name)
        with urllib.request.urlopen(CJK_URL + file_name, timeout=60) as response:
            data = response.read()
        if hashlib.sha256(data).hexdigest() != CJK_SOURCES[file_name]:
            sys.exit("download checksum mismatch: %s" % file_name)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    if hashlib.sha256(path.read_bytes()).hexdigest() != CJK_SOURCES[file_name]:
        sys.exit("cached font checksum mismatch: %s" % path)
    return str(path)


@functools.lru_cache(maxsize=None)
def missing_glyph(font):
    return rasterise(font, NOTDEF_PROBE)


@functools.lru_cache(maxsize=None)
def japanese_runes():
    """The catalog and its native language name define the Japanese subset."""
    if not JAPANESE_CATALOG.exists():
        sys.exit("Japanese catalog not found: %s" % JAPANESE_CATALOG)
    text = JAPANESE_CATALOG.read_text(encoding="utf-8") + "日本語"
    return sorted({ord(ch) for ch in text if ord(ch) > LAST_CHAR})


def japanese_font_path(bold):
    return JAPANESE_FONT_DIR / ("VinixJapanese-%s.ttf" % ("Bold" if bold else "Regular"))


def update_japanese_subsets(runes, source_path=None):
    """Make small static regular/bold fonts from the pinned upstream variable font."""
    try:
        from fontTools import subset
        from fontTools.ttLib import TTFont
        from fontTools.varLib.instancer import instantiateVariableFont
    except ImportError:
        sys.exit("subset regeneration needs fontTools; see desktop/fonts/README.md")

    if source_path:
        source = Path(source_path).read_bytes()
    else:
        print("Downloading pinned Noto Sans JP source...")
        with urllib.request.urlopen(JAPANESE_FONT_URL, timeout=60) as response:
            source = response.read()
    if hashlib.sha256(source).hexdigest() != JAPANESE_FONT_SHA256:
        sys.exit("Noto Sans JP source SHA-256 does not match the pinned font")

    font = TTFont(io.BytesIO(source), recalcTimestamp=False)
    missing = set(runes) - font.getBestCmap().keys()
    if missing:
        sys.exit("upstream Japanese font lacks: " + ", ".join("U+%04X" % cp for cp in sorted(missing)))
    options = subset.Options()
    options.name_IDs += [13, 14, 16, 17]  # license, URL, typographic family/style
    # These are standalone masks: no runtime shaping or OpenType layout uses
    # the features, and keeping their alternate glyphs would inflate subsets.
    options.layout_features = []
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(unicodes=runes)
    subsetter.subset(font)
    JAPANESE_FONT_DIR.mkdir(exist_ok=True)
    for weight, bold in [(400, False), (700, True)]:
        static = instantiateVariableFont(font, {"wght": weight}, inplace=False)
        style = "Bold" if bold else "Regular"
        # Name the modified subsets clearly; keep upstream copyright/license
        # records. The original license reserves the name 'Source'.
        names = {
            1: "Vinix Japanese", 2: style, 3: "VinixJapanese-" + style,
            4: "Vinix Japanese " + style, 6: "VinixJapanese-" + style,
            16: "Vinix Japanese", 17: style,
        }
        for record in static["name"].names:
            if record.nameID in names:
                static["name"].setName(names[record.nameID], record.nameID,
                                       record.platformID, record.platEncID, record.langID)
        path = japanese_font_path(bold)
        static.save(path)
        print("wrote %s (%d bytes, %d characters)" % (path, path.stat().st_size, len(runes)))


@functools.lru_cache(maxsize=None)
def open_font(file_name, size):
    path = os.path.join(FONT_DIR, file_name)
    if not os.path.exists(path):
        sys.exit("font not found: %s" % path)
    return ImageFont.truetype(path, size)


@functools.lru_cache(maxsize=None)
def open_japanese_font(bold, size):
    path = japanese_font_path(bold)
    if not path.exists():
        sys.exit("Japanese subset not found: %s; run with --update-japanese-subsets" % path)
    return ImageFont.truetype(str(path), size)


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


@functools.lru_cache(maxsize=None)
def has_glyph(font, code_point):
    candidate = rasterise(font, code_point)
    return candidate != missing_glyph(font) and (candidate[0] != 0 or candidate[1] != 0)


def glyph_font(file_name, size, bold, code_point, japanese=None):
    # One atlas slot is shared across locales. Prefer Simplified Chinese shapes
    # for the Chinese catalog, while retaining JP shapes for Japanese-only text.
    if is_chinese_glyph(code_point):
        source = "NotoSansCJKsc-Bold.otf" if bold else "NotoSansCJKsc-Regular.otf"
        return open_font(cjk_font_path(source), size)
    font = open_font(file_name, size)
    if japanese is None:
        japanese = japanese_runes()
    if code_point in japanese and not has_glyph(font, code_point):
        return open_japanese_font(bold, size)
    return font


def supported_extras(faces, japanese, required=None):
    """Keep only real glyphs in every face and scale; require catalog coverage."""
    if required is None:
        required = translation_runes()
    kept = []
    for code_point in sorted(set(EXTRA_RUNES) | required | japanese):
        ok = True
        for _, file_name, size, bold in faces:
            for raster_scale in RASTER_SCALES:
                font = glyph_font(file_name, size * raster_scale, bold, code_point, japanese)
                if not has_glyph(font, code_point):
                    ok = False
                    break
            if not ok:
                break
        if ok:
            kept.append(code_point)
        elif code_point in required or code_point in japanese:
            sys.exit("translation needs missing glyph U+%04X (%s)" % (code_point, chr(code_point)))
        else:
            print("  dropped U+%04X (not in every face)" % code_point)
    return kept


def build_face(file_name, size, bold, raster_scale, extras, japanese):
    logical_font = open_font(file_name, size)
    font = open_font(file_name, size * raster_scale)
    ascent, descent = logical_font.getmetrics()

    header = bytearray()
    pixels = bytearray()
    for code_point in list(range(FIRST_CHAR, LAST_CHAR + 1)) + extras:
        raster_font = glyph_font(file_name, size * raster_scale, bold, code_point, japanese)
        advance_font = glyph_font(file_name, size, bold, code_point, japanese)
        width, height, bx, by, _, mask = rasterise(raster_font, code_point)
        # Keep layout exactly the same at both scales. FreeType hinting can
        # otherwise make a run baked at 26 px a different logical width from
        # the same run baked at 13 px.
        logical_advance = int(round(advance_font.getlength(chr(code_point))))
        advance = logical_advance * raster_scale
        if raster_font is not font:
            # Match Roboto's baseline and keep its existing line height. Noto's
            # own ascender would otherwise put Japanese text below the run.
            by += font.getmetrics()[0] - raster_font.getmetrics()[0]
            if "Mono" in file_name:
                # CJK fallback characters take two terminal cells, centered in
                # that space; ASCII and the other existing glyphs stay fixed.
                advance = 2 * int(round(logical_font.getlength("M"))) * raster_scale
                bx += (advance - logical_advance * raster_scale) // 2
            line_height = (ascent + descent) * raster_scale
            if is_chinese_glyph(code_point):
                if height > line_height:
                    sys.exit("Chinese glyph U+%04X exceeds the %dpx line box" % (code_point, size))
                by = max(0, min(by, line_height - height))
            elif by < 0 or by + height > line_height:
                sys.exit("Japanese glyph U+%04X exceeds the %dpx line box" % (code_point, size))
        if bx < -128 or bx > 127:
            sys.exit("left bearing out of range for U+%04X" % code_point)
        if not all(0 <= value <= 255 for value in [width, height, advance]):
            sys.exit("glyph metrics out of range for U+%04X" % code_point)
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
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--update-japanese-subsets", action="store_true",
                        help="download the pinned source and update Japanese font subsets")
    parser.add_argument("--japanese-source", metavar="TTF",
                        help="use a local copy of the pinned upstream font for subset regeneration")
    args = parser.parse_args()
    if args.japanese_source and not args.update_japanese_subsets:
        parser.error("--japanese-source requires --update-japanese-subsets")
    japanese = set(japanese_runes())
    if args.update_japanese_subsets:
        update_japanese_subsets(japanese, args.japanese_source)
    print("Checking supplemental runes...")
    extras = supported_extras(FACES, japanese)
    print("  kept %d supplemental runes, including %d Japanese catalog characters" % (len(extras), len(japanese)))

    out = []
    out.append("// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.")
    out.append("// Use of this source code is governed by a GPL v2 license")
    out.append("// that can be found in the LICENSE file.")
    out.append("")
    out.append("// Generated by desktop/tools/genfont.py. Do not edit by hand.")
    out.append("//")
    out.append("// Coverage atlases for Roboto with Noto Sans JP and CJK SC fallback; the")
    out.append("// binary needs no font files. Glyph data uses the SIL Open Font License")
    out.append("// 1.1; see desktop/FONT-LICENSE.txt and desktop/FONT-SOURCES.md.")
    out.append("module main")
    out.append("")
    out.append("// FaceBlob is one rasterised face. `bold`, logical `size` and `raster_scale`")
    out.append("// are how the renderer picks between faces. `ascent` + `descent`")
    out.append("// is the height of a line. `parts` join into base64 of a metrics header")
    out.append("// (width, height, left bearing, top bearing, advance for each glyph)")
    out.append("// followed by every glyph's coverage bytes in the same order. It is split")
    out.append("// because a single literal this long, spelled as one concatenation,")
    out.append("// exceeds what V's checker will descend into.")
    out.append("struct FaceBlob {")
    out.append("\tbold    bool")
    out.append("\tmono    bool")
    out.append("\tsize    int")
    out.append("\traster_scale int")
    out.append("\tascent  int")
    out.append("\tdescent int")
    out.append("\tparts   []string")
    out.append("}")
    out.append("")
    out.append("// Glyph slots run over printable ASCII first, then over these code points")
    out.append("// in this order, in every face. The list is ascending.")
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
    for raster_scale in RASTER_SCALES:
        for name, file_name, size, bold in FACES:
            face = build_face(file_name, size, bold, raster_scale, extras, japanese)
            scaled_name = "%s_%dx" % (name, raster_scale)
            names.append(scaled_name)
            out.append("// %s: %s at %dpx (%dx raster)" %
                       (name, file_name, size, raster_scale))
            out.append("const face_%s = FaceBlob{" % scaled_name)
            out.append("\tbold:    %s" % ("true" if bold else "false"))
            out.append("\tmono:    %s" % ("true" if "Mono" in file_name else "false"))
            out.append("\tsize:    %d" % size)
            out.append("\traster_scale: %d" % raster_scale)
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
