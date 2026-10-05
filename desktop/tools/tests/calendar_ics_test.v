// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn C.mkfifo(path &char, mode u32) int

const calendar_ics_test_header = 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:Vinix tests\r\n'
const calendar_ics_test_event = 'BEGIN:VEVENT\r\nUID:test-one\r\nDTSTAMP:20261005T120059Z\r\nDTSTART;VALUE=DATE:20261005\r\nSUMMARY:Planning\r\nEND:VEVENT\r\n'
const calendar_ics_test_valid = calendar_ics_test_header + calendar_ics_test_event + 'END:VCALENDAR\r\n'

fn calendar_ics_test_home(suffix string) string {
	home := os.join_path(os.temp_dir(), 'vinix-calendar-ics-${os.getpid()}-${suffix}')
	os.mkdir(home) or { panic(err) }
	defer { unsafe { home.free() } }
	return os.real_path(home)
}

fn calendar_ics_test_app(home string) CalendarApp {
	mut app := CalendarApp{year: 2026, month: 10, selected_day: 5}
	app.refresh_labels()
	app.events.load(home)
	return app
}

fn calendar_ics_test_element(root ui2.Element, id string) ?ui2.Element {
	if root.id == id { return root }
	for child in root.children {
		found := calendar_ics_test_element(child, id) or { continue }
		return found
	}
	return none
}

fn test_calendar_ics_supported_dates_text_folding_and_property_order() {
	text := 'begin:vcalendar\nversion:2.0\nprodid:Tests\nBEGIN:VEVENT\nSUMMARY:Café\\, Привет\\; \\世界\nUID:one\nDTSTART;VALUE=DATE:20240229\nDTEND;VALUE=DATE:20240301\nDTSTAMP:20260101T235959Z\nLOCATION:Room\\; A\\, B\nEND:VEVENT\nBEGIN:VEVENT\nUID:two\nDTSTAMP:20261005T120000Z\nSUMMARY:Local meeting\nDTSTART;VALUE=DATE-TIME:20261231T234500\nEND:VEVENT\nEND:VCALENDAR\n'
	// A literal backslash must be escaped independently of the Unicode text.
	valid := text.replace('\\世界', '\\\\世界')
	mut model, status := calendar_ics_parse(valid)
	defer { model.free_items() unsafe { valid.free() } }
	assert status == ''
	assert model.count == 2
	assert model.items[0].year == 2024 && model.items[0].day == 29
	assert model.items[0].minutes == -1
	assert model.items[0].title == 'Café, Привет; \\世界'
	assert model.items[0].location == 'Room; A, B'
	assert model.items[1].minutes == 1425
	// RFC unfolding happens before UTF-8 decoding, including a folded byte pair.
	folded := calendar_ics_test_valid.replace('Planning', 'Caf\xc3\r\n \xa9')
	mut folded_model, folded_status := calendar_ics_parse(folded)
	defer { folded_model.free_items() unsafe { folded.free() } }
	assert folded_status == ''
	assert folded_model.items[0].title == 'Café'
}

fn test_calendar_ics_rejects_unrepresentable_semantics_explicitly() {
	for property in ['RRULE:FREQ=DAILY', 'DURATION:PT1H', 'DTEND:20261005T130000',
		'DESCRIPTION:Do not lose this', 'STATUS:CANCELLED', 'ATTENDEE:mailto:a@example.com',
		'BEGIN:VALARM', 'DTSTART;TZID=Europe/Moscow:20261005T120000']! {
		input := calendar_ics_test_valid.replace('SUMMARY:Planning', property + '\r\nSUMMARY:Planning')
		mut model, status := calendar_ics_parse(input)
		assert status == 'calendar.ics.unsupported'
		assert model.count == 0
		model.free_items()
		unsafe { input.free() }
	}
	for date in ['20261005T120000Z', '20261005T120001']! {
		input := calendar_ics_test_valid.replace('DTSTART;VALUE=DATE:20261005', 'DTSTART:' + date)
		mut model, status := calendar_ics_parse(input)
		assert status == 'calendar.ics.unsupported'
		model.free_items()
		unsafe { input.free() }
	}
	for end in ['20261005', '20261007']! {
		input := calendar_ics_test_valid.replace('SUMMARY:Planning', 'DTEND;VALUE=DATE:' + end + '\r\nSUMMARY:Planning')
		mut model, status := calendar_ics_parse(input)
		assert status == 'calendar.ics.unsupported'
		model.free_items()
		unsafe { input.free() }
	}
}

