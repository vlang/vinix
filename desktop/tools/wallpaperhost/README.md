`../fetch_wallpapers OUTPUT_DIR [--cache DIR]` builds the wallpaper set in V.
It needs curl and libjpeg-turbo's `libturbojpeg` development package, discoverable
through pkg-config (`brew install jpeg-turbo` on macOS). Both desktop image
builders invoke this native entry point.

The ten pinned JPEG photographs are decoded with accurate DCT, cropped to 4:3,
resampled with normalized Lanczos-3 coefficients at 22-bit precision, and stored
as 512×384 RGB in VWP1. The coefficient normalization and pass rounding follow
the [Pillow resampler](https://github.com/python-pillow/Pillow/blob/12.0.0/src/libImaging/Resample.c).
The decoder supports JPEG; other Pillow image formats are outside this command's
pinned input set. Curl retains the original certificate fallback and user agent,
using connection and transfer-stall limits rather than urllib read timeouts.

Warm caches work offline. Failed downloads remove partial files; malformed cached
images remain available for diagnosis. Failed conversions do not enter the index,
and existing wallpaper files outside the index remain untouched. Index labels and
source attribution retain their original byte layout.

`wallpaper-check.v CAPTURES OUTPUT` compares all ten images against hash-qualified
original JPEG/VWP pairs. `wallpaper-test.v CAPTURES NEW_TEST_DIR` checks geometry,
constant resampling, cache failures, exact indexes and attribution, malformed
decoder retirement, streamed downloads and partial-file cleanup. ARM, Rosetta x86
and ASan/UBSan match all 5,898,330 captured output bytes. No Python or Vinix guest
is executed. Qualification retains the official libjpeg-turbo 3.2.0 x86 SDK build
and source hash separately from this repository.

`qualify-wallpapers.v COMPILER CAPTURES NEW_EVIDENCE arm|x86|san [X86_JPEG_SDK]`
performs three cold builds and those checks, then verifies the whole CLI's warm
cache, outputs, help and argument guard. The x86 SDK directory contains
`include/turbojpeg.h` and `lib/libturbojpeg.a` built for x86_64.
