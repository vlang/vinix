// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn calendar_search_test_home(suffix string) string {
	path := os.join_path(os.temp_dir(), 'vinix-calendar-search-${os.getpid()}-${suffix}')
	os.mkdir(path) or { panic(err) }
	defer { unsafe { path.free() } }
	return os.real_path(path)
}

fn calendar_search_test_app(home string) CalendarApp {
	mut app := CalendarApp{year: 2026, month: 10, selected_day: 5}
	app.refresh_labels()
	app.events.load(home)
	return app
}

fn calendar_search_test_add(mut app CalendarApp, year int, month int, day int, minutes int, title string, location string) {
	app.events.items[app.events.count] = CalendarEvent{year: year, month: month, day: day, minutes: minutes, title: title.clone(), location: location.clone()}
	app.events.count++
}

fn calendar_search_test_element(root ui2.Element, id string) ?ui2.Element {
	if root.id == id { return root }
	for child in root.children {
		found := calendar_search_test_element(child, id) or { continue }
		return found
	}
	return none
}

fn test_calendar_search_finds_all_dates_and_tokens_across_title_and_location() {
	home := calendar_search_test_home('matching')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := calendar_search_test_app(home)
	defer { app.close_app() }
	calendar_search_test_add(mut app, 2028, 2, 29, 600, 'Café planning', 'Madrid')
	calendar_search_test_add(mut app, 2025, 1, 1, -1, 'ПРИВЕТ', 'Москва')
	calendar_search_test_add(mut app, 2026, 10, 5, 600, 'Planning', 'Office')
	app.key_input('\x06CAFE madrid')
	assert app.search_active && app.search_focus
	assert app.search_count == 1 && app.search_indices[0] == 0
	app.key_input('\x01привет МОСКВА')
	assert app.search_count == 1 && app.search_indices[0] == 1
	app.key_input('\x01planning office')
	assert app.search_count == 1 && app.search_indices[0] == 2
	app.key_input('\x01planning madrid missing')
	assert app.search_count == 0
	assert app.year == 2026 && app.month == 10 && app.selected_day == 5
}

fn test_calendar_search_orders_dates_all_day_and_time_stably() {
	home := calendar_search_test_home('order')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := calendar_search_test_app(home)
	defer { app.close_app() }
	calendar_search_test_add(mut app, 2027, 1, 1, -1, 'Event', '')
	calendar_search_test_add(mut app, 2026, 10, 5, 800, 'Event', '')
	calendar_search_test_add(mut app, 2026, 10, 5, -1, 'Event', '')
	calendar_search_test_add(mut app, 2026, 10, 5, 600, 'Event', '')
	calendar_search_test_add(mut app, 2026, 10, 5, 600, 'Event', '')
	calendar_search_test_add(mut app, 1, 1, 1, -1, 'Event', '')
	app.key_input('\x06')
	assert app.search_count == 6
	for row, expected in [5, 2, 3, 4, 1, 0]! { assert app.search_indices[row] == expected }
}

fn test_calendar_search_pages_full_store_and_clamps_after_resize_and_deletion() {
	home := calendar_search_test_home('paging')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := calendar_search_test_app(home)
	defer { app.close_app() }
	for index in 0 .. calendar_events_limit {
		calendar_search_test_add(mut app, 2026, 10, 5, index, 'Event', '')
	}
	app.key_input('\x06event')
	root := app.build(ui2.rect(0, 0, 400, 476))!
	assert app.search_visible == 5 && app.search_count == calendar_events_limit
	free_tree(root)
	app.key_input('\x1b[F')
	assert app.search_scroll == 125
	app.handle('calendar.search.next')!
	assert app.search_scroll == 125
	app.handle('calendar.search.previous')!
	assert app.search_scroll == 120
	resized := app.build(ui2.rect(0, 0, 640, 640))!
	assert app.search_visible == 8 && app.search_scroll == 120
	free_tree(resized)
	for index in 3 .. app.events.count {
		unsafe { app.events.items[index].title.free() app.events.items[index].location.free() }
		app.events.items[index] = CalendarEvent{}
	}
	app.events.count = 3
	refreshed := app.build(ui2.rect(0, 0, 640, 466))!
	assert app.search_scroll == 0 && app.search_count == 3
	free_tree(refreshed)
}