fn test_calendar_ics_damaged_input_and_missing_required_properties_are_rejected() {
	for replacement in ['DTSTART;VALUE=DATE:20260230', 'DTSTART;VALUE=DATE:00001005',
		'DTSTART:20261005T240000', 'DTSTART:20261005T126000']! {
		input := calendar_ics_test_valid.replace('DTSTART;VALUE=DATE:20261005', replacement)
		mut model, status := calendar_ics_parse(input)
		assert status == 'calendar.ics.invalid'
		assert model.count == 0
		model.free_items()
		unsafe { input.free() }
	}
	for property in ['UID:test-one\r\n', 'DTSTAMP:20261005T120059Z\r\n', 'SUMMARY:Planning\r\n',
		'VERSION:2.0\r\n', 'PRODID:Vinix tests\r\n', 'END:VEVENT\r\n']! {
		input := calendar_ics_test_valid.replace(property, '')
		mut model, status := calendar_ics_parse(input)
		assert status.len > 0
		assert model.count == 0
		model.free_items()
		unsafe { input.free() }
	}
	for title in ['', 'bad\\q', 'raw,comma', 'raw;semicolon', 'bad\xff', 'bad\x00', 'line\\nnext']! {
		input := calendar_ics_test_valid.replace('Planning', title)
		mut model, status := calendar_ics_parse(input)
		assert status.len > 0
		model.free_items()
		unsafe { input.free() }
	}
	for input in ['BEGIN:VCALENDAR\r', calendar_ics_test_valid + 'SUMMARY:Trailing\r\n',
		calendar_ics_test_header + calendar_ics_test_event + calendar_ics_test_event.replace('Planning', 'Planning\r\nSUMMARY:Again') + 'END:VCALENDAR\r\n']! {
		mut model, status := calendar_ics_parse(input)
		assert status == 'calendar.ics.invalid'
		model.free_items()
	}
}

fn test_calendar_ics_bounds_apply_to_files_lines_fields_and_duplicate_components() {
	for title in ['x'.repeat(161), 'x'.repeat(1025)]! {
		input := calendar_ics_test_valid.replace('Planning', title)
		mut model, status := calendar_ics_parse(input)
		assert status == 'calendar.ics.limit'
		model.free_items()
		unsafe { input.free() title.free() }
	}
	components := calendar_ics_test_event.repeat(129)
	too_many := calendar_ics_test_header + components + 'END:VCALENDAR\r\n'
	mut model, status := calendar_ics_parse(too_many)
	assert status == 'calendar.ics.limit'
	assert model.count == 0
	model.free_items()
	oversize := 'x'.repeat(calendar_ics_max_bytes + 1)
	mut oversized, oversized_status := calendar_ics_parse(oversize)
	assert oversized_status == 'calendar.ics.limit'
	oversized.free_items()
	unsafe { components.free() too_many.free() oversize.free() }
}

fn test_calendar_ics_uid_conflicts_and_identical_components() {
	identical := calendar_ics_test_header + calendar_ics_test_event + calendar_ics_test_event + 'END:VCALENDAR\r\n'
	mut model, status := calendar_ics_parse(identical)
	assert status == ''
	assert model.count == 1
	model.free_items()
	changed := identical.replace('END:VEVENT\r\nEND:VCALENDAR', 'LOCATION:Different\r\nEND:VEVENT\r\nEND:VCALENDAR')
	mut conflict, conflict_status := calendar_ics_parse(changed)
	assert conflict_status == 'calendar.ics.duplicate'
	assert conflict.count == 0
	conflict.free_items()
	unsafe { identical.free() changed.free() }
}

