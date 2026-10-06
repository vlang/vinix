// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

#include "@VMODROOT/heap_tracker.h"

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn calendar_search_memory_home(suffix string) string {
	path := os.join_path(os.temp_dir(), 'vinix-calendar-search-memory-${os.getpid()}-${suffix}')
	os.mkdir(path) or { panic(err) }
	defer { unsafe { path.free() } }
	return os.real_path(path)
}

fn calendar_search_memory_app(home string) CalendarApp {
	mut app := CalendarApp{year: 2026, month: 10, selected_day: 5}
	app.refresh_labels()
	app.events.load(home)
	return app
}

fn calendar_search_memory_add(mut app CalendarApp, count int) {
	for index in 0 .. count {
		app.events.items[index] = CalendarEvent{year: 2024 + index % 4, month: 2, day: 28, minutes: index, title: 'Café Привет'.clone(), location: 'Office Москва'.clone()}
	}
	app.events.count = count
}

fn test_calendar_search_repeated_full_store_input_filter_and_navigation_allocates_nothing() {
	home := calendar_search_memory_home('input')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := calendar_search_memory_app(home)
	calendar_search_memory_add(mut app, calendar_events_limit)
	defer { app.close_app() }
	oversized := 'Ж'.repeat(65)
	defer { unsafe { oversized.free() } }
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		app.key_input('\x06CAFE office')
		assert app.search_count == calendar_events_limit
		app.key_input('\x01\xd0')
		app.key_input('\x96\x7fПРИВЕТ Москва')
		assert app.search_count == calendar_events_limit
		app.key_input('\x1b')
		app.key_input('[6~\x1bO')
		app.key_input('B\x1b[H\x01')
		app.paste_input('Café\tOffice\r\n\x1b\xff')
		assert app.search_count == calendar_events_limit
		app.key_input('\x01')
		app.paste_input(oversized)
		assert app.search_selected
		app.key_input('\x1b[12345678901234567890123')
		app.key_input('4~')
		assert app.search_escape_len == 0
		app.key_input('\x1b')
		assert app.expire_search_escape(~u64(0))
		assert !app.search_active && app.search_len == 0
	}
	assert C.vinix_heap_end() == 0
}

fn test_calendar_search_repeated_all_languages_results_resize_and_owned_row_labels_free() {
	home := calendar_search_memory_home('frames')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut app := calendar_search_memory_app(home)
	calendar_search_memory_add(mut app, calendar_events_limit)
	saved_language := desktop_language
	defer { desktop_language = saved_language }
	app.key_input('\x06cafe office')
	for size in [ui2.rect(0, 0, 400, 476), ui2.rect(0, 0, 640, 466), ui2.rect(0, 0, 360, 300), ui2.rect(0, 0, 820, 640), ui2.rect(0, 0, 180, 96)]! {
		begin_frame_elements()
		free_tree(app.build(size)!)
	}
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		for language in [DesktopLanguage.en, .es, .ru]! {
			desktop_language = language
			for size in [ui2.rect(0, 0, 400, 476), ui2.rect(0, 0, 640, 466), ui2.rect(0, 0, 360, 300), ui2.rect(0, 0, 820, 640), ui2.rect(0, 0, 180, 96)]! {
				begin_frame_elements()
				free_tree(app.build(size)!)
				app.handle('calendar.search.next')!
			}
		}
	}
	// Language changes replace the persistent month/date labels as well as
	// frame text, so finish their ownership before measuring live allocations.
	app.close_app()
	assert C.vinix_heap_end() == 0
}

fn test_calendar_search_repeated_init_editor_cancel_and_close_release_all_owned_memory() {
	home := calendar_search_memory_home('lifetime')
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	mut warm := calendar_search_memory_app(home)
	calendar_search_memory_add(mut warm, 2)
	warm.key_input('\x06cafe')
	warm.handle(warm.events.actions[0])!
	begin_frame_elements()
	free_tree(warm.build(ui2.rect(0, 0, 400, 476))!)
	warm.handle('calendar.event.cancel')!
	begin_frame_elements()
	free_tree(warm.build(ui2.rect(0, 0, 400, 476))!)
	warm.clear_search()
	begin_frame_elements()
	free_tree(warm.build(ui2.rect(0, 0, 400, 476))!)
	warm.close_app()
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut app := calendar_search_memory_app(home)
		calendar_search_memory_add(mut app, 2)
		app.key_input('\x06cafe')
		app.handle(app.events.actions[0])!
		assert app.editing && app.year == 2024 && app.month == 2 && app.selected_day == 28
		app.key_input('\x01Draft\x06')
		app.paste_input(' Café Привет')
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 400, 476))!)
		app.handle('calendar.event.cancel')!
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 400, 476))!)
		app.handle('calendar.search.clear')!
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 400, 476))!)
		app.close_app()
	}
	assert C.vinix_heap_end() == 0
}

fn test_calendar_search_repeated_persist_edit_delete_refilter_and_reload_free_memory() {
	home := calendar_search_memory_home('persistence')
	record := home + '/' + calendar_events_filename
	defer { os.rmdir_all(home) or {} unsafe { home.free() record.free() } }
	mut warm := calendar_search_memory_app(home)
	warm.key_input('\x06')
	begin_frame_elements()
	free_tree(warm.build(ui2.rect(0, 0, 400, 476))!)
	warm.close_app()
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut app := calendar_search_memory_app(home)
		calendar_search_memory_add(mut app, 2)
		assert app.events.save()
		app.key_input('\x06cafe office')
		app.handle(app.events.actions[0])!
		app.key_input('\x01Changed')
		app.save_event()
		assert !app.editing && app.events.items[0].year == 2024
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 400, 476))!)
		assert app.search_count == 1 && app.search_indices[0] == 1
		app.handle(app.events.actions[1])!
		app.delete_event()
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 400, 476))!)
		assert app.search_count == 0
		mut reopened := calendar_search_memory_app(home)
		assert reopened.events.count == 1 && reopened.events.items[0].title == 'Changed'
		reopened.close_app()
		app.close_app()
		assert C.unlink(&char(record.str)) == 0
	}
	assert C.vinix_heap_end() == 0
}
