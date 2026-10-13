The maintained generator is [`../genfont`](../genfont), implemented in V.
This module owns catalog coverage, fallback selection, pinned source checksums,
ties-to-even advances, metric validation, atlas packing, subset names and
publication order. `fontnative` supplies direct FreeType/HarfBuzz SDK effects
with explicit font, mask and SFNT owners. Its callback is installed only for
the synchronous operation and restored before the context retires.

```sh
desktop/tools/genfont
desktop/tools/genfont --update-japanese-subsets
desktop/tools/tests/test_font_data
```

The command uses FreeType 2.13.3 and HarfBuzz 14.5.0. `fontkit` verifies pinned
source archives, builds static SDKs with CMake and publishes hash-qualified
headers/libraries. The cache is under `VINIX_FONT_CACHE` (default
`~/.cache/vinix/fonts`). Initial SDK builds require CMake, a C/C++ compiler,
curl and tar. Subsequent invocations verify and reuse the cache. An existing
qualified SDK directory can be supplied through `VINIX_FONT_SDK`.

The renderer retains the saved atlas's direct character layout and hinted
advances, including U+00AD. Static subset instantiation preserves the
[original overlap flags](https://github.com/fonttools/fonttools/blob/4.60.1/Lib/fontTools/varLib/instancer/__init__.py),
names, license records and source timestamps. SFNT directories, bounds and
checksums are handled in V. Regenerated subset files may use different table
packing; every glyph's mask and header matches the captured atlas.

`qualify-fonts.v COMPILER CAPTURES SDK NEW_EVIDENCE arm|x86|san` cold-builds
seven programs and checks all 20,672 captured glyph masks and headers across
16 faces, normal and subset-regenerating CLI workflows, translated atlas tests,
SDK owner/error retirement, coverage/names/timestamps/checksums, previews and
the native driver. SDK libraries are external dependencies; sanitizers instrument
the V implementation. No Python or Vinix guest is executed.

The old `font_query.v` wire protocol remains as a historical V interface.
Maintained commands invoke the direct native context. The Python import API
and primitive adapter are retired after qualification.
