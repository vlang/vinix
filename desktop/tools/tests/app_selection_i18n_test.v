// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn test_setup_translations_are_complete_and_every_glyph_is_bundled() {
	fonts := load_fonts()
	for key, english in desktop_translations['en'] {
		if !key.starts_with('app_selection.') { continue }
		assert english.len > 0
		for language in desktop_languages {
			text := desktop_translations[language.code()][key]
			assert text.len > 0, '${language.code()} lacks ${key}'
			for r in text.runes() {
				if r in [` `, `\n`, `\t`, `\r`] { continue }
				for face in fonts {
					glyph := face.glyph_for(u32(r))
					assert glyph.width > 0 && glyph.height > 0, '${language.code()} ${key}: no glyph for ${r}'
				}
			}
		}
	}
}