fn test_calendar_ics_import_merges_semantic_duplicates_and_persists_without_replacing() {
	home := calendar_ics_test_home('merge')
	defer { os.rmdir_all(home) or {} }
	input := home + '/input.ics'
	second := calendar_ics_test_event.replace('UID:test-one', 'UID:other').replace('Planning', 'Second')
	duplicate := calendar_ics_test_event.replace('UID:test-one', 'UID:same-content')
	os.write_file(input, calendar_ics_test_header + calendar_ics_test_event + duplicate + second + 'END:VCALENDAR\r\n')!
	mut app := calendar_ics_test_app(home)
	defer { app.close_app() }
	app.begin_event(-1)
	app.key_input('Planning')
	app.save_event()
	app.import_ics(input)
	assert app.ics_status == 'calendar.ics.imported'
	assert app.events.count == 2
	assert app.events.items[0].title == 'Planning'
	assert app.events.items[1].title == 'Second'
	app.import_ics(input)
	assert app.ics_status == 'calendar.ics.nothing'
	assert app.events.count == 2
	mut reopened := calendar_ics_test_app(home)
	defer { reopened.close_app() }
	assert reopened.events.count == 2
	assert reopened.events.items[1].title == 'Second'
}

fn test_calendar_ics_invalid_later_event_and_stale_window_import_are_atomic() {
	home := calendar_ics_test_home('atomic')
	defer { os.rmdir_all(home) or {} }
	input := home + '/input.ics'
	mut first := calendar_ics_test_app(home)
	mut stale := calendar_ics_test_app(home)
	defer { first.close_app() stale.close_app() }
	first.begin_event(-1)
	first.key_input('Existing')
	first.save_event()
	before := os.read_file(home + '/' + calendar_events_filename)!
	os.write_file(input, calendar_ics_test_header + calendar_ics_test_event + 'BEGIN:VEVENT\r\nUID:broken\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n')!
	first.import_ics(input)
	assert first.ics_status == 'calendar.ics.invalid'
	assert first.events.count == 1
	assert first.events.items[0].title == 'Existing'
	assert os.read_file(home + '/' + calendar_events_filename)! == before
	os.write_file(input, calendar_ics_test_valid)!
	stale.import_ics(input)
	assert stale.ics_status == 'calendar.event.changed'
	assert stale.events.count == 0
	assert os.read_file(home + '/' + calendar_events_filename)! == before
}

fn test_calendar_ics_capacity_and_failed_save_preserve_existing_events() {
	home := calendar_ics_test_home('capacity')
	defer { os.rmdir_all(home) or {} }
	input := home + '/input.ics'
	os.write_file(input, calendar_ics_test_valid)!
	mut app := calendar_ics_test_app(home)
	defer { app.close_app() }
	for index in 0 .. calendar_events_limit {
		app.events.items[index] = CalendarEvent{year: 2026, month: 10, day: 5, title: 'Existing'.clone()}
	}
	app.events.count = calendar_events_limit
	assert app.events.save()
	before := os.read_file(home + '/' + calendar_events_filename)!
	app.import_ics(input)
	assert app.ics_status == 'calendar.ics.limit'
	assert app.events.count == calendar_events_limit
	assert os.read_file(home + '/' + calendar_events_filename)! == before
	app.events.free_items()
	assert app.events.save()
	// A symlink lock is refused before changing the record.
	lock_path := home + '/' + '.vinix-calendar-events.lock'
	os.rm(lock_path)!
	os.symlink('missing', lock_path)!
	app.import_ics(input)
	assert app.ics_status == 'calendar.event.save_failed'
	assert app.events.count == 0
	mut reopened := calendar_ics_test_app(home)
	defer { reopened.close_app() }
	assert reopened.events.count == 0
}