fn test_calendar_search_result_opens_actual_date_and_saves_without_moving_event() {
	home := calendar_search_test_home('open-save')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := calendar_search_test_app(home)
	defer { app.close_app() }
	calendar_search_test_add(mut app, 2024, 2, 29, 825, 'Remote event', 'Café')
	assert app.events.save()
	app.key_input('\x06remote')
	app.handle(app.events.actions[0])!
	assert app.editing && app.edit_index == 0 && !app.search_focus
	assert app.year == 2024 && app.month == 2 && app.selected_day == 29
	assert editor_bytes_text(app.edit_title) == 'Remote event'
	assert editor_bytes_text(app.edit_time) == '13:45'
	app.key_input('\x01Revised event')
	app.save_event()
	assert !app.editing && app.events.items[0].year == 2024 && app.events.items[0].month == 2 && app.events.items[0].day == 29
	root := app.build(ui2.rect(0, 0, 400, 476))!
	assert app.search_active && app.search_text() == 'remote' && app.search_count == 0
	free_tree(root)
	app.handle('calendar.search.back')!
	assert !app.search_active && app.search_len == 0
	app.change_month(1)
	assert app.year == 2024 && app.month == 3 && app.selected_day == 29
	mut restored := calendar_search_test_app(home)
	defer { restored.close_app() }
	assert restored.events.items[0].title == 'Revised event' && restored.events.items[0].day == 29
}

fn test_calendar_search_cancel_keeps_query_and_drafts_ignore_find_shortcut() {
	home := calendar_search_test_home('drafts')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := calendar_search_test_app(home)
	defer { app.close_app() }
	calendar_search_test_add(mut app, 2027, 3, 6, -1, 'Future', 'Office')
	app.key_input('\x06future')
	app.handle(app.events.actions[0])!
	app.key_input('\x01Draft\x06')
	assert app.editing && editor_bytes_text(app.edit_title) == 'Draft'
	assert app.search_text() == 'future'
	app.handle('calendar.event.cancel')!
	assert !app.editing && app.search_active
	assert app.events.items[0].title == 'Future'
	app.clear_search()
	app.open_interchange()
	app.paste_input('/tmp/draft.ics')
	before := editor_bytes_text(app.ics_import_path).clone()
	defer { unsafe { before.free() } }
	app.key_input('\x06')
	assert app.interchange && !app.search_active && editor_bytes_text(app.ics_import_path) == before
}

fn test_calendar_search_utf8_typing_is_bounded_and_backspace_removes_whole_runes() {
	home := calendar_search_test_home('utf8')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := calendar_search_test_app(home)
	defer { app.close_app() }
	app.key_input('\x06\xd0')
	assert app.search_len == 0 && app.search_pending_len == 1
	app.key_input('\x96é')
	assert app.search_text() == 'Жé'
	app.key_input('\x7f')
	assert app.search_text() == 'Ж'
	app.key_input('\x01')
	for _ in 0 .. 127 { app.key_input('a') }
	app.key_input('é')
	assert app.search_len == 127 && app.search_pending_len == 0
	app.key_input('b')
	assert app.search_len == 128
	app.key_input('c')
	assert app.search_len == 128
	app.key_input('\x01\xd0\t\x96X')
	assert app.search_text() == 'X' && app.search_pending_len == 0
}

fn test_calendar_search_paste_is_validated_atomic_text_and_control_separators() {
	home := calendar_search_test_home('paste')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := calendar_search_test_app(home)
	defer { app.close_app() }
	app.key_input('\x06original\x01')
	oversized := 'Ж'.repeat(65)
	defer { unsafe { oversized.free() } }
	app.paste_input(oversized)
	assert app.search_text() == 'original' && app.search_selected
	app.paste_input('Café\tOffice\nМосква\r\x1b\x06')
	assert app.search_text() == 'Café Office Москва '
	assert app.search_active && !app.editing && app.search_escape_len == 0
	app.key_input('\x01')
	app.paste_input('\xff\xc0\x80OK\xe2')
	assert app.search_text() == 'OK'
	app.key_input('\x01')
	app.paste_input('\x00\x01\x1b')
	assert app.search_text() == 'OK' && app.search_selected
}

fn test_calendar_search_fragmented_navigation_cannot_modify_query() {
	home := calendar_search_test_home('sequences')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := calendar_search_test_app(home)
	defer { app.close_app() }
	for index in 0 .. 12 { calendar_search_test_add(mut app, 2026, 10, 5, index, 'Event', '') }
	app.key_input('\x06event')
	root := app.build(ui2.rect(0, 0, 400, 476))!
	free_tree(root)
	app.key_input('\x1b')
	app.key_input('[')
	app.key_input('6')
	app.key_input('~')
	assert app.search_text() == 'event' && app.search_scroll == 5
	app.key_input('\x1bO')
	app.key_input('B')
	assert app.search_text() == 'event' && app.search_scroll == 10
	app.key_input('\x1b')
	app.key_input('[H')
	assert app.search_scroll == 0 && app.search_text() == 'event'
	app.key_input('\x1b[123456789012345678901234567890')
	assert app.search_escape_len == app.search_escape.len
	app.key_input('123~')
	assert app.search_escape_len == 0 && app.search_text() == 'event'
}

