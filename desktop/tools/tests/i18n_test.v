// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

// Functions whose first argument is a translation key.
const i18n_test_lookups = ['tr', 'tr_fill', 'tr_fill2', 'tr_fill3', 'tr_count', 'tr_count_fill',
	'tr_plural_form', 'set_status', 'set_file_status']

fn ui2_rect_for_i18n_test() ui2.Rect {
	return ui2.rect(0, 0, 620, 376)
}

fn i18n_collect_text(el ui2.Element, mut out []string) {
	if el.text.len > 0 {
		out << el.text
	}
	for child in el.children {
		i18n_collect_text(child, mut out)
	}
}

fn i18n_placeholders(text string) []int {
	mut found := []int{}
	for i in 0 .. text.len {
		slot := tr_placeholder_at(text, i)
		if slot >= 0 && slot !in found {
			found << slot
		}
	}
	found.sort()
	return found
}

// i18n_source_keys is every literal key a staged desktop source looks up. The
// staged directory is this module's root and holds the real sources.
fn i18n_source_keys() map[string]string {
	mut keys := map[string]string{}
	root := @VMODROOT
	for name in os.ls(root) or { panic(err) } {
		if !name.ends_with('.v') || name.ends_with('_test.v') {
			continue
		}
		text := os.read_file(os.join_path(root, name)) or { panic(err) }
		mut at := 0
		for {
			quote := text.index_after("('", at) or { break }
			at = quote + 2
			mut start := quote
			for start > 0 && (text[start - 1].is_letter() || text[start - 1].is_digit()
				|| text[start - 1] == `_`) {
				start--
			}
			if text[start..quote] !in i18n_test_lookups {
				continue
			}
			end := text.index_after("'", at) or { break }
			keys[text[at..end]] = name
			at = end + 1
		}
	}
	return keys
}

fn test_every_language_defines_exactly_the_english_keys() {
	english := desktop_translations['en']
	assert english.len > 0
	for language in desktop_languages {
		table := desktop_translations[language.code()]
		for key, _ in english {
			assert key in table, '${language.code()} lacks ${key}'
		}
		for key, text in table {
			assert key in english, '${language.code()} defines ${key}, which English does not'
			assert text.trim_space().len > 0, '${language.code()} ${key} is empty'
		}
	}
}

fn test_translations_keep_placeholders_and_plural_forms() {
	for key, english in desktop_translations['en'] {
		for language in desktop_languages {
			text := desktop_translations[language.code()][key]
			assert i18n_placeholders(text) == i18n_placeholders(english), '${language.code()} ${key} changes its placeholders'
			if english.contains('|') {
				forms := text.split('|')
				want := match language {
					.ru { 3 }
					.ja, .zh { 1 }
					.en, .es, .fr { 2 }
				}
				assert forms.len == want, '${language.code()} ${key} needs ${want} plural forms'
				for form in forms {
					assert i18n_placeholders(form) == i18n_placeholders(english), '${language.code()} ${key} changes a plural form\'s placeholders'
				}
			} else {
				assert !text.contains('|'), '${language.code()} ${key} is a plural only in translation'
			}
		}
	}
}

fn test_every_key_the_sources_use_is_defined() {
	keys := i18n_source_keys()
	assert keys.len > 0
	for key, file in keys {
		assert key in desktop_translations['en'], '${file} uses undefined key ${key}'
	}
}

// UI helpers whose first argument is the text they show, and those whose
// second argument is, after an element id.
const i18n_text_first = ['settings_heading', 'settings_note', 'heading', 'body_line', 'owned_body_line',
	'muted_line', 'tray_flyout_heading']
const i18n_text_second = ['ui2.label', 'ui2.button', 'ui2.button_with_image', 'settings_choice',
	'settings_toggle', 'editor_toolbar_button']
// Names that read the same in every language.
const i18n_untranslated_names = ['Vinix', 'Disk Usage']

// i18n_literal_after is the single-quoted literal starting at index, after
// any spaces, or none.
fn i18n_literal_after(text string, index int) ?string {
	mut at := index
	for at < text.len && text[at] in [` `, `\t`, `\n`] {
		at++
	}
	if at >= text.len || text[at] != `'` {
		return none
	}
	end := text.index_after("'", at + 1) or { return none }
	return text[at + 1..end]
}

