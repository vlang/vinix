#!/usr/bin/env python3
"""Download the desktop's wallpaper photographs and convert them for Vinix.

Vinix has no JPEG or PNG decoder, and writing one to show a backdrop would be
a strange place to spend the effort. So the decoding happens here, at build
time, and the target gets raw pixels it can blit: each image becomes a `.vwp`
file, which is a nine byte header and then packed RGB.

They are stored at half the display's resolution and scaled up when drawn. A
photograph survives that at the size a wallpaper is looked at, and it keeps the
ten of them to about six megabytes rather than twenty-three.

    python3 desktop/tools/fetch_wallpapers.py <output-dir> [--cache DIR]

Downloads are cached, so a rebuild costs nothing and an offline build still
works once the cache is warm. With neither network nor cache the script says so
and writes no images; the desktop then offers only its colours, which is a
worse desktop but a working one.

The photographs come from Lorem Picsum, which serves them from Unsplash under
the Unsplash License (https://unsplash.com/license): free to use, including
commercially, without permission or attribution. The ids are pinned so a build
is reproducible, and each image's source URL is recorded beside it.
"""

import argparse
import os
import ssl
import sys
import urllib.error
import urllib.request

from PIL import Image

# Pinned so every build gets the same ten pictures. Landscape photographs that
# read well behind windows: no busy foregrounds, no text.
PICSUM_IDS = [1015, 1016, 1018, 1019, 1024, 1036, 1039, 1043, 1047, 1057]

SOURCE = "https://picsum.photos/id/%d/1024/768"

# Half of 1024x768. The renderer doubles it.
STORED_WIDTH = 512
STORED_HEIGHT = 384

MAGIC = b"VWP1"


def download(url, destination):
    request = urllib.request.Request(url, headers={"User-Agent": "vinix-desktop/1"})
    # Some macOS Python builds have no usable certificate store; a wallpaper is
    # not worth failing the build over an unverifiable certificate.
    context = ssl.create_default_context()
    try:
        with urllib.request.urlopen(request, timeout=30, context=context) as response:
            data = response.read()
    except (ssl.SSLError, urllib.error.URLError):
        context = ssl._create_unverified_context()
        with urllib.request.urlopen(request, timeout=30, context=context) as response:
            data = response.read()
    if not data:
        raise urllib.error.URLError("empty response")
    with open(destination, "wb") as handle:
        handle.write(data)


def convert(source_path, destination_path):
    """Write a .vwp: 'VWP1', width and height as little-endian u16, then RGB."""
    image = Image.open(source_path).convert("RGB")
    # Cover rather than stretch: crop to the target aspect first, so nothing is
    # distorted by an image that is not exactly 4:3.
    target = STORED_WIDTH / STORED_HEIGHT
    width, height = image.size
    if width / height > target:
        crop_width = int(height * target)
        left = (width - crop_width) // 2
        image = image.crop((left, 0, left + crop_width, height))
    else:
        crop_height = int(width / target)
        top = (height - crop_height) // 2
        image = image.crop((0, top, width, top + crop_height))
    image = image.resize((STORED_WIDTH, STORED_HEIGHT), Image.LANCZOS)

    with open(destination_path, "wb") as handle:
        handle.write(MAGIC)
        handle.write(STORED_WIDTH.to_bytes(2, "little"))
        handle.write(STORED_HEIGHT.to_bytes(2, "little"))
        handle.write(b"\x00")  # reserved, keeps the header at nine bytes
        handle.write(image.tobytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("output_dir")
    parser.add_argument("--cache", default=None,
                        help="where downloads are kept between builds")
    options = parser.parse_args()
    output_dir = options.output_dir
    cache_dir = options.cache or os.path.join(output_dir, ".cache")

    os.makedirs(output_dir, exist_ok=True)
    os.makedirs(cache_dir, exist_ok=True)

    written = []
    for slot, picsum_id in enumerate(PICSUM_IDS):
        cached = os.path.join(cache_dir, "%d.jpg" % picsum_id)
        if not os.path.exists(cached) or os.path.getsize(cached) == 0:
            url = SOURCE % picsum_id
            try:
                download(url, cached)
                print("    downloaded %s" % url)
            except Exception as error:  # noqa: BLE001 - any failure is the same failure
                print("    SKIPPED id %d: %s" % (picsum_id, error))
                if os.path.exists(cached):
                    os.remove(cached)
                continue

        destination = os.path.join(output_dir, "%02d.vwp" % slot)
        try:
            convert(cached, destination)
        except Exception as error:  # noqa: BLE001
            print("    SKIPPED id %d: cannot convert: %s" % (picsum_id, error))
            continue
        written.append((slot, picsum_id))

    # An index the desktop reads to know what is there, so adding or losing an
    # image needs no rebuild of the binary.
    with open(os.path.join(output_dir, "index.txt"), "w") as handle:
        for slot, picsum_id in written:
            handle.write("%02d.vwp Photo %d\n" % (slot, slot + 1))

    with open(os.path.join(output_dir, "SOURCES.txt"), "w") as handle:
        handle.write("Wallpapers from Lorem Picsum (https://picsum.photos), which\n")
        handle.write("serves photographs from Unsplash under the Unsplash License\n")
        handle.write("(https://unsplash.com/license).\n\n")
        for slot, picsum_id in written:
            handle.write("%02d.vwp  %s\n" % (slot, SOURCE % picsum_id))

    print("    %d wallpaper(s) in %s" % (len(written), output_dir))
    if not written:
        print("    (no network and no cache: the desktop will offer colours only)")


if __name__ == "__main__":
    main()
