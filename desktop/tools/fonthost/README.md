The native font generator owns catalog coverage, fallback selection, cache
policy, pinned checksums, ties-to-even advances, metric validation, atlas
packing, subset names and publication order. `font_query.v` runs that policy
with synchronous library callbacks. `genfont.py` preserves the import/CLI API;
`_font_native.py` binds Pillow, fontTools and urllib without choosing glyphs or
assembling atlases. The existing invocation remains:

```sh
python3 desktop/tools/genfont.py
```

Pillow owns rasterization and fontTools owns font parsing, subsetting and
variable-font instantiation. Library objects use explicit cache owners;
temporary raster calls borrow their font only for the synchronous request.
Cache clearing retires its owner independently, and controller failure closes
remaining library objects and its private installer directory.

Qualification uses the frozen original generator and unchanged baked-font
tests on ARM64, x86-64 and with ASan/UBSan. It compares complete atlas bytes,
fallback identity, Unicode boundaries, malformed catalogs, missing fonts,
wide advances, metric errors and library-object retirement. Subset comparisons
use the pinned upstream source and the same fontTools version. Generated
desktop font data and font license/provenance records are separate artifacts.
