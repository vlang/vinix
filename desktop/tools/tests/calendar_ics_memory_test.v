// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

#include "@VMODROOT/heap_tracker.h"

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

const calendar_ics_memory_valid = 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:Vinix tests\r\nBEGIN:VEVENT\r\nUID:one\r\nDTSTAMP:20261005T120000Z\r\nDTSTART;VALUE=DATE:20261005\r\nSUMMARY:Café\\, Привет\\; 世界\r\nLOCATION:Room\\; A\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n'

fn calendar_ics_memory_home(suffix string) string {
	path := os.join_path(os.temp_dir(), 'vinix-calendar-ics-memory-${os.getpid()}-${suffix}')
	os.mkdir(path) or { panic(err) }
	defer { unsafe { path.free() } }
	return os.real_path(path)
}

fn calendar_ics_memory_app(home string) CalendarApp {
	mut app := CalendarApp{year: 2026, month: 10, selected_day: 5}
	app.refresh_labels()
	app.events.load(home)
	return app
}

fn test_calendar_ics_parser_releases_complete_draft_duplicate_and_error_allocations() {
	tail := calendar_ics_memory_valid.all_after('PRODID:Vinix tests\r\n')
	changed := tail.replace('Café\\, Привет\\; 世界', 'Different')
	duplicate := calendar_ics_memory_valid.replace('END:VCALENDAR\r\n', tail)
	conflict := calendar_ics_memory_valid.replace('END:VCALENDAR\r\n', changed)
	invalid := calendar_ics_memory_valid.replace('END:VCALENDAR\r\n', 'BEGIN:VEVENT\r\nUID:bad\r\nSUMMARY:Bad\r\nRRULE:FREQ=DAILY\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n')
	long_title := 'x'.repeat(161)
	too_long := calendar_ics_memory_valid.replace('Café\\, Привет\\; 世界', long_title)
	defer { unsafe { tail.free() changed.free() duplicate.free() conflict.free() invalid.free() long_title.free() too_long.free() } }
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		for input in [calendar_ics_memory_valid, duplicate, conflict, invalid, too_long]! {
			mut model, status := calendar_ics_parse(input)
			if status == '' { assert model.count == 1 } else { assert model.count == 0 }
			model.free_items()
		}
	}
	assert C.vinix_heap_end() == 0
}

fn test_calendar_ics_repeated_export_encode_decode_and_rejected_models_free_owned_memory() {
	mut source, status := calendar_ics_parse(calendar_ics_memory_valid)
	assert status == ''
	defer { source.free_items() }
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		bytes, encoded_status := calendar_ics_encode(&source)
		assert encoded_status == ''
		mut restored, parsed_status := calendar_ics_parse(editor_bytes_text(bytes))
		assert parsed_status == ''
		assert calendar_ics_equal(source.items[0], restored.items[0])
		restored.free_items()
		unsafe { bytes.free() }
		source.items[0].minutes = 1440
		_, rejected_status := calendar_ics_encode(&source)
		assert rejected_status == 'calendar.ics.invalid'
		source.items[0].minutes = -1
	}
	assert C.vinix_heap_end() == 0
}

fn test_calendar_ics_complete_init_panel_keyboard_resize_and_close_free_all_owned_memory() {
	home := calendar_ics_memory_home('ui')
	alias := home + '-alias'
	os.symlink(home, alias)!
	defer { os.rm(alias) or {} os.rmdir_all(home) or {} unsafe { home.free() alias.free() } }
	saved_language := desktop_language
	defer { desktop_language = saved_language }
	mut warm := calendar_ics_memory_app(alias)
	warm.open_interchange()
	for size in [ui2.rect(0, 0, 400, 476), ui2.rect(0, 0, 640, 476), ui2.rect(0, 0, 360, 300), ui2.rect(0, 0, 820, 560)]! {
		begin_frame_elements()
		free_tree(warm.build(size)!)
	}
	warm.close_app()
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut app := calendar_ics_memory_app(alias)
		app.open_interchange()
		app.key_input('\x01')
		app.paste_input('/tmp/Café')
		app.key_input('\x7f\xd0')
		app.key_input('\x96\t\x01')
		app.paste_input('/tmp/Привет\r\n\t')
		for language in [DesktopLanguage.en, .es, .ru]! {
			desktop_language = language
			for size in [ui2.rect(0, 0, 400, 476), ui2.rect(0, 0, 640, 476), ui2.rect(0, 0, 360, 300), ui2.rect(0, 0, 820, 560)]! {
				begin_frame_elements()
				free_tree(app.build(size)!)
			}
		}
		app.close_app()
	}
	assert C.vinix_heap_end() == 0
}