fn test_calendar_search_lone_escape_expires_and_fragment_timeout_keeps_query() {
	home := calendar_search_test_home('escape')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := calendar_search_test_app(home)
	defer { app.close_app() }
	app.key_input('\x06query\x1b')
	assert app.next_poll_ms() == 100
	assert !app.expire_search_escape(app.search_escape_ms + 99)
	assert app.expire_search_escape(app.search_escape_ms + 100)
	assert !app.search_active && !app.search_focus && app.search_len == 0
	assert app.next_poll_ms() == 2000
	app.key_input('\x06query\x1b[')
	assert !app.expire_search_escape(~u64(0))
	assert app.search_active && app.search_text() == 'query' && app.search_escape_len == 0
}

fn test_calendar_search_ui_has_visible_labels_dated_rows_and_compact_controls() {
	home := calendar_search_test_home('ui')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := calendar_search_test_app(home)
	defer { app.close_app() }
	for index in 0 .. 12 { calendar_search_test_add(mut app, 2026, 10, 5, index, 'Event', 'Office') }
	saved_language := desktop_language
	defer { desktop_language = saved_language }
	for language in [DesktopLanguage.en, .es, .ru]! {
		desktop_language = language
		month := app.build(ui2.rect(0, 0, 400, 476))!
		assert calendar_search_test_element(month, 'calendar.search.label') != none
		assert calendar_search_test_element(month, 'calendar.day.1') != none
		free_tree(month)
		app.key_input('\x06event')
		for size in [ui2.rect(0, 0, 400, 476), ui2.rect(0, 0, 640, 466), ui2.rect(0, 0, 360, 300), ui2.rect(0, 0, 400, 210)]! {
			root := app.build(size)!
			field := calendar_search_test_element(root, 'calendar.search') or { panic('Search field missing') }
			clear := calendar_search_test_element(root, 'calendar.search.clear') or { panic('Clear missing') }
			assert field.frame.width > 0 && field.frame.x + field.frame.width < clear.frame.x
			assert clear.frame.x + clear.frame.width <= size.width - 18
			assert calendar_search_test_element(root, 'calendar.event.row.0') != none
			assert calendar_search_test_element(root, 'calendar.search.next') != none
			next := calendar_search_test_element(root, 'calendar.search.next') or { panic('Next missing') }
			assert 120 + (app.search_visible - 1) * 60 + 58 < next.frame.y
			for child in root.children { assert child.frame.y + child.frame.height <= size.height }
			free_tree(root)
		}
		app.handle('calendar.search.clear')!
	}
}

fn test_calendar_search_import_delete_and_empty_states_refresh_full_store() {
	home := calendar_search_test_home('refresh')
	input := home + '/input.ics'
	defer { os.rmdir_all(home) or {} unsafe { home.free() input.free() } }
	os.write_file(input, 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:Vinix tests\r\nBEGIN:VEVENT\r\nUID:future\r\nDTSTAMP:20261006T120000Z\r\nDTSTART;VALUE=DATE:20300203\r\nSUMMARY:Future event\r\nLOCATION:Office\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n')!
	mut app := calendar_search_test_app(home)
	defer { app.close_app() }
	app.key_input('\x06future')
	app.import_ics(input)
	assert app.ics_status == 'calendar.ics.imported'
	root := app.build(ui2.rect(0, 0, 400, 476))!
	assert app.search_count == 1
	free_tree(root)
	app.handle(app.events.actions[0])!
	app.delete_event()
	empty := app.build(ui2.rect(0, 0, 400, 476))!
	assert app.search_count == 0 && app.search_scroll == 0
	assert calendar_search_test_element(empty, 'calendar.event.row.0') == none
	free_tree(empty)
	app.events.read_failed = true
	failed := app.build(ui2.rect(0, 0, 400, 476))!
	assert app.search_count == 0
	free_tree(failed)
}

fn test_calendar_search_tiny_windows_keep_month_navigation_and_back_reachable() {
	home := calendar_search_test_home('tiny')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := calendar_search_test_app(home)
	defer { app.close_app() }
	for size in [ui2.rect(0, 0, 180, 96), ui2.rect(0, 0, 360, 300)]! {
		month := app.build(size)!
		assert calendar_search_test_element(month, 'calendar.previous') != none
		assert calendar_search_test_element(month, 'calendar.next') != none
		assert calendar_search_test_element(month, 'calendar.search') != none
		for child in month.children {
			assert child.frame.x >= 0 && child.frame.y >= 0 && child.frame.width > 0 && child.frame.height > 0
			assert child.frame.x + child.frame.width <= size.width && child.frame.y + child.frame.height <= size.height
		}
		free_tree(month)
		app.key_input('\x06query')
		small := app.build(ui2.rect(0, 0, 180, 96))!
		assert calendar_search_test_element(small, 'calendar.search.back') != none
		for child in small.children {
			assert child.frame.x >= 0 && child.frame.y >= 0 && child.frame.width > 0 && child.frame.height > 0
			assert child.frame.x + child.frame.width <= 180 && child.frame.y + child.frame.height <= 96
		}
		free_tree(small)
		app.handle('calendar.search.back')!
	}
}
