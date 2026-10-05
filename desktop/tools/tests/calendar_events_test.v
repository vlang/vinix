// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn calendar_test_home(suffix string) string {
	home := os.join_path(os.temp_dir(), 'vinix-calendar-${os.getpid()}-${suffix}')
	os.mkdir(home) or { panic(err) }
	return home
}

fn calendar_test_app(home string) CalendarApp {
	mut app := CalendarApp{ year: 2026, month: 10, selected_day: 5 }
	app.refresh_labels()
	app.events.load(home)
	return app
}

fn test_calendar_events_create_edit_delete_and_reload() {
	home := calendar_test_home('roundtrip')
	defer { os.rmdir_all(home) or {} }
	mut app := calendar_test_app(home)
	defer { app.close_app() }
	app.begin_event(-1)
	app.key_input('Planning')
	app.edit_all_day = false
	app.handle('calendar.event.time') or { panic(err) }
	app.key_input('13:45')
	app.handle('calendar.event.location') or { panic(err) }
	app.key_input('Meeting room')
	app.save_event()
	assert !app.editing
	assert app.events.count == 1
	assert app.events.items[0].minutes == 825
	assert app.events.has_date(2026, 10, 5)
	assert !app.events.has_date(2026, 10, 6)
	mut restored := calendar_test_app(home)
	defer { restored.close_app() }
	assert restored.events.items[0].title == 'Planning'
	assert restored.events.items[0].location == 'Meeting room'
	restored.begin_event(0)
	restored.key_input('\x01Renamed')
	restored.edit_all_day = true
	restored.save_event()
	assert restored.events.items[0].title == 'Renamed'
	assert restored.events.items[0].minutes == -1
	mut edited := calendar_test_app(home)
	defer { edited.close_app() }
	assert edited.events.items[0].title == 'Renamed'
	edited.begin_event(0)
	edited.delete_event()
	assert edited.events.count == 0
	mut empty := calendar_test_app(home)
	defer { empty.close_app() }
	assert empty.events.count == 0
}

fn test_calendar_invalid_input_and_failed_save_keep_event_editor() {
	home := calendar_test_home('validation')
	defer { os.rmdir_all(home) or {} }
	mut app := calendar_test_app(home)
	defer { app.close_app() }
	app.begin_event(-1)
	app.save_event()
	assert app.editing
	assert app.status_key == 'calendar.event.title_required'
	app.key_input('Appointment')
	app.edit_all_day = false
	app.handle('calendar.event.time') or { panic(err) }
	app.key_input('24:00')
	app.save_event()
	assert app.status_key == 'calendar.event.invalid_time'
	assert app.events.count == 0
	app.key_input('\x0112:00')
	// A directory at the destination must be rejected by exact rename.
	path := '${home}/${calendar_events_filename}'
	os.mkdir(path) or { panic(err) }
	app.save_event()
	assert app.editing
	assert app.status_key == 'calendar.event.save_failed'
	assert app.events.count == 0
	assert os.is_dir(path)
}

fn test_calendar_damaged_saved_record_is_preserved() {
	home := calendar_test_home('damaged')
	defer { os.rmdir_all(home) or {} }
	path := '${home}/${calendar_events_filename}'
	record := 'VINIX-CALENDAR 1\n2026\t2\t30\t-1\tImpossible\t\n'
	os.write_file(path, record) or { panic(err) }
	mut app := calendar_test_app(home)
	defer { app.close_app() }
	assert app.events.read_failed
	app.begin_event(-1)
	assert !app.editing
	assert !app.events.save()
	assert os.read_file(path) or { panic(err) } == record
}

fn test_calendar_second_window_does_not_overwrite_newly_saved_events() {
	home := calendar_test_home('concurrent')
	defer { os.rmdir_all(home) or {} }
	mut first := calendar_test_app(home)
	defer { first.close_app() }
	mut second := calendar_test_app(home)
	defer { second.close_app() }
	first.begin_event(-1)
	first.key_input('First window')
	first.save_event()
	second.begin_event(-1)
	second.key_input('Second window')
	second.save_event()
	assert second.editing
	assert second.status_key == 'calendar.event.changed'
	assert second.events.count == 0
	mut restored := calendar_test_app(home)
	defer { restored.close_app() }
	assert restored.events.count == 1
	assert restored.events.items[0].title == 'First window'
}

fn test_calendar_external_lock_refuses_save_then_release_allows_retry() {
	home := calendar_test_home('locked')
	defer { os.rmdir_all(home) or {} }
	mut app := calendar_test_app(home)
	defer { app.close_app() }
	app.begin_event(-1)
	app.key_input('Pending event')
	fd := calendar_lock_acquire(home)
	assert fd >= 0
	app.save_event()
	assert app.editing
	assert app.events.count == 0
	assert app.status_key == 'calendar.event.save_failed'
	assert editor_bytes_text(app.edit_title) == 'Pending event'
	desktop_close(fd)
	app.save_event()
	assert !app.editing
	assert app.events.count == 1
	lock_path := '${home}/.vinix-calendar-events.lock'
	mut stat := C.stat{}
	assert unsafe { C.lstat(&char(lock_path.str), &stat) } == 0
	assert u32(stat.st_mode) & 0o777 == 0o600
}

