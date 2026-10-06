# Desktop font sources

`font_data.v` embeds coverage masks derived from the following fonts under
the SIL Open Font License 1.1. Copyright notices and the license are in
`FONT-LICENSE.txt`.

Roboto regular, bold, and Roboto Mono regular come from the existing
`third_party/ui2/assets/fonts/` checkout. The generator keeps these glyphs and
their line metrics for Latin and Cyrillic text.

Japanese-only characters use the existing bundled Noto Sans JP regular and
bold subsets in `desktop/fonts/`. Their pinned sources, license notices, and
subset regeneration instructions are in [fonts/README.md](fonts/README.md).
The generator preserves their fallback selection and two-cell terminal
advances. Chinese catalog CJK characters use the Simplified Chinese source
below, including characters shared with Japanese: each codepoint has one
shared glyph slot across locales.

Chinese ideographs and punctuation use the regular and bold Simplified
Chinese faces of [Noto Sans CJK 2.004](https://github.com/notofonts/noto-cjk/releases/tag/Sans2.004).
The source revision is `523d033d6cb47f4a80c58a35753646f5c3608a78`. These are
the unmodified upstream OTF files:

| File | SHA-256 |
| --- | --- |
| [NotoSansCJKsc-Regular.otf](https://raw.githubusercontent.com/notofonts/noto-cjk/523d033d6cb47f4a80c58a35753646f5c3608a78/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf) | `2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b` |
| [NotoSansCJKsc-Bold.otf](https://raw.githubusercontent.com/notofonts/noto-cjk/523d033d6cb47f4a80c58a35753646f5c3608a78/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Bold.otf) | `b5f0d1a190a7f9b43c310a8850630af12553df32c4c050543f9059732d9b4c0a` |

The [upstream license](https://raw.githubusercontent.com/notofonts/noto-cjk/523d033d6cb47f4a80c58a35753646f5c3608a78/LICENSE)
is SIL OFL 1.1. The font's copyright notice is “© 2014-2021 Adobe
(http://www.adobe.com/).”

Run `python3 desktop/tools/genfont.py` from the repository root. Python Pillow
is required. The generator downloads Noto source fonts on the first run and
checks their hashes, including on later runs. They are cached in
`~/.cache/vinix/fonts/noto-cjk-2.004/`; set `VINIX_FONT_CACHE` to override the
`~/.cache/vinix/fonts` directory. Copy verified source files to that cache to
regenerate offline. Font objects are reused throughout generation.

The generator derives the repertoire from values in `desktop/translations/*.tr`
and the native language selector names `中文（简体）` and `日本語`. Each character
appears in every size and weight at 1x and 2x, with identical logical advances across
scales. The atlas includes only the Chinese characters the UI needs, keeping
the runtime binary smaller than embedding complete CJK fonts.

Run `python3 desktop/tools/tests/test_font_data.py` to verify catalog coverage,
real glyph masks, line bounds, face weights, and scale metrics. Setting
`VINIX_FONT_PREVIEW=/tmp/vinix-fonts.png` also writes a preview rendered from
the actual baked atlas data.
