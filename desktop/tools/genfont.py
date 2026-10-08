#!/usr/bin/env python3
"""Import/CLI compatibility for the native font atlas generator."""
import argparse
import importlib.util
import os
import operator
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("vinix_font_native", _HERE / "_font_native.py")
_native = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_native)
globals().update(_native.call("constants"))
__doc__ = _native.call("description")
FACES = [tuple(face) for face in FACES]
FONT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "third_party", "ui2", "assets", "fonts")
DESKTOP_DIR = _HERE.parent
JAPANESE_FONT_DIR = DESKTOP_DIR / "fonts"
JAPANESE_CATALOG = DESKTOP_DIR / "translations/ja.tr"


def _context():
    return {"fonts": os.fsencode(FONT_DIR).hex(), "desktop": os.fsencode(DESKTOP_DIR).hex(),
            "japanese_fonts": os.fsencode(JAPANESE_FONT_DIR).hex(),
            "japanese_catalog": os.fsencode(JAPANESE_CATALOG).hex(),
            "cache": os.fsencode(Path(os.environ.get("VINIX_FONT_CACHE", Path.home() / ".cache/vinix/fonts"))).hex(),
            "target": os.fsencode(DESKTOP_DIR / "font_data.v").hex(),
            "cjk_sources": CJK_SOURCES, "cjk_url": CJK_URL, "japanese_url": JAPANESE_FONT_URL,
            "japanese_sha256": JAPANESE_FONT_SHA256, "extra_runes": EXTRA_RUNES,
            "faces": FACES, "scales": RASTER_SCALES}


def _call(operation, **arguments):
    return _native.call(operation, arguments, _context())


def catalog_runes(paths):
    return set(_call("catalog", paths=[os.fsencode(p).hex() for p in paths]))


def translation_runes():
    return set(_call("translations"))


def chinese_runes():
    return set(_call("chinese"))


def is_cjk(code_point):
    return _call("is_cjk", code_point=code_point)


def is_chinese_glyph(code_point):
    return _call("is_chinese", code_point=code_point)


def cjk_font_path(file_name):
    return os.fsdecode(bytes.fromhex(_call("cjk_path", file=file_name)))


def japanese_runes():
    return _call("japanese")


def japanese_font_path(bold):
    return Path(os.fsdecode(bytes.fromhex(_call("japanese_path", bold=bold))))


def update_japanese_subsets(runes, source_path=None):
    _call("update_japanese", runes=list(runes), source=os.fsencode(source_path).hex() if source_path else "")


def open_font(file_name, size):
    return _native._lookup(_call("open", file=file_name, size=size))


def open_japanese_font(bold, size):
    return _native._lookup(_call("open_japanese", bold=bold, size=size))


def _glyph(value):
    return tuple(value[:4]) + (int(value[4]), bytes.fromhex(value[5]))


def rasterise(font, code_point):
    return _glyph(_native.call_font("raster", font, {"code_point": code_point}, _context()))


def missing_glyph(font):
    return _glyph(_native.call_font("missing", font, {}, _context()))


def has_glyph(font, code_point):
    return _native.call_font("has", font, {"code_point": code_point}, _context())


def glyph_font(file_name, size, bold, code_point, japanese=None):
    key = _call("glyph_font", file=file_name, size=size, bold=bold, code_point=code_point,
                japanese=list(japanese) if japanese is not None else None)
    return _native._lookup(key)


def supported_extras(faces, japanese, required=None):
    return _call("supported", faces=faces, japanese=list(japanese), required=list(required) if required is not None else None)


def build_face(file_name, size, bold, raster_scale, extras, japanese):
    return _call("face", file=file_name, size=size, bold=bold, scale=raster_scale, extras=extras, japanese=list(japanese))


def wrap(text, width=100):
    return [bytes.fromhex(part).decode("utf-8", "surrogatepass")
            for part in _call("wrap", text_hex=text.encode("utf-8", "surrogatepass").hex(),
                              width_decimal=str(operator.index(width)))]


for _name in ("chinese_runes", "japanese_runes", "cjk_font_path", "missing_glyph", "has_glyph", "open_font", "open_japanese_font"):
    globals()[_name].cache_clear = lambda name=_name: _call("clear", name=name)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--update-japanese-subsets", action="store_true",
                        help="download the pinned source and update Japanese font subsets")
    parser.add_argument("--japanese-source", metavar="TTF",
                        help="use a local copy of the pinned upstream font for subset regeneration")
    args = parser.parse_args()
    if args.japanese_source and not args.update_japanese_subsets:
        parser.error("--japanese-source requires --update-japanese-subsets")
    _call("generate", update=args.update_japanese_subsets,
          source=os.fsencode(args.japanese_source).hex() if args.japanese_source else "")


if __name__ == "__main__":
    main()
