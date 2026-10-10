# Native screenshot checks

`build-support/check-screenshot SHOT.{ppm,png}` reports the desktop brightness
and sampled palette. `--changed BEFORE AFTER MIN_PIXELS` compares RGB pixels,
ignoring alpha, and succeeds when the screen changes size or enough pixels
differ. The ISO boot test invokes this V command directly.

The decoder retains binary P6's one-byte separator, RGB/RGBA PNG support,
all five PNG filters, split IDAT chunks, brightness and palette thresholds,
and percentage rounding to even. Like the previous tool, PNG CRCs are ignored
and unknown scanline filters are treated as unfiltered data. Truncated headers
and pixels, missing PNG headers and oversized dimensions now return a read
error instead of hanging or indexing beyond the image. Invalid compressed
streams use V's zlib diagnostics; these need not match the old exception text.

```sh
v -cc cc test build-support/screenshotcore
v -cc cc -o /tmp/check-screenshot build-support/check-screenshot.v
VINIX_SCREENSHOT_TOOL=/tmp/check-screenshot v -cc cc test build-support/screenshotcore
```

Native tests decode 144 independently filtered RGB/RGBA fixtures, check PPM
comments and pixel whitespace, unsupported and truncated images, desktop
thresholds, alpha-independent comparisons, and command output/exit codes.
The optional executable check can target a separately built ARM or x86 host
binary. These checks establish host screenshot behavior; they do not boot a VM.
