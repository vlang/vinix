# Desktop translations

One file per language the desktop speaks, named by its code: `en.tr`
(English, the reference), `ru.tr` (Russian), `es.tr` (Spanish), `fr.tr`
(French), `ja.tr` (Japanese) and `zh.tr` (Simplified Chinese). They use the `.tr`
format of V's `i18n` module: a key line, the text, and a `-----` line between entries.

```
settings.category.language
Язык
-----
files.items
{0} элемент|{0} элемента|{0} элементов
```

The build compiles these files in (`desktop/tools/stage_app.py` turns them
into `translations_data.v`), and [translations.v](../translations.v) loads
them with `i18n.load_tr_map_from_files` and looks text up with `tr()`.

## Writing entries

- Keys are lowercase and dot-separated, grouped by area (`settings.`,
  `files.`, `date.`, ...). Sources name them literally, as in
  `tr('files.items')`, so the tests can check every key exists.
- `{0}`, `{1}` and `{2}` are where values go. A translation keeps the same
  placeholders but may reorder them.
- Text containing `|` is a plural: complete forms, chosen by the count.
  English and Spanish give two forms (one, other); French gives two (zero or
  one, other); Russian gives three (one, few, many: 1 and 21 элемент,
  2–4 элемента, 5–20 элементов). Japanese and Chinese use one form for every
  count, without `|`.
- Keep ordinary labels on one line and about as short as the English: the
  desktop's labels have fixed widths. Compact Grapher help uses three catalog
  lines, rendered as three separate labels; preserve those line breaks.
- Product names (Firefox, Wine, QEMU, macOS...) are not translated.

The desktop's fonts carry ASCII, Latin-1, Russian Cyrillic, and the Japanese
and Chinese characters used by the translations (`tools/genfont.py`). Noto
Sans JP and Noto Sans CJK SC provide the fallback glyphs. After changing
translations or adding a language, regenerate the fonts so every character
is included.

`tools/tests/i18n_test.v` checks that every file defines exactly the English
keys, that placeholders and plural forms match, that every key the sources use
exists, and that the fonts can draw every letter. It also fails on literal
words handed to the UI helpers (`ui2.label`, `ui2.button`, `settings_note`,
`heading`, ...), naming the file and line, so new text cannot skip the
translations; product names that read the same everywhere are listed in
`i18n_untranslated_names`.

## Adding a language

1. Add it to `DesktopLanguage` and `desktop_languages` in
   [settings_model.v](../settings_model.v), with its code and its own name.
2. Add `<code>.tr` with every key of `en.tr`.
3. Give it a plural rule in `desktop_plural_index` in
   [translations.v](../translations.v), and bake any letters it needs into the
   fonts.
