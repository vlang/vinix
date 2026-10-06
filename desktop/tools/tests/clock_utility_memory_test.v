// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

#include "@VMODROOT/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn test_clock_named_timer_frames_names_and_lifecycle_retain_no_heap() {
	previous := desktop_language
	defer { set_desktop_language(previous) }
	mut app := ClockApp{tab: 1}
	app.refresh()
	for language in [DesktopLanguage.en, .es, .ru]! {
		set_desktop_language(language)
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 560, 376))!)
	}
	app.close_app()
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		app.tab = 1
		app.initialize_timers()
		for _ in 1 .. 4 {
			assert app.add_timer()
			app.handle('clock.timer.name')!
			app.paste_input('Timer 日本語')
			app.key_input('\x7f')
			app.key_input(' A')
			app.key_input('\xe6')
			app.key_input('\x97')
			app.key_input('\xa5')
			app.key_input('\x7f')
			app.set_timer_duration(1000)
			app.toggle_timer_at(1000)
		}
		for language in [DesktopLanguage.en, .es, .ru]! {
			set_desktop_language(language)
			app.refresh()
			for size in [ui2.rect(0, 0, 560, 376), ui2.rect(0, 0, 400, 370), ui2.rect(0, 0, 180, 96)]! {
				begin_frame_elements()
				free_tree(app.build(size)!)
			}
		}
		app.update_timer(2000)
		app.name_focus = false
		app.selected_timer = 1
		assert app.remove_timer()
		app.toggle_stopwatch_at(1000)
		for index in 1 .. 70 { app.add_lap_at(u64(1000 + index * 100)) }
		app.close_app()
		app.close_app()
	}
	assert C.vinix_heap_end() == 0
}