// i18n_second_argument is where the argument after the first top-level comma
// of the call whose `(` is at open begins.
fn i18n_second_argument(text string, open int) ?int {
	mut depth := 0
	mut at := open + 1
	for at < text.len {
		c := text[at]
		if c == `'` {
			at = (text.index_after("'", at + 1) or { return none }) + 1
			continue
		}
		if c in [`(`, `[`, `{`] {
			depth++
		} else if c in [`)`, `]`, `}`] {
			if depth == 0 {
				return none
			}
			depth--
		} else if c == `,` && depth == 0 {
			return at + 1
		}
		at++
	}
	return none
}

// i18n_shows_words is whether a literal has letters of its own once its
// ${...} interpolations are taken out. Symbols such as ↑, − and × are not
// words and read the same in every language.
fn i18n_shows_words(literal string) bool {
	mut at := 0
	for at < literal.len {
		if literal[at] == `$` && at + 1 < literal.len && literal[at + 1] == `{` {
			at = (literal.index_after('}', at) or { return false }) + 1
			continue
		}
		r, size := next_rune(literal, at)
		if (r >= `a` && r <= `z`) || (r >= `A` && r <= `Z`)
			|| (r >= 0xc0 && r <= 0x24f && r != 0xd7 && r != 0xf7) || (r >= 0x400 && r <= 0x4ff)
			|| (r >= 0x3040 && r <= 0x30ff)
			|| (r >= 0x3400 && r <= 0x9fff) {
			return true
		}
		at += size
	}
	return false
}

// Every word the desktop shows goes through a translation key. This finds
// literal text handed to the UI helpers, which a translation would miss.
fn test_ui_helpers_are_not_given_literal_words() {
	root := @VMODROOT
	mut found := []string{}
	for name in os.ls(root) or { panic(err) } {
		if !name.ends_with('.v') || name.ends_with('_test.v') || name.starts_with('app_') {
			continue
		}
		text := os.read_file(os.join_path(root, name)) or { panic(err) }
		for index, helpers in [i18n_text_first, i18n_text_second] {
			for helper in helpers {
				mut at := 0
				for {
					call := text.index_after(helper + '(', at) or { break }
					at = call + helper.len + 1
					if call > 0 && (text[call - 1].is_letter() || text[call - 1].is_digit()
						|| text[call - 1] == `_` || (text[call - 1] == `.` && !helper.contains('.'))) {
						continue
					}
					start := if index == 0 {
						call + helper.len + 1
					} else {
						i18n_second_argument(text, call + helper.len) or { continue }
					}
					literal := i18n_literal_after(text, start) or { continue }
					if i18n_shows_words(literal) && literal !in i18n_untranslated_names {
						line := text[..call].count('\n') + 1
						found << "${name}:${line}: ${helper} shows '${literal}'"
					}
				}
			}
		}
	}
	assert found.len == 0, 'use tr() for text the desktop shows:\n' + found.join('\n')
}

// Text the fonts cannot draw comes out as gaps. Every rune any translation
// uses must have a glyph of its own, in every face.
fn test_fonts_draw_every_translated_rune() {
	fonts := load_fonts()
	for language in desktop_languages {
		for r in language.native_name().runes() {
			for face in fonts {
				glyph := face.glyph_for(u32(r))
				assert glyph.width > 0 && glyph.height > 0, '${language.code()}: no glyph for ${r}'
			}
		}
		for key, text in desktop_translations[language.code()] {
			for r in text.runes() {
				// Compact Grapher help renders catalog line breaks as separate labels.
				if r == `\n` { continue }
				if r == ` ` || r == ` ` {
					continue
				}
				for face in fonts {
					glyph := face.glyph_for(u32(r))
					assert glyph.width > 0 && glyph.height > 0, '${language.code()} ${key}: no glyph for ${r}'
				}
			}
		}
	}
}

fn test_tr_follows_the_desktop_language() {
	defer {
		set_desktop_language(.en)
	}
	set_desktop_language(.en)
	assert tr('settings.category.language') == 'Language'
	assert app_title_text('Files') == 'Files'
	set_desktop_language(.ru)
	assert tr('settings.category.language') == 'Язык'
	assert app_title_text('Files') == 'Файлы'
	assert app_title_text(files_settings_window_title) == 'Настройки Файлов'
	// Product names are not translated.
	assert app_title_text('Firefox') == 'Firefox'
	set_desktop_language(.es)
	assert tr('settings.category.language') == 'Idioma'
	assert app_title_text(capture_app_title) == 'Captura'
	set_desktop_language(.fr)
	assert tr('settings.category.language') == 'Langue'
	assert app_title_text('Files') == 'Fichiers'
}

