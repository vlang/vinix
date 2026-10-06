# Japanese desktop glyphs

`VinixJapanese-Regular.ttf` and `VinixJapanese-Bold.ttf` are small static
subsets of [Noto Sans JP](https://github.com/google/fonts/tree/295d98a7a0c17c68f1341eaeea354e7960ea70d3/ofl/notosansjp),
at weights 400 and 700. They carry only non-ASCII characters in
`desktop/translations/ja.tr` and the native language name `日本語`.
The modified fonts use the family name "Vinix Japanese". The upstream
copyright and SIL Open Font License records remain in the font metadata;
the license is also in [FONT-LICENSE.txt](../FONT-LICENSE.txt).

The source is `NotoSansJP[wght].ttf` from Google Fonts commit
`295d98a7a0c17c68f1341eaeea354e7960ea70d3`, with SHA-256:

```text
c2f3b4d463500a2ddcd3849cded1fceeb9fd6d1c32e6cbecd568453ba50fc68f
```

The upstream font project is
[notofonts/noto-cjk](https://github.com/notofonts/noto-cjk).
The upstream [OFL notice](https://github.com/google/fonts/blob/295d98a7a0c17c68f1341eaeea354e7960ea70d3/ofl/notosansjp/OFL.txt)
names Adobe as copyright holder and reserves the font name "Source".

## Regeneration

Normal atlas generation needs Pillow and the bundled subsets. When a
translation adds Japanese characters, update the subsets and atlas together.
From the repository root, using the versions used for these files:

```sh
python3 -m venv /tmp/vinix-fonts-venv
/tmp/vinix-fonts-venv/bin/pip install Pillow==11.3.0 fonttools==4.60.1
/tmp/vinix-fonts-venv/bin/python desktop/tools/genfont.py --update-japanese-subsets
```

The update downloads the pinned upstream font and verifies its SHA-256 before
subsetting and instantiating regular/bold faces. To regenerate offline, pass
`--japanese-source /path/to/NotoSansJP.ttf` with the same verified upstream
file. Font timestamps are preserved to make subset regeneration reproducible.
The generated subsets and `desktop/font_data.v` must be committed together.

The generator uses Japanese fallback only when Roboto lacks a catalog glyph,
preserving existing Latin and Cyrillic masks and metrics. It aligns the
fallback to Roboto's baseline and preserves the desktop's line heights and
logical advances at both 1x and 2x. Japanese glyphs in the monospaced face
advance by two existing terminal cells. Missing Japanese glyphs or a glyph
that exceeds the line box fail generation instead of silently making a gap.
