// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The index names controls that actually exist. Titles, category names and
// explanatory text are borrowed from the current translation table. Matching
// folds Latin accents and Cyrillic case without making temporary strings.
struct SettingsSearchEntry {
	category SettingsCategory
	title    string
	terms    [6]string
}

const settings_search_limit = 128
const settings_search_entries = [
	SettingsSearchEntry{.appearance, 'settings.appearance.buttons', [
		'settings.appearance.buttons_note',
		'settings.appearance.left',
		'settings.appearance.right',
		'',
		'',
		'',
	]!},
	SettingsSearchEntry{.appearance, 'settings.appearance.taskbar', [
		'settings.appearance.taskbar_note',
		'settings.appearance.standard',
		'settings.appearance.combined',
		'',
		'',
		'',
	]!},
	SettingsSearchEntry{.date_time, 'settings.date_time.format', [
		'settings.date_time.format_note',
		'settings.date_time.24_hour',
		'settings.date_time.12_hour',
		'',
		'',
		'',
	]!},
	SettingsSearchEntry{.date_time, 'settings.date_time.seconds', [
		'settings.date_time.seconds_note',
		'settings.date_time.show',
		'settings.date_time.hide',
		'',
		'',
		'',
	]!},
	SettingsSearchEntry{.date_time, 'settings.date_time.date_line', [
		'settings.date_time.date_line_note',
		'settings.date_time.show_date',
		'settings.date_time.hide_date',
		'',
		'',
		'',
	]!},
	SettingsSearchEntry{.date_time, 'settings.date_time.show_weekday', [
		'settings.date_time.hide_weekday',
		'',
		'',
		'',
		'',
		'',
	]!},
	SettingsSearchEntry{.language, 'settings.language.heading', [
		'settings.language.note',
		'settings.language.apps_note',
		'',
		'',
		'',
		'',
	]!},
	SettingsSearchEntry{.theme, 'settings.theme.heading', [
		'settings.theme.note',
		'settings.theme.default',
		'settings.theme.macos',
		'settings.theme.default_note_1',
		'settings.theme.macos_note_1',
		'',
	]!},
	SettingsSearchEntry{.wallpaper, 'settings.wallpaper.colour', [
		'',
		'',
		'',
		'',
		'',
		'',
	]!},
	SettingsSearchEntry{.wallpaper, 'settings.wallpaper.photo', [
		'settings.wallpaper.no_photos_1',
		'settings.wallpaper.no_photos_2',
		'',
		'',
		'',
		'',
	]!},
	SettingsSearchEntry{.wifi, 'settings.wifi.radio', [
		'settings.wifi.subtitle',
		'settings.wifi.turn_on',
		'settings.wifi.turn_off',
		'',
		'',
		'',
	]!},
	SettingsSearchEntry{.wifi, 'settings.wifi.available', [
		'settings.wifi.scan_button',
		'settings.wifi.refresh_button',
		'settings.wifi.read_only',
		'',
		'',
		'',
	]!},
	SettingsSearchEntry{.display, 'settings.display.brightness', [
		'settings.display.built_in',
		'settings.display.bar_hint',
		'settings.display.read_from',
		'settings.display.requested_nits',
		'settings.display.actual_nits',
		'settings.display.refresh',
	]!},
	SettingsSearchEntry{.display, 'settings.display.scale', [
		'',
		'',
		'',
		'',
		'',
		'',
	]!},
	SettingsSearchEntry{.battery, 'settings.battery.current_charge', [
		'settings.battery.built_in',
		'settings.battery.refresh',
		'settings.battery.estimated_remaining',
		'',
		'',
		'',
	]!},
	SettingsSearchEntry{.battery, 'settings.battery.history', [
		'settings.battery.day_ago',
		'settings.battery.now',
		'',
		'',
		'',
		'',
	]!},
	SettingsSearchEntry{.keyboard, 'settings.keyboard.sources', [
		'settings.keyboard.sources_note',
		'settings.keyboard.menu_hint',
		'',
		'',
		'',
		'',
	]!},
	SettingsSearchEntry{.keyboard, 'settings.keyboard.layout.us', [
		'settings.keyboard.sources_note',
		'',
		'',
		'',
		'',
		'',
	]!},
	SettingsSearchEntry{.keyboard, 'settings.keyboard.layout.russian', [
		'settings.keyboard.sources_note',
		'',
		'',
		'',
		'',
		'',
	]!},
	SettingsSearchEntry{.keyboard, 'settings.keyboard.layout.spanish', [
		'settings.keyboard.sources_note',
		'',
		'',
		'',
		'',
		'',
	]!},
	SettingsSearchEntry{.keyboard, 'settings.keyboard.layout.french', [
		'settings.keyboard.sources_note',
		'',
		'',
		'',
		'',
		'',
	]!},
	SettingsSearchEntry{.keyboard, 'settings.keyboard.layout.german', [
		'settings.keyboard.sources_note',
		'',
		'',
		'',
		'',
		'',
	]!},
	SettingsSearchEntry{.keyboard, 'settings.keyboard.layout.portuguese', [
		'settings.keyboard.sources_note',
		'',
		'',
		'',
		'',
		'',
	]!},
	SettingsSearchEntry{.about, 'settings.about.kernel', [
		'',
		'',
		'',
		'',
		'',
		'',
	]!},
	SettingsSearchEntry{.about, 'settings.about.cpu', [
		'',
		'',
		'',
		'',
		'',
		'',
	]!},
	SettingsSearchEntry{.about, 'settings.about.memory', [
		'',
		'',
		'',
		'',
		'',
		'',
	]!},
	SettingsSearchEntry{.about, 'settings.about.uptime', [
		'',
		'',
		'',
		'',
		'',
		'',
	]!},
]!