fn test_tr_fill_places_arguments_in_one_allocation() {
	assert tr_substitute('{1} of {0}', 'a', 'bcd', '') == 'bcd of a'
	assert tr_substitute('{0}{0}{2}', 'x', '', 'yz') == 'xxyz'
	assert tr_substitute('no slots', 'a', 'b', 'c') == 'no slots'
	assert tr_substitute('{9} and {', 'a', 'b', 'c') == '{9} and {'
	assert tr_substitute('', 'a', 'b', 'c') == ''
}

fn test_plural_rules_per_language() {
	for count in [i64(0), 2, 5, 11, 21, 100, 101] {
		assert desktop_plural_index(.en, count) == 1
		assert desktop_plural_index(.es, count) == 1
	}
	assert desktop_plural_index(.en, 1) == 0
	assert desktop_plural_index(.es, 1) == 0
	for count in [i64(-1), 0, 1] {
		assert desktop_plural_index(.fr, count) == 0
	}
	for count in [i64(-2), 2, 5, 11, 21, 100, 101, 1_000_000] {
		assert desktop_plural_index(.fr, count) == 1
	}
	for count in [i64(1), 21, 31, 101, 1001] {
		assert desktop_plural_index(.ru, count) == 0, '${count}'
	}
	for count in [i64(2), 3, 4, 22, 34, 102, 1004] {
		assert desktop_plural_index(.ru, count) == 1, '${count}'
	}
	for count in [i64(0), 5, 9, 10, 11, 12, 13, 14, 15, 20, 25, 100, 111, 112, 114] {
		assert desktop_plural_index(.ru, count) == 2, '${count}'
	}
	assert desktop_plural_index(.ru, -21) == 0
	for count in [i64(-21), -1, 0, 1, 2, 11, 100, 1001] {
		assert desktop_plural_index(.ja, count) == 0
	}
}

fn test_language_crosses_the_application_process_boundary() {
	for language in desktop_languages {
		state := AppWireState{
			settings:        Settings{
				language: language
			}
			requested_scale: desktop_scale_100
		}
		mut encoded := []u8{}
		wire_put_state(mut encoded, state)
		assert encoded.len == app_request_header_size - 20
		mut reader := WireReader{
			data: encoded
		}
		decoded := wire_take_state(mut reader) or { panic(err) }
		assert reader.index == encoded.len
		assert decoded.settings.language == language
	}
	// A language this desktop does not know is a damaged message.
	mut encoded := []u8{}
	wire_put_state(mut encoded, AppWireState{
		requested_scale: desktop_scale_100
	})
	// The language follows the nine Settings fields and the two keyboard ones.
	encoded[44] = u8(desktop_languages.len)
	mut reader := WireReader{
		data: encoded
	}
	if _ := wire_take_state(mut reader) {
		assert false, 'an unknown language was accepted'
	}
}

fn test_accepting_a_language_from_settings_retranslates_the_compositor() {
	defer {
		set_desktop_language(.en)
	}
	mut desktop := Desktop{}
	desktop.taskbar_clock_sampled = true
	apply_app_state(mut desktop, AppWireState{
		settings:        Settings{
			language: .es
		}
		requested_scale: desktop_requested_scale()
	})
	assert desktop.settings.language == .es
	assert desktop_language == .es
	assert !desktop.taskbar_clock_sampled
	assert desktop.dirty
	assert SettingsCategory.battery.title() == 'Batería'
}

fn test_settings_language_pane_switches_the_language() {
	defer {
		set_desktop_language(.en)
	}
	mut desktop := Desktop{}
	mut app := SettingsApp{
		desktop: &desktop
	}
	app.handle('${settings_action_category}${settings_categories.index(SettingsCategory.language)}')!
	assert app.category == .language
	tree := app.build(ui2_rect_for_i18n_test())!
	mut labels := []string{}
	i18n_collect_text(tree, mut labels)
	assert 'System language' in labels
	for language in desktop_languages {
		assert language.native_name() in labels
	}
	app.handle('${settings_action_language}${desktop_languages.index(DesktopLanguage.ru)}')!
	assert desktop.settings.language == .ru
	assert desktop_language == .ru
	translated := app.build(ui2_rect_for_i18n_test())!
	labels.clear()
	i18n_collect_text(translated, mut labels)
	assert 'Язык системы' in labels
	// Languages keep their own names whichever is chosen.
	assert 'English' in labels && 'Español' in labels && 'Français' in labels
	app.handle('${settings_action_language}${desktop_languages.index(DesktopLanguage.fr)}')!
	assert desktop.settings.language == .fr
	assert desktop_language == .fr
	french := app.build(ui2_rect_for_i18n_test())!
	labels.clear()
	i18n_collect_text(french, mut labels)
	assert 'Langue du système' in labels
	// Out-of-range choices are ignored.
	app.handle('${settings_action_language}9')!
	assert desktop.settings.language == .fr
}