fn test_calendar_ics_read_rejects_symlinks_directories_fifos_and_oversized_files() {
	home := calendar_ics_test_home('unsafe-read')
	defer { os.rmdir_all(home) or {} }
	path := home + '/input.ics'
	link := home + '/link.ics'
	fifo := home + '/fifo.ics'
	os.write_file(path, calendar_ics_test_valid)!
	os.symlink(path, link)!
	assert C.mkfifo(&char(fifo.str), 0o600) == 0
	for bad_path in [link, fifo, home, 'relative.ics']! {
		text, status := calendar_ics_read(bad_path)
		assert status.len > 0
		assert text.len == 0
	}
	os.write_file(path, 'x'.repeat(calendar_ics_max_bytes + 1))!
	_, status := calendar_ics_read(path)
	assert status == 'calendar.ics.limit'
}

fn test_calendar_ics_damaged_saved_calendar_refuses_import_and_export() {
	home := calendar_ics_test_home('damaged-store')
	defer { os.rmdir_all(home) or {} }
	record := home + '/' + calendar_events_filename
	input := home + '/input.ics'
	output := home + '/output.ics'
	os.write_file(record, 'damaged')!
	os.write_file(input, calendar_ics_test_valid)!
	mut app := calendar_ics_test_app(home)
	defer { app.close_app() }
	app.import_ics(input)
	assert app.ics_status == 'calendar.event.read_failed'
	app.export_ics(output)
	assert app.ics_status == 'calendar.event.read_failed'
	assert !os.exists(output)
	assert os.read_file(record)! == 'damaged'
}

fn test_calendar_ics_export_roundtrip_folds_utf8_and_requires_new_regular_path() {
	home := calendar_ics_test_home('export')
	defer { os.rmdir_all(home) or {} }
	output := home + '/output.ics'
	mut app := calendar_ics_test_app(home)
	defer { app.close_app() }
	app.events.items[0] = CalendarEvent{year: 2026, month: 10, day: 5, title: 'Café, Привет; 世界\\'.repeat(4), location: 'Room, A; B'.clone()}
	app.events.items[1] = CalendarEvent{year: 2026, month: 12, day: 31, minutes: 1425, title: 'Local'.clone()}
	app.events.count = 2
	app.export_ics(output)
	assert app.ics_status == 'calendar.ics.exported'
	record := os.read_file(output)!
	assert record.contains('DTSTAMP:') && record.contains('UID:')
	assert record.contains('\r\n ')
	assert !record.contains('DTEND:') && !record.contains('TZID')
	for line in record.split('\r\n') {
		assert line.len <= 75
		assert calendar_ics_utf8(line)
	}
	mut imported, status := calendar_ics_parse(record)
	defer { imported.free_items() }
	assert status == ''
	assert imported.count == 2
	assert calendar_ics_equal(imported.items[0], app.events.items[0])
	assert calendar_ics_equal(imported.items[1], app.events.items[1])
	app.export_ics(output)
	assert app.ics_status == 'calendar.ics.export_exists'
	assert os.read_file(output)! == record
	link := home + '/link.ics'
	os.symlink(output, link)!
	app.export_ics(link)
	assert app.ics_status == 'calendar.ics.export_exists'
	assert os.read_file(output)! == record
	alias := home + '-alias'
	os.symlink(home, alias)!
	defer { os.rm(alias) or {} }
	app.export_ics(alias + '/unsafe.ics')
	assert app.ics_status == 'calendar.ics.export_failed'
	assert !os.exists(home + '/unsafe.ics')
}

fn test_calendar_ics_export_rejects_invalid_model_without_creating_output() {
	mut model := CalendarEvents{count: 1}
	model.items[0] = CalendarEvent{year: 2026, month: 2, day: 30, title: 'Invalid'}
	_, status := calendar_ics_encode(&model)
	assert status == 'calendar.ics.invalid'
	model.items[0].day = 28
	model.items[0].minutes = 1440
	_, time_status := calendar_ics_encode(&model)
	assert time_status == 'calendar.ics.invalid'
	model.items[0].minutes = -1
	model.items[0].title = 'Bad\xff'
	_, text_status := calendar_ics_encode(&model)
	assert text_status == 'calendar.ics.invalid'
}

