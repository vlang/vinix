// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// The desktop's own text, in every language it speaks.
//
// Everything the desktop and its native applications show is looked up by key
// with tr(). The text itself lives in translations/<code>.tr, one file per
// DesktopLanguage, in the format of V's i18n module: a key line, the text, and
// a `-----` separator. The staging step compiles those files in as
// desktop_translation_files (translations_data.v), and i18n parses them once.
//
// A key a translation lacks falls back to English, so an unfinished language
// shows English words rather than keys. tools/tests/i18n_test.v keeps every
// file complete and every key the sources name defined.
//
// Two conventions go beyond the plain format:
//   - `{0}`, `{1}`, `{2}` mark where tr_fill and friends put their arguments,
//     so each language orders a sentence its own way.
//   - Text containing `|` is a plural: complete forms, `one|other` in English
//     and Spanish, `zero-or-one|other` in French and `one|few|many` in Russian,
//     chosen by tr_count. Japanese and Chinese use one form for every count.
//     i18n's own tr_plural appends a suffix to the first form, which cannot spell
//     окно/окна/окон, and it applies the Russian rule to every language.
//
// Vinix runs without a garbage collector, and the renderer frees only the text
// it is told it owns. tr() therefore returns the table's own strings, which
// must never be freed, and the filling helpers allocate exactly their result,
// which the caller owns like any other formatted string.
module main

import i18n

const desktop_translations = i18n.load_tr_map_from_files(desktop_translation_files)

// Each plural's forms, split once at startup so choosing one allocates
// nothing. Keyed like desktop_translations: language code, then key.
const desktop_plural_forms = split_desktop_plurals(desktop_translations)

// The language tr() answers in. It mirrors Settings.language: the compositor
// sets it when it loads or accepts preferences, an application process
// whenever a request brings it the compositor's settings.
__global desktop_language = DesktopLanguage.en

fn set_desktop_language(language DesktopLanguage) {
	desktop_language = language
}

fn split_desktop_plurals(translations map[string]map[string]string) map[string]map[string][]string {
	mut plurals := map[string]map[string][]string{}
	for code, table in translations {
		// Keep an entry even for languages that have no multi-form plurals.
		// A missing outer map would allocate an empty map on every lookup.
		plurals[code] = map[string][]string{}
		for key, text in table {
			if text.contains('|') {
				plurals[code][key] = text.split('|')
			}
		}
	}
	return plurals
}

// tr returns the text for key in the desktop's language.
fn tr(key string) string {
	text := desktop_translations[desktop_language.code()][key]
	if text.len > 0 {
		return text
	}
	// i18n reports a key English lacks too, and shows the key itself.
	return i18n.tr_from_map(desktop_translations, 'en', key)
}

// tr_fill returns key's text with `{0}` replaced by a. The result is newly
// allocated and belongs to the caller.
fn tr_fill(key string, a string) string {
	return tr_substitute(tr(key), a, '', '')
}

fn tr_fill2(key string, a string, b string) string {
	return tr_substitute(tr(key), a, b, '')
}

fn tr_fill3(key string, a string, b string, c string) string {
	return tr_substitute(tr(key), a, b, c)
}

// tr_count returns the plural form of key that suits count, with `{0}`
// replaced by the count. The result is newly allocated and belongs to the
// caller.
fn tr_count(key string, count i64) string {
	number := count.str()
	text := tr_substitute(tr_plural_form(key, count), number, '', '')
	unsafe { number.free() }
	return text
}

// tr_count_fill is tr_count for a sentence that names something besides the
// count, which goes in `{1}`.
fn tr_count_fill(key string, count i64, b string) string {
	number := count.str()
	text := tr_substitute(tr_plural_form(key, count), number, b, '')
	unsafe { number.free() }
	return text
}

// tr_plural_form picks, without allocating, the form of key that suits count
// in the desktop's language, and English's when that language lacks the key.
fn tr_plural_form(key string, count i64) string {
	mut language := desktop_language
	mut forms := desktop_plural_forms[language.code()][key]
	if forms.len == 0 {
		// Japanese and Chinese use a single complete form without `|`.
		text := desktop_translations[language.code()][key]
		if text.len > 0 {
			return text
		}
		language = .en
		forms = desktop_plural_forms['en'][key]
	}
	if forms.len == 0 {
		// Not a plural after all: the text is its own only form.
		return tr(key)
	}
	index := desktop_plural_index(language, count)
	return forms[if index < forms.len { index } else { forms.len - 1 }]
}

// desktop_plural_index is which of a language's plural forms a count takes.
// English and Spanish have one and other; French has zero-or-one and other.
// Russian has one (1, 21, 101), few (2-4, 22-24) and many (0, 5-20, 25-30,
// 11-14 of every hundred). Japanese and Chinese use one form for every count.
fn desktop_plural_index(language DesktopLanguage, count i64) int {
	n := if count < 0 { -count } else { count }
	return match language {
		.ru {
			if n % 10 == 1 && n % 100 != 11 {
				0
			} else if n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14) {
				1
			} else {
				2
			}
		}
		.en, .es {
			if n == 1 { 0 } else { 1 }
		}
		.fr {
			if n <= 1 { 0 } else { 1 }
		}
		.ja, .zh { 0 }
	}
}

// tr_substitute fills `{0}`, `{1}` and `{2}` in text with a, b and c in one
// allocation of exactly the result's size.
fn tr_substitute(text string, a string, b string, c string) string {
	mut size := 0
	mut i := 0
	for i < text.len {
		slot := tr_placeholder_at(text, i)
		if slot >= 0 {
			size += match slot {
				0 { a.len }
				1 { b.len }
				else { c.len }
			}
			i += 3
			continue
		}
		size++
		i++
	}
	mut out := unsafe { malloc_noscan(size + 1) }
	mut at := 0
	i = 0
	for i < text.len {
		slot := tr_placeholder_at(text, i)
		if slot >= 0 {
			value := match slot {
				0 { a }
				1 { b }
				else { c }
			}
			if value.len > 0 {
				unsafe { vmemcpy(out + at, value.str, value.len) }
			}
			at += value.len
			i += 3
			continue
		}
		unsafe {
			out[at] = text[i]
		}
		at++
		i++
	}
	unsafe {
		out[size] = 0
	}
	return unsafe { tos(out, size) }
}

// tr_placeholder_at is the argument a `{n}` at index names, or -1.
@[inline]
fn tr_placeholder_at(text string, index int) int {
	if index + 2 < text.len && text[index] == `{` && text[index + 2] == `}`
		&& text[index + 1] >= `0` && text[index + 1] <= `2` {
		return int(text[index + 1] - `0`)
	}
	return -1
}

// language_changed follows a change of Settings.language in the compositor.
// Everything is looked up afresh each frame; this drops what was composed
// earlier and kept.
fn (mut d Desktop) language_changed() {
	set_desktop_language(d.settings.language)
	// Weekday and month names.
	d.taskbar_clock_sampled = false
	if d.external_error_app.len > 0 {
		d.compose_external_error()
	}
	d.dirty = true
}