// An application process learns the language as it starts, before its first
// request, so what it composes while opening is translated too.
fn test_app_processes_start_in_the_desktop_language() {
	base := ['--vinix-app=vinix-settings', '--request-fd=3', '--response-fd=4']
	options := app_process_options(base) or { panic('options rejected') }
	assert options.language == .en
	for language in desktop_languages {
		mut args := base.clone()
		args << '--app-lang=${language.code()}'
		chosen := app_process_options(args) or { panic('options rejected') }
		assert chosen.language == language
	}
	mut unknown := base.clone()
	unknown << '--app-lang=zz'
	fallback := app_process_options(unknown) or { panic('options rejected') }
	assert fallback.language == .en
}

fn test_program_search_ignores_case_and_accents_in_every_script() {
	assert start_menu_matches('Activity Monitor', 'MON')
	assert start_menu_matches('Терминал', 'ТЕРМ')
	assert start_menu_matches('Терминал', 'минал')
	assert start_menu_matches('Ёлка', 'ел')
	assert start_menu_matches('Configuración', 'configuracion')
	assert start_menu_matches('Configuración', 'CIÓN')
	assert !start_menu_matches('Терминал', 'файл')
	assert !start_menu_matches('Files', 'Filesystem')
	defer {
		set_desktop_language(.en)
	}
	set_desktop_language(.ru)
	// Found by the name shown and by the English one.
	assert app_matches('Calculator', 'каль')
	assert app_matches('Calculator', 'calc')
	assert !app_matches('Calculator', 'терм')
	set_desktop_language(.es)
	assert app_matches('Calendar', 'calendario')
	set_desktop_language(.fr)
	assert app_matches('Text Editor', 'EDITEUR')
	assert app_matches('Settings', 'parametres')
	set_desktop_language(.ja)
	assert app_matches('Calculator', '電卓')
	assert app_matches('Calculator', 'calc')
	assert start_menu_matches('日本語', '日本')
}

// Settings' Jump List tasks name categories, not positions in the sidebar,
// which gained Language.
fn test_settings_jump_tasks_open_the_page_they_name() {
	want := {
		'Wallpaper': SettingsCategory.wallpaper
		'Display':   SettingsCategory.display
		'Wi-Fi':     SettingsCategory.wifi
		'Battery':   SettingsCategory.battery
	}
	for task in settings_jump_tasks {
		assert task.command == .settings_page
		assert task.arg == int(want[task.title]), task.title
		assert jump_task_text(task.title) == want[task.title].title()
	}
}

fn test_keyboard_pane_names_layouts_in_the_language() {
	defer {
		set_desktop_language(.en)
	}
	mut desktop := Desktop{}
	desktop.settings.keyboard_layouts = keyboard_layout_all_mask
	desktop.settings.keyboard_layout = .russian
	mut app := SettingsApp{
		desktop:  &desktop
		category: .keyboard
	}
	set_desktop_language(.ru)
	mut labels := []string{}
	i18n_collect_text(app.build(ui2_rect_for_i18n_test())!, mut labels)
	assert 'Клавиатура' in labels
	assert 'Русская' in labels && 'Португальская' in labels
	// The model keeps its English names; only what is shown changes.
	assert KeyboardLayout.russian.title() == 'Russian'
	assert keyboard_layout_text(.russian) == 'Русская'
}

fn test_editor_status_follows_a_change_of_language() {
	defer {
		set_desktop_language(.en)
	}
	set_desktop_language(.en)
	mut editor := TextEditorApp{}
	editor.set_path('/root/notes.txt')
	editor.set_file_status('editor.status.saved')
	assert editor_bytes_text(editor.status) == 'Saved /root/notes.txt'
	set_desktop_language(.es)
	editor.build(ui2_rect_for_i18n_test())!
	assert editor_bytes_text(editor.status) == 'Guardado /root/notes.txt'
	editor.set_status('editor.status.unsaved')
	set_desktop_language(.ru)
	editor.build(ui2_rect_for_i18n_test())!
	assert editor_bytes_text(editor.status) == 'Есть несохранённые изменения'
}