fn test_calendar_ics_failed_save_removes_own_temporary_and_preserves_replacement_inode() {
	home := calendar_ics_test_home('temporary')
	defer { os.rmdir_all(home) or {} }
	fd, temporary := calendar_temporary_file(home)
	assert fd >= 0
	defer { desktop_close(fd) unsafe { temporary.free() } }
	assert calendar_temporary_matches(fd, temporary)
	moved := home + '/moved'
	os.rename(temporary, moved)!
	os.write_file(temporary, 'Replacement must survive')!
	assert !calendar_temporary_matches(fd, temporary)
	assert !calendar_remove_temporary(fd, temporary)
	assert os.read_file(temporary)! == 'Replacement must survive'
	os.rm(temporary)!
	os.rename(moved, temporary)!
	assert calendar_remove_temporary(fd, temporary)
	assert !os.exists(temporary)
	// An invalid record destination leaves no private siblings.
	mut app := calendar_ics_test_app(home)
	defer { app.close_app() }
	os.mkdir(home + '/' + calendar_events_filename)!
	app.events.items[0] = CalendarEvent{year: 2026, month: 10, day: 5, title: 'Owned'.clone()}
	app.events.count = 1
	assert !app.events.save()
	for entry in os.ls(home)! { assert !entry.starts_with('.vinix-calendar.') }
}

fn test_calendar_ics_native_panel_keyboard_paste_resize_and_registered_home_alias() {
	home := calendar_ics_test_home('ui')
	defer { os.rmdir_all(home) or {} }
	alias := home + '-alias'
	os.symlink(home, alias)!
	defer { os.rm(alias) or {} }
	mut app := calendar_ics_test_app(alias)
	defer { app.close_app() }
	begin_frame_elements()
	agenda := app.build(ui2.rect(0, 0, 640, 476))!
	assert calendar_ics_test_element(agenda, 'calendar.ics.open') != none
	free_tree(agenda)
	app.handle('calendar.ics.open')!
	assert app.interchange
	assert editor_bytes_text(app.ics_export_path) == calendar_ics_home(home) + '/Calendar-export.ics'
	for size in [ui2.rect(0, 0, 640, 476), ui2.rect(0, 0, 820, 560), ui2.rect(0, 0, 360, 300)]! {
		begin_frame_elements()
		tree := app.build(size)!
		assert calendar_ics_test_element(tree, 'calendar.ics.back') != none
		if size.width >= 400 {
			for id in ['calendar.ics.import_path', 'calendar.ics.export_path', 'calendar.ics.import', 'calendar.ics.export']! {
				assert calendar_ics_test_element(tree, id) != none
			}
		}
		free_tree(tree)
	}
	app.key_input('\x01')
	app.paste_input('/tmp/Café\n\t\r\x1b')
	assert editor_bytes_text(app.ics_import_path) == '/tmp/Café'
	assert app.events.count == 0
	app.key_input('\x01\xd0')
	app.key_input('\x96')
	assert editor_bytes_text(app.ics_import_path) == 'Ж'
	app.key_input('\x7f')
	assert app.ics_import_path.len == 0
	app.key_input('\x1b[A')
	assert app.interchange && app.ics_import_path.len == 0
	input := home + '/Calendar.ics'
	os.write_file(input, calendar_ics_test_valid)!
	app.paste_input(input)
	app.key_input('\r')
	assert app.ics_status == 'calendar.ics.imported'
	app.key_input('\t\r')
	assert app.ics_status == 'calendar.ics.exported'
	assert os.exists(home + '/Calendar-export.ics')
	app.key_input('\x1b')
	assert !app.interchange
}