fn test_calendar_lock_rejects_symbolic_links() {
	home := calendar_test_home('symlink-lock')
	defer { os.rmdir_all(home) or {} }
	path := '${home}/.vinix-calendar-events.lock'
	os.symlink('missing-target', path) or { panic(err) }
	assert calendar_lock_acquire(home) == -1
	assert !os.exists('${home}/missing-target')
}

fn test_calendar_utf8_keyboard_is_bounded_and_backspaces_whole_characters() {
	home := calendar_test_home('utf8')
	defer { os.rmdir_all(home) or {} }
	mut app := calendar_test_app(home)
	defer { app.close_app() }
	app.begin_event(-1)
	app.key_input('Привет')
	assert editor_bytes_text(app.edit_title) == 'Привет'
	app.key_input('\x7f')
	assert editor_bytes_text(app.edit_title) == 'Приве'
	app.key_input('\x01')
	for _ in 0 .. calendar_event_title_limit - 1 { app.key_input('a') }
	app.key_input('é')
	assert app.edit_title.len == calendar_event_title_limit - 1
	app.key_input('b')
	assert app.edit_title.len == calendar_event_title_limit
}

fn test_calendar_parser_validates_gregorian_dates_and_time() {
	mut leap := calendar_parse_events('VINIX-CALENDAR 1\n2024\t2\t29\t1439\tLeap day\t\n') or { panic(err) }
	defer { leap.free_items() }
	assert leap.count == 1
	assert (calendar_parse_time('23:59') or { -1 }) == 1439
	assert calendar_parse_time('9:00') == none
	assert calendar_parse_time('12:60') == none
	for record in [
		'VINIX-CALENDAR 1\n2025\t2\t29\t-1\tInvalid\t\n',
		'VINIX-CALENDAR 1\n2026\t1\t1\t1440\tInvalid\t\n',
		'VINIX-CALENDAR 1\n2026\t1\t1\t-1\t\t\n',
		'VINIX-CALENDAR 1\n2026\t1\t1\t-1\tIncomplete\t',
		'VINIX-CALENDAR 2\n',
	] {
		mut invalid := calendar_parse_events(record) or { continue }
		invalid.free_items()
		assert false, 'parser accepted invalid event'
	}
}

fn test_calendar_clipboard_is_field_text_and_preserves_utf8_boundaries() {
	home := calendar_test_home('clipboard')
	defer { os.rmdir_all(home) or {} }
	mut app := calendar_test_app(home)
	defer { app.close_app() }
	app.begin_event(-1)
	app.paste_input('Café\n\tПривет\r\x1b')
	assert app.editing
	assert app.edit_focus == 0
	assert app.events.count == 0
	assert editor_bytes_text(app.edit_title) == 'CaféПривет'
	app.handle('calendar.event.location') or { panic(err) }
	app.paste_input('Office\nsecond line\t\x01')
	assert app.edit_focus == 2
	assert editor_bytes_text(app.edit_location) == 'Officesecond line'
	app.handle('calendar.event.title') or { panic(err) }
	app.paste_input('й'.repeat(100))
	assert app.edit_title.len == calendar_event_title_limit
	assert app.edit_title[calendar_event_title_limit - 2] == 0xd0
	assert app.edit_title[calendar_event_title_limit - 1] == 0xb9
	app.edit_location << `\t`
	app.save_event()
	assert app.editing
	assert app.status_key == 'calendar.event.invalid_location'
}

fn calendar_test_element(root ui2.Element, id string) ?ui2.Element {
	if root.id == id { return root }
	for child in root.children {
		found := calendar_test_element(child, id) or { continue }
		return found
	}
	return none
}

fn test_calendar_agenda_and_editor_controls_are_reachable() {
	home := calendar_test_home('ui')
	defer { os.rmdir_all(home) or {} }
	mut app := calendar_test_app(home)
	defer { app.close_app() }
	app.begin_event(-1)
	app.key_input('Visible event')
	app.save_event()
	root := app.build(ui2.rect(0, 0, 640, 466)) or { panic(err) }
	assert calendar_test_element(root, 'calendar.event.new') != none
	assert calendar_test_element(root, 'calendar.event.row.0') != none
	free_tree(root)
	app.handle('calendar.event.row.0') or { panic(err) }
	editor := app.build(ui2.rect(0, 0, 640, 466)) or { panic(err) }
	assert calendar_test_element(editor, 'calendar.event.save') != none
	assert calendar_test_element(editor, 'calendar.event.delete') != none
	free_tree(editor)
}