const settings_category_actions = ['settings.category.0', 'settings.category.1', 'settings.category.2',
	'settings.category.3', 'settings.category.4', 'settings.category.5', 'settings.category.6',
	'settings.category.7', 'settings.category.8', 'settings.category.9']!
const settings_search_actions = ['settings.search.result.0', 'settings.search.result.1',
	'settings.search.result.2', 'settings.search.result.3', 'settings.search.result.4',
	'settings.search.result.5', 'settings.search.result.6', 'settings.search.result.7',
	'settings.search.result.8', 'settings.search.result.9', 'settings.search.result.10',
	'settings.search.result.11']!

fn (a &SettingsApp) searching() bool {
	for byte in a.search { if byte != ` ` { return true } }
	return false
}

fn settings_search_token(entry SettingsSearchEntry, token string) bool {
	if start_menu_matches(entry.category.title(), token) || start_menu_matches(tr(entry.title), token) {
		return true
	}
	for key in entry.terms { if key.len > 0 && start_menu_matches(tr(key), token) { return true } }
	if entry.category == .language {
		for language in desktop_languages {
			if start_menu_matches(language.native_name(), token) { return true }
		}
	}
	if entry.title == 'settings.display.scale' {
		return start_menu_matches('100% 200%', token)
	}
	return false
}

fn settings_search_matches(entry SettingsSearchEntry, query string) bool {
	mut at := 0
	mut found := false
	for at < query.len {
		for at < query.len && query[at] == ` ` { at++ }
		start := at
		for at < query.len && query[at] != ` ` { at++ }
		if at > start {
			found = true
			if !settings_search_token(entry, console_borrow(query, start, at)) { return false }
		}
	}
	return found
}

fn (mut a SettingsApp) refilter_search() {
	a.search_count = 0
	a.search_page = 0
	a.search_selected = 0
	a.search_language = desktop_language
	if !a.searching() { return }
	query := editor_bytes_text(a.search)
	for index, entry in settings_search_entries {
		if settings_search_matches(entry, query) {
			a.search_results[a.search_count] = index
			a.search_count++
		}
	}
}

fn (mut a SettingsApp) clear_search() {
	a.search.clear()
	a.search_count = 0
	a.search_selected = 0
	a.search_page = 0
	a.search_focused = false
	a.search_select_all = false
	a.search_pending_len = 0
	a.search_escape_len = 0
}

fn (mut a SettingsApp) choose_category(category SettingsCategory) {
	a.clear_search()
	a.category = category
	match category {
		.about { a.about.refresh() }
		.battery { a.battery_read(true) }
		.wifi {
			a.wifi_action_result = .ok
			a.refresh_wifi()
		}
		.display {
			a.write_result = .ok
			a.refresh()
		}
		else {}
	}
}

fn (mut a SettingsApp) open_search_result(index int) {
	if index >= 0 && index < a.search_count {
		a.choose_category(settings_search_entries[a.search_results[index]].category)
	}
}

fn (mut a SettingsApp) search_page_by(direction int) {
	if a.search_rows <= 0 || a.search_count == 0 { return }
	last := ((a.search_count - 1) / a.search_rows) * a.search_rows
	a.search_page += direction * a.search_rows
	if a.search_page < 0 { a.search_page = 0 }
	if a.search_page > last { a.search_page = last }
	a.search_selected = a.search_page
}

