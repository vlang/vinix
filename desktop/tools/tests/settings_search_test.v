// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import ui2

__global settings_search_device_reads = 0

fn settings_search_device_read(mut state BacklightState) BacklightResult {
	state = BacklightState{}
	settings_search_device_reads++
	return .unavailable
}

fn settings_search_has_result(a &SettingsApp, title string) bool {
	for index in 0 .. a.search_count {
		if settings_search_entries[a.search_results[index]].title == title { return true }
	}
	return false
}

fn settings_search_contains(root &ui2.Element, id string) bool {
	if root.id == id { return true }
	for child in root.children {
		if settings_search_contains(unsafe { &child }, id) { return true }
	}
	return false
}

fn test_settings_search_indexes_every_real_localized_option_and_category() {
	mut app := &SettingsApp{}
	defer {
		app.close_app()
		unsafe { free(app) }
		set_desktop_language(.en)
	}
	for language in desktop_languages {
		set_desktop_language(language)
		for entry in settings_search_entries {
			app.key_input('\x06')
			app.paste_input(tr(entry.title))
			assert settings_search_has_result(app, entry.title)
		}
		for category in settings_categories {
			app.key_input('\x06')
			app.paste_input(category.title())
			assert app.search_count > 0
			mut found_category := false
			for index in 0 .. app.search_count {
				if settings_search_entries[app.search_results[index]].category == category {
					found_category = true
				}
			}
			assert found_category
		}
	}
}

fn test_settings_search_folds_case_accents_and_matches_native_language_names() {
	mut app := &SettingsApp{}
	defer {
		app.close_app()
		unsafe { free(app) }
		set_desktop_language(.en)
	}
	for language, query in {
		DesktopLanguage.en: 'BRIGHTNESS'
		.es:                'BRILLO'
		.ru:                'ЯРКОСТЬ'
	} {
		set_desktop_language(language)
		app.key_input('\x06')
		app.paste_input(query)
		assert settings_search_has_result(app, 'settings.display.brightness')
	}
	set_desktop_language(.en)
	for query in ['ESPANOL', 'русский', 'english']! {
		app.key_input('\x06')
		app.paste_input(query)
		assert settings_search_has_result(app, 'settings.language.heading')
	}
	app.key_input('\x06')
	app.paste_input('keyboard french')
	assert settings_search_has_result(app, 'settings.keyboard.layout.french')
	assert !settings_search_has_result(app, 'settings.appearance.buttons')
	app.key_input('\x06')
	app.paste_input('bluetooth')
	assert app.search_count == 0
}

fn test_settings_search_opens_real_controls_without_mutating_hidden_preferences_or_devices() {
	set_desktop_language(.en)
	mut desktop := Desktop{}
	mut app := &SettingsApp{ desktop: unsafe { &desktop }, read_state: settings_search_device_read }
	defer {
		app.close_app()
		unsafe {
			free(app)
			desktop.native_asset_icons.free()
		}
	}
	settings_search_device_reads = 0
	app.key_input('\x06')
	app.paste_input('brightness')
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 620, 376))!
	assert settings_search_contains(unsafe { &tree }, 'settings.search.result.0')
	assert !settings_search_contains(unsafe { &tree }, settings_brightness_actions[0])
	free_tree(tree)
	assert settings_search_device_reads == 0
	app.handle('settings.side.1')!
	assert desktop.settings.button_side == .right
	app.handle('settings.search.result.0')!
	assert app.category == .display && !app.searching()
	assert settings_search_device_reads == 1
	app.key_input('\x06')
	app.paste_input('window buttons')
	app.key_input('\r')
	assert app.category == .appearance && !app.search_focused
	app.handle('settings.side.1')!
	assert desktop.settings.button_side == .left
	app.key_input('text')
	assert app.search.len == 0
	app.paste_input('text')
	assert app.search.len == 0
}

fn test_settings_search_utf8_fragments_backspace_selection_and_bounded_paste() {
	set_desktop_language(.ru)
	mut app := &SettingsApp{}
	defer {
		app.close_app()
		unsafe { free(app) }
		set_desktop_language(.en)
	}
	app.handle('settings.search.field')!
	word := 'яркость'
	for index in 0 .. word.len { app.key_input(console_borrow(word, index, index + 1)) }
	assert editor_bytes_text(app.search) == word
	assert settings_search_has_result(app, 'settings.display.brightness')
	app.key_input('\x7f')
	assert editor_bytes_text(app.search) == 'яркост'
	app.key_input('\x01\x7f')
	assert app.search.len == 0 && app.search_count == 0
	app.paste_input('a\n\t\x1bb\x7fc\xc2\x85d\xffé')
	assert editor_bytes_text(app.search) == 'abcdé'
	app.key_input('\x01')
	app.paste_input('\n\t\xff')
	assert editor_bytes_text(app.search) == 'abcdé'
	app.key_input('\x01')
	long := 'é'.repeat(100)
	app.paste_input(long)
	assert app.search.len == settings_search_limit
	assert app.search[app.search.len - 2] == 0xc3 && app.search.last() == 0xa9
	unsafe { long.free() }
	app.key_input('\x06')
	app.paste_input('a')
	app.key_input('\xe2')
	app.key_input('b')
	assert editor_bytes_text(app.search) == 'ab'
	app.key_input('\x1b')
	app.key_input('\x06')
	app.paste_input('c')
	assert editor_bytes_text(app.search) == 'c' && app.search_escape_len == 0
	app.key_input('\x1b')
	app.paste_input('d')
	assert editor_bytes_text(app.search) == 'cd' && app.search_escape_len == 0
}