fn test_calendar_ics_repeated_merge_persist_reload_and_exclusive_export_release_owned_memory() {
	home := calendar_ics_memory_home('io')
	input := home + '/input.ics'
	output := home + '/output.ics'
	record := home + '/' + calendar_events_filename
	os.write_file(input, calendar_ics_memory_valid)!
	defer { os.rmdir_all(home) or {} unsafe { home.free() input.free() output.free() record.free() } }
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut app := calendar_ics_memory_app(home)
		app.import_ics(input)
		assert app.ics_status == 'calendar.ics.imported'
		assert app.events.count == 1
		app.import_ics(input)
		assert app.ics_status == 'calendar.ics.nothing'
		app.export_ics(output)
		assert app.ics_status == 'calendar.ics.exported'
		app.export_ics(output)
		assert app.ics_status == 'calendar.ics.export_exists'
		mut reopened := calendar_ics_memory_app(home)
		assert reopened.events.count == 1
		reopened.close_app()
		app.close_app()
		assert C.unlink(&char(record.str)) == 0
		assert C.unlink(&char(output.str)) == 0
	}
	assert C.vinix_heap_end() == 0
}

fn test_calendar_ics_repeated_read_parse_and_save_failures_rollback_without_memory_growth() {
	home := calendar_ics_memory_home('failures')
	input := home + '/input.ics'
	bad := home + '/bad.ics'
	missing := home + '/missing.ics'
	lock_path := home + '/.vinix-calendar-events.lock'
	os.write_file(input, calendar_ics_memory_valid)!
	bad_record := calendar_ics_memory_valid.replace('DTSTART;VALUE=DATE:20261005', 'DTSTART;VALUE=DATE:20260230')
	os.write_file(bad, bad_record)!
	unsafe { bad_record.free() }
	os.symlink('missing', lock_path)!
	defer { os.rmdir_all(home) or {} unsafe { home.free() input.free() bad.free() missing.free() lock_path.free() } }
	mut app := calendar_ics_memory_app(home)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		app.import_ics(missing)
		assert app.ics_status == 'calendar.ics.read_failed'
		app.import_ics(bad)
		assert app.ics_status == 'calendar.ics.invalid'
		app.import_ics(input)
		assert app.ics_status == 'calendar.event.save_failed'
		assert app.events.count == 0
		app.export_ics('relative.ics')
		assert app.ics_status == 'calendar.ics.path_invalid'
	}
	app.close_app()
	assert C.vinix_heap_end() == 0
}

fn test_calendar_ics_repeated_damaged_calendar_init_and_blocked_interchange_release_memory() {
	home := calendar_ics_memory_home('damaged')
	record := home + '/' + calendar_events_filename
	input := home + '/input.ics'
	output := home + '/output.ics'
	os.write_file(record, 'VINIX-CALENDAR 1\n2026\t10\t5\t-1\tValid first row\t\n2026\t2\t30\t-1\tDamaged later row\t\n')!
	os.write_file(input, calendar_ics_memory_valid)!
	defer { os.rmdir_all(home) or {} unsafe { home.free() record.free() input.free() output.free() } }
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut app := calendar_ics_memory_app(home)
		assert app.events.read_failed
		app.open_interchange()
		app.import_ics(input)
		assert app.ics_status == 'calendar.event.read_failed'
		app.export_ics(output)
		assert app.ics_status == 'calendar.event.read_failed'
		app.close_app()
	}
	assert C.vinix_heap_end() == 0
}