fn (mut a SettingsApp) handle_search(event_id string) bool {
	if a.search_language != desktop_language { a.refilter_search() }
	match event_id {
		'settings.search.field' {
			a.search_focused = true
			a.search_select_all = false
			a.search_pending_len = 0
			a.search_escape_len = 0
			return true
		}
		'settings.search.clear' {
			a.clear_search()
			return true
		}
		'settings.search.previous' {
			a.search_page_by(-1)
			return true
		}
		'settings.search.next' {
			a.search_page_by(1)
			return true
		}
		else {}
	}
	for index, action in settings_search_actions {
		if event_id == action {
			if a.searching() && index < a.search_rows {
				a.open_search_result(a.search_page + index)
			}
			return true
		}
	}
	return event_id.starts_with('settings.search.')
}

fn (mut a SettingsApp) paste_input(text string) {
	if !a.search_focused { return }
	if a.search.cap == 0 {
		a.search = []u8{cap: settings_search_limit}
		a.search.flags |= .noslices
	}
	console_paste_field(mut a.search, text, settings_search_limit, a.search_select_all)
	a.search_select_all = false
	a.search_pending_len = 0
	a.search_escape_len = 0
	a.refilter_search()
}

fn (mut a SettingsApp) search_move(direction int) {
	if a.search_count == 0 { return }
	a.search_selected += direction
	if a.search_selected < 0 { a.search_selected = 0 }
	if a.search_selected >= a.search_count { a.search_selected = a.search_count - 1 }
	a.search_page = (a.search_selected / a.search_rows) * a.search_rows
}

fn (mut a SettingsApp) key_input(input string) {
	if a.search_language != desktop_language { a.refilter_search() }
	mut at := 0
	for at < input.len {
		byte := input[at]
		at++
		if byte == 0x06 {
			a.search_focused = true
			a.search_select_all = true
			a.search_pending_len = 0
			a.search_escape_len = 0
			continue
		}
		if a.search_escape_len > 0 {
			if a.search_escape_len == 1 && byte != `[` {
				a.clear_search()
			} else {
				// Consume an oversized CSI until its final byte; its suffix must
				// not become query text after the bounded buffer fills.
				if a.search_escape_len == a.search_escape.len {
					if byte >= 0x40 && byte <= 0x7e { a.search_escape_len = 0 }
					continue
				}
				a.search_escape[a.search_escape_len] = byte
				a.search_escape_len++
				if (byte >= 0x40 && byte <= 0x7e) && a.search_escape_len > 2 {
					if a.search_focused {
						match unsafe { tos(&a.search_escape[0], a.search_escape_len) } {
							'\x1b[A' { a.search_move(-1) }
							'\x1b[B' { a.search_move(1) }
							'\x1b[5~' { a.search_page_by(-1) }
							'\x1b[6~' { a.search_page_by(1) }
							else {}
						}
					}
					a.search_escape_len = 0
				}
				continue
			}
		}
		if !a.search_focused { continue }
		if a.search_pending_len > 0 {
			if editor_utf8_follows(a.search_pending[0], a.search_pending_len, byte) {
				a.search_pending[a.search_pending_len] = byte
				a.search_pending_len++
				if a.search_pending_len == editor_utf8_length(a.search_pending[0]) {
					a.paste_input(unsafe { tos(&a.search_pending[0], a.search_pending_len) })
				}
				continue
			}
			a.search_pending_len = 0
		}
		match byte {
			0x01 { a.search_select_all = true }
			0x1b {
				a.search_escape[0] = byte
				a.search_escape_len = 1
				a.search_escape_ms = desktop_monotonic_ms()
			}
			0x08, 0x7f {
				console_backspace(mut a.search, a.search_select_all)
				a.search_select_all = false
				a.refilter_search()
			}
			`\r`, `\n` { a.open_search_result(a.search_selected) }
			`\t` {
				a.search_focused = false
				a.search_select_all = false
			}
			else {
				if byte >= 0x20 && byte < 0x7f {
					a.paste_input(unsafe { tos(&byte, 1) })
				} else if editor_utf8_length(byte) > 1 {
					a.search_pending[0] = byte
					a.search_pending_len = 1
				}
			}
		}
	}
}

fn (mut a SettingsApp) expire_search_escape(now u64) bool {
	if a.search_escape_len == 0 || (now != ~u64(0) && now >= a.search_escape_ms
		&& now - a.search_escape_ms < 100) {
		return false
	}
	if a.search_escape_len == 1 {
		a.clear_search()
	} else {
		a.search_escape_len = 0
	}
	return true
}

fn (mut a SettingsApp) poll() bool { return a.expire_search_escape(desktop_monotonic_ms()) }

fn (a &SettingsApp) next_poll_ms() u64 {
	return if a.search_escape_len > 0 { u64(100) } else { u64(2000) }
}