fn test_settings_search_fragmented_navigation_paging_and_resize_keep_selection_visible() {
	set_desktop_language(.en)
	mut app := &SettingsApp{}
	defer {
		app.close_app()
		unsafe { free(app) }
	}
	app.key_input('\x06')
	app.paste_input('a')
	begin_frame_elements()
	first := app.build(ui2.rect(0, 0, 620, 300))!
	free_tree(first)
	assert app.search_count > app.search_rows
	app.key_input('\x1b')
	app.key_input('[')
	app.key_input('B')
	assert app.search_selected == 1 && editor_bytes_text(app.search) == 'a'
	app.key_input('\x1b[6')
	app.key_input('~')
	assert app.search_page == app.search_rows && app.search_selected == app.search_page
	for _ in 0 .. settings_search_entries.len { app.key_input('\x1b[B') }
	assert app.search_selected == app.search_count - 1
	begin_frame_elements()
	wide := app.build(ui2.rect(0, 0, 900, 700))!
	free_tree(wide)
	assert app.search_selected >= app.search_page && app.search_selected < app.search_page + app.search_rows
	app.handle('settings.search.previous')!
	assert app.search_selected == app.search_page
	app.key_input('\x1b[1;5C')
	assert editor_bytes_text(app.search) == 'a'
	app.key_input('\x1b[123456789012345678901~')
	assert editor_bytes_text(app.search) == 'a'
}

fn test_settings_search_escape_expires_and_clear_or_category_returns_to_controls() {
	set_desktop_language(.en)
	mut app := &SettingsApp{}
	defer {
		app.close_app()
		unsafe { free(app) }
	}
	app.key_input('\x06')
	app.paste_input('wifi')
	app.key_input('\x1b')
	assert app.next_poll_ms() == 100
	assert !app.expire_search_escape(app.search_escape_ms + 99)
	assert app.expire_search_escape(app.search_escape_ms + 100)
	assert !app.searching() && !app.search_focused && app.next_poll_ms() == 2000
	app.key_input('\x06')
	app.paste_input('not found')
	begin_frame_elements()
	empty := app.build(ui2.rect(0, 0, 620, 376))!
	assert settings_search_contains(unsafe { &empty }, 'settings.search.empty')
	free_tree(empty)
	app.handle('settings.search.clear')!
	assert app.search.len == 0
	app.key_input('\x06')
	app.paste_input('theme')
	app.handle('settings.category.8')!
	assert app.category == .keyboard && app.search.len == 0
	app.handle('settings.category.invalid')!
	app.handle('settings.category.99')!
	app.handle('settings.search.result.-1')!
	app.handle('settings.search.result.11')!
	assert app.category == .keyboard
}

fn test_settings_search_language_changes_recompute_results_before_render_or_selection() {
	set_desktop_language(.en)
	mut app := &SettingsApp{}
	defer {
		app.close_app()
		unsafe { free(app) }
		set_desktop_language(.en)
	}
	app.key_input('\x06')
	app.paste_input('brightness')
	assert app.search_count > 0
	set_desktop_language(.ru)
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 620, 376))!
	assert app.search_count == 0 && settings_search_contains(unsafe { &tree }, 'settings.search.empty')
	free_tree(tree)
	app.handle('settings.search.result.0')!
	assert app.category == .appearance
	app.key_input('\x06')
	app.paste_input('яркость')
	set_desktop_language(.es)
	app.key_input('\r')
	assert app.search_count == 0 && app.category == .appearance
}

fn test_settings_search_sidebar_fits_default_content_and_keeps_pane_control_ids() {
	set_desktop_language(.en)
	mut desktop := Desktop{}
	mut app := &SettingsApp{ desktop: unsafe { &desktop } }
	defer {
		app.close_app()
		unsafe {
			free(app)
			desktop.native_asset_icons.free()
		}
	}
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 620, 376))!
	assert settings_search_contains(unsafe { &tree }, 'settings.search.field')
	assert settings_search_contains(unsafe { &tree }, 'settings.side.0')
	assert tree.children[0].children.last().frame.y + tree.children[0].children.last().frame.height <= 376
	assert tree.children[2].frame.x == 133 && tree.children[2].frame.y == 0
	free_tree(tree)
}
