#!/usr/bin/env python3
"""Build high-resolution Vinix application icons from official app artwork.

The compositor deliberately has no PNG/SVG decoder. At image-build time this
tool selects the largest official icon already staged by each application (or a
pinned upstream fallback in desktop/app-icon-fallbacks), rasterizes it into a
256x256 RGBA square, and writes a tiny .vai file:

    VAI1 + little-endian u16 width + u16 height + one reserved byte + RGBA

A missing icon is harmless: the renderer keeps the existing builtin glyph.
"""

import argparse
import glob
import os

from PIL import Image

SIZE = 256
MAGIC = b"VAI1"

SPECS = {
    "firefox": [
        "usr/share/icons/hicolor/*x*/apps/firefox*.png",
        "usr/lib/firefox*/browser/chrome/icons/default/default*.png",
    ],
    "chromium": [
        "usr/share/icons/hicolor/*x*/apps/chromium*.png",
        "usr/share/icons/hicolor/*x*/apps/org.chromium*.png",
        "usr/lib/chromium/product_logo_*.png",
    ],
    "blender": [
        "usr/share/icons/hicolor/*x*/apps/blender*.png",
    ],
    "gimp": [
        "usr/share/icons/hicolor/*x*/apps/gimp*.png",
        "usr/share/icons/hicolor/*x*/apps/org.gimp*.png",
    ],
    "libreoffice": [
        "usr/share/icons/hicolor/*x*/apps/libreoffice-startcenter*.png",
        "usr/share/icons/hicolor/*x*/apps/libreoffice-main*.png",
        "usr/share/icons/hicolor/*x*/apps/startcenter*.png",
    ],
}

FALLBACK_NAMES = {
    "firefox": "firefox.png",
    "chromium": "chromium.png",
    "blender": "blender.ico",
    "gimp": "gimp.ico",
    "libreoffice": "libreoffice.png",
}


def load_candidate(path):
    try:
        image = Image.open(path)
        image.load()
        return image.convert("RGBA")
    except Exception:
        return None


def best_icon(root, fallback_dir, key):
    candidates = []
    for pattern in SPECS[key]:
        candidates.extend(glob.glob(os.path.join(root, pattern)))
    fallback = FALLBACK_NAMES.get(key)
    if fallback:
        fallback_path = os.path.join(fallback_dir, fallback)
        if os.path.isfile(fallback_path):
            candidates.append(fallback_path)

    best = None
    best_path = None
    best_score = (-1, -1)
    for path in sorted(set(candidates)):
        image = load_candidate(path)
        if image is None:
            continue
        score = (min(image.size), image.size[0] * image.size[1])
        if score > best_score:
            best = image
            best_path = path
            best_score = score
    return best, best_path


def fit_square(image):
    image.thumbnail((SIZE, SIZE), Image.LANCZOS)
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    x = (SIZE - image.size[0]) // 2
    y = (SIZE - image.size[1]) // 2
    out.alpha_composite(image, (x, y))
    return out


def write_vai(image, destination):
    image = fit_square(image)
    with open(destination, "wb") as handle:
        handle.write(MAGIC)
        handle.write(SIZE.to_bytes(2, "little"))
        handle.write(SIZE.to_bytes(2, "little"))
        handle.write(b"\x00")
        handle.write(image.tobytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("output_dir")
    parser.add_argument("--root", required=True, help="assembled desktop filesystem root")
    parser.add_argument("--fallback-dir", required=True)
    options = parser.parse_args()

    os.makedirs(options.output_dir, exist_ok=True)
    for old in glob.glob(os.path.join(options.output_dir, "*.vai")):
        os.remove(old)

    used = []
    for key in SPECS:
        image, source = best_icon(options.root, options.fallback_dir, key)
        if image is None:
            print("    %s: no official icon found; builtin fallback remains" % key)
            continue
        destination = os.path.join(options.output_dir, key + ".vai")
        write_vai(image, destination)
        if os.path.commonpath([os.path.abspath(source), os.path.abspath(options.root)]) == os.path.abspath(options.root):
            recorded = "package:" + os.path.relpath(source, options.root)
        elif os.path.commonpath([os.path.abspath(source), os.path.abspath(options.fallback_dir)]) == os.path.abspath(options.fallback_dir):
            recorded = "fallback:" + os.path.basename(source)
        else:
            recorded = source
        used.append((key, recorded))
        print("    %s <- %s" % (key, recorded))

    with open(os.path.join(options.output_dir, "SOURCES.txt"), "w") as handle:
        handle.write("Application icons are official application artwork.\n")
        handle.write("Package paths are relative to the assembled Vinix image.\n")
        handle.write("Fallback sources are recorded in desktop/app-icon-fallbacks/SOURCES.txt.\n\n")
        for key, source in used:
            handle.write("%s  %s\n" % (key, source))


if __name__ == "__main__":
    main()
