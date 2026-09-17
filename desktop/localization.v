// SPDX-License-Identifier: GPL-2.0-or-later
// Desktop localization. User-facing ui2 text is translated at the renderer
// boundary, so compositor chrome and every native application share one
// catalogue without each application growing its own translation mechanism.
module main

import i18n

const desktop_i18n_language_names = ['en', 'ru']
const desktop_i18n_search_dirs = ['/usr/share/vinix/translations', '/root/desktop/translations',
	'desktop/translations', 'translations']

__global (
	desktop_i18n_loaded bool
	desktop_i18n_language SystemLanguage
	desktop_i18n_translations map[string]map[string]string
	desktop_i18n_english_keys map[string]string
)

fn desktop_language_name(language SystemLanguage) string {
	index := int(language)
	if index < 0 || index >= desktop_i18n_language_names.len {
		return 'en'
	}
	return desktop_i18n_language_names[index]
}

// load once per process. The installed catalogue is preferred, while the
// source-tree paths keep host tests and the source copy shipped in /root useful.
fn desktop_i18n_load() {
	if desktop_i18n_loaded {
		return
	}
	desktop_i18n_loaded = true
	for directory in desktop_i18n_search_dirs {
		candidate := i18n.load_tr_map_from_dir(directory)
		if 'en' !in candidate || candidate['en'].len == 0 {
			continue
		}
		desktop_i18n_translations = candidate
		break
	}
	if 'en' !in desktop_i18n_translations {
		return
	}
	desktop_i18n_english_keys = map[string]string{}
	for key, text in desktop_i18n_translations['en'] {
		// Duplicate English spellings are intentionally resolved to the first
		// key. They have the same visible source text, so either translation key
		// is equivalent at the ui2 renderer boundary.
		if text !in desktop_i18n_english_keys {
			desktop_i18n_english_keys[text] = key
		}
	}
}

fn desktop_i18n_set_language(language SystemLanguage) {
	desktop_i18n_language = language
	desktop_i18n_load()
}

// Explicit-key lookup for code that already has a semantic translation key.
// V's builtin i18n module remains the source of truth and supplies its normal
// English fallback when a newly added Russian string has not landed yet.
fn desktop_tr(key string) string {
	desktop_i18n_load()
	language := desktop_language_name(desktop_i18n_language)
	if language in desktop_i18n_translations && key in desktop_i18n_translations[language] {
		return i18n.tr_from_map(desktop_i18n_translations, language, key)
	}
	if 'en' in desktop_i18n_translations && key in desktop_i18n_translations['en'] {
		return i18n.tr_from_map(desktop_i18n_translations, 'en', key)
	}
	return key
}

// ui2 applications historically supplied English literals. The renderer maps
// that English catalogue value back to its key, then asks V's builtin i18n for
// the selected language. This makes the migration exhaustive without changing
// ui2's Element API or allocating translated strings every frame.
fn desktop_i18n_text(text string) string {
	if text.len == 0 || desktop_i18n_language == .en {
		return text
	}
	desktop_i18n_load()
	key := desktop_i18n_english_keys[text] or { return text }
	language := desktop_language_name(desktop_i18n_language)
	if language !in desktop_i18n_translations || key !in desktop_i18n_translations[language] {
		return text
	}
	return i18n.tr_from_map(desktop_i18n_translations, language, key)
}
