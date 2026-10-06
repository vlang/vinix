// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn test_stopwatch_laps_include_splits_and_preserve_elapsed_across_pause() {
	mut app := ClockApp{}
	defer { app.close_app() }
	app.toggle_stopwatch_at(1000)
	app.add_lap_at(2500)
	assert app.lap_count == 1
	assert app.last_lap_ms == 1500
	assert app.lap_text[0] == '1    00:00:01.5    00:00:01.5'
	app.toggle_stopwatch_at(3000)
	app.add_lap_at(4000)
	assert app.lap_count == 1
	app.toggle_stopwatch_at(10_000)
	app.add_lap_at(10_500)
	assert app.lap_text[1] == '2    00:00:01.0    00:00:02.5'
	assert app.elapsed(10_600) == 2600
	app.clear_laps()
	assert app.lap_count == 0
	assert app.last_lap_ms == 0
}

fn test_stopwatch_lap_history_is_bounded_and_rejects_bad_clocks() {
	mut app := ClockApp{}
	defer { app.close_app() }
	app.toggle_stopwatch_at(1000)
	app.add_lap_at(~u64(0))
	app.add_lap_at(999)
	assert app.lap_count == 0
	for index in 1 .. 101 { app.add_lap_at(u64(1000 + index * 100)) }
	assert app.lap_count == clock_lap_limit
	assert app.lap_number == 100
	assert app.lap_text[clock_lap_limit - 1] == '100    00:00:00.1    00:00:10.0'
}

fn test_countdown_uses_monotonic_time_pauses_resumes_and_expires() {
	mut app := ClockApp{}
	defer { app.close_app() }
	app.set_timer_duration(5000)
	app.toggle_timer_at(1000)
	assert app.timers[app.selected_timer].running
	assert app.timer_remaining(2000) == 4000
	assert app.timer_remaining(999) == 5000
	assert app.timer_remaining(~u64(0)) == 5000
	app.toggle_timer_at(2500)
	assert !app.timers[app.selected_timer].running
	assert app.timers[app.selected_timer].remaining_ms == 3500
	assert app.timer_remaining(20_000) == 3500
	app.toggle_timer_at(20_000)
	app.update_timer(23_499)
	assert app.timers[app.selected_timer].running
	app.update_timer(23_500)
	assert !app.timers[app.selected_timer].running
	assert app.timers[app.selected_timer].done
	assert app.tab == 1
	assert app.timers[app.selected_timer].remaining_ms == 0
	app.toggle_timer_at(30_000)
	assert !app.timers[app.selected_timer].done
	assert app.timer_remaining(30_000) == 5000
	app.reset_timer()
	assert !app.timers[app.selected_timer].running
	assert app.timers[app.selected_timer].remaining_ms == 5000
}

fn test_countdown_duration_is_bounded_and_cannot_change_while_running() {
	mut app := ClockApp{}
	defer { app.close_app() }
	app.set_timer_duration(0)
	assert app.timers[app.selected_timer].duration_ms == 300_000
	app.adjust_timer(-400_000)
	assert app.timers[app.selected_timer].duration_ms == 1000
	app.adjust_timer(100_000_000)
	assert app.timers[app.selected_timer].duration_ms == 86_400_000
	app.toggle_timer_at(1000)
	app.adjust_timer(-60_000)
	app.set_timer_duration(5000)
	assert app.timers[app.selected_timer].duration_ms == 86_400_000
	assert app.next_poll_ms() == clock_running_poll_ms
}

fn test_countdown_formats_remaining_fraction_as_next_whole_second() {
	values := [u64(0), 1, 60_001, 86_400_000]!
	expected := ['00:00:00', '00:00:01', '00:01:01', '24:00:00']!
	for index, value in values {
		text := clock_timer_text(value)
		assert text == expected[index]
		unsafe { text.free() }
	}
}

fn clock_utility_element(root ui2.Element, id string) ?ui2.Element {
	if root.id == id || root.action_id == id { return root }
	for child in root.children {
		found := clock_utility_element(child, id) or { continue }
		return found
	}
	return none
}

fn test_clock_timer_and_lap_controls_fit_the_installed_window() {
	mut app := ClockApp{}
	defer { app.close_app() }
	app.refresh()
	stopwatch := app.build(ui2.rect(0, 0, 560, 376)) or { panic(err) }
	assert clock_utility_element(stopwatch, clock_action_lap) != none
	assert clock_utility_element(stopwatch, 'clock.tab.timer') != none
	free_tree(stopwatch)
	app.handle('clock.tab.timer') or { panic(err) }
	timer := app.build(ui2.rect(0, 0, 560, 376)) or { panic(err) }
	start := clock_utility_element(timer, 'clock.timer.toggle') or { panic('missing start') }
	assert start.frame.y + start.frame.height <= 376
	assert clock_utility_element(timer, 'clock.timer.preset.15') != none
	free_tree(timer)
}

fn test_named_timers_run_pause_reset_and_expire_independently() {
	mut app := ClockApp{}
	defer { app.close_app() }
	app.set_timer_duration(5000)
	app.toggle_timer_at(1000)
	assert app.add_timer()
	app.set_timer_duration(10_000)
	app.toggle_timer_at(1000)
	app.selected_timer = 0
	app.toggle_timer_at(2000)
	assert app.timers[0].remaining_ms == 4000
	assert app.timers[1].remaining(3000) == 8000
	assert app.next_poll_ms() == clock_running_poll_ms
	app.selected_timer = 1
	assert !app.remove_timer()
	app.reset_timer()
	assert app.timers[0].remaining_ms == 4000 && !app.timers[0].running
	assert app.timers[1].remaining_ms == 10_000 && !app.timers[1].running
	app.toggle_timer_at(3000)
	app.selected_timer = 0
	app.toggle_timer_at(3000)
	app.update_timer(7000)
	assert app.timers[0].done && !app.timers[0].running
	assert app.timers[1].running && app.timers[1].remaining(7000) == 6000
	app.update_timer(13_000)
	assert app.timers[1].done && !app.any_timer_running()
}

fn test_named_timer_capacity_and_removal_preserve_other_slots() {
	mut app := ClockApp{tab: 1}
	defer { app.close_app() }
	app.initialize_timers()
	assert !app.remove_timer()
	for index in 1 .. clock_timer_limit { assert app.add_timer() }
	assert !app.add_timer()
	assert app.timer_count == 4 && app.selected_timer == 3
	app.set_timer_duration(7000)
	app.name_focus = true
	app.paste_input('last timer')
	app.toggle_timer_at(1000)
	app.selected_timer = 1
	assert app.remove_timer()
	assert app.timer_count == 3
	assert app.timer_name(2) == 'last timer'
	assert app.timers[2].remaining(2000) == 6000 && app.timers[2].running
	assert !app.timers[3].running && app.timers[3].name_len == 0
	app.selected_timer = 2
	app.toggle_timer_at(2500)
	assert app.remove_timer()
	assert app.selected_timer == 1 && app.timer_count == 2
}

fn test_timer_names_accept_atomic_utf8_paste_and_whole_character_backspace() {
	mut app := ClockApp{tab: 1}
	defer { app.close_app() }
	app.handle('clock.timer.name')!
	app.paste_input('Tea 日本語')
	assert app.timer_name(0) == 'Tea 日本語'
	app.key_input('\x01')
	app.paste_input('bad\nname')
	assert app.timer_name(0) == 'Tea 日本語' && app.name_selected
	app.paste_input('xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx')
	assert app.timer_name(0) == 'Tea 日本語' && app.name_selected
	invalid := [u8(0xf0), 0x80, 0x80, 0x80]!
	app.paste_input(unsafe { tos(&invalid[0], 4) })
	assert app.timer_name(0) == 'Tea 日本語' && app.name_selected
	app.paste_input('Ж')
	assert app.timer_name(0) == 'Ж' && !app.name_selected
	app.key_input('\x7f')
	assert app.timer_name(0) == ''
	app.key_input('\xe6')
	app.key_input('\x97')
	assert app.timer_name(0) == ''
	app.key_input('\xa5')
	assert app.timer_name(0) == '日'
	app.key_input('\x1b[D')
	assert app.timer_name(0) == '日'
	app.key_input('\r')
	app.paste_input('ignored')
	assert app.timer_name(0) == '日' && !app.name_focus
}

fn test_hidden_timer_expiry_does_not_redirect_a_name_edit_or_toggle() {
	mut app := ClockApp{tab: 1}
	defer { app.close_app() }
	app.set_timer_duration(1000)
	app.toggle_timer_at(1000)
	assert app.add_timer()
	app.name_focus = true
	app.paste_input('second')
	app.update_timer(2000)
	assert app.timers[0].done && app.selected_timer == 1 && app.name_focus
	app.paste_input(' timer')
	assert app.timer_name(1) == 'second timer'
	app.selected_timer = 0
	app.toggle_timer_at(3000)
	app.selected_timer = 1
	app.name_focus = false
	app.toggle_timer_at(4000)
	assert app.selected_timer == 1 && app.timers[1].running && app.timers[0].done
	app.update_timer(~u64(0))
	app.update_timer(3999)
	assert app.timers[1].running && app.timers[1].remaining_ms == 300_000
}

fn clock_assert_inside(element ui2.Element, width f64, height f64) {
	assert element.frame.x >= 0 && element.frame.y >= 0
	assert element.frame.x + element.frame.width <= width
	assert element.frame.y + element.frame.height <= height
	for child in element.children { clock_assert_inside(child, element.frame.width, element.frame.height) }
}

fn test_all_timer_controls_and_translated_labels_fit_and_show_real_enabled_state() {
	previous := desktop_language
	defer { set_desktop_language(previous) }
	mut app := ClockApp{tab: 1}
	defer { app.close_app() }
	app.refresh()
	for _ in 1 .. 4 { assert app.add_timer() }
	for language in [DesktopLanguage.en, .es, .ru]! {
		set_desktop_language(language)
		for size in [ui2.rect(0, 0, 560, 376), ui2.rect(0, 0, 400, 370), ui2.rect(0, 0, 180, 96)]! {
			begin_frame_elements()
			tree := app.build(size)!
			for child in tree.children { clock_assert_inside(child, size.width, size.height) }
			if size.width >= 400 {
				add := clock_utility_element(tree, 'clock.timer.add') or { panic('missing Add') }
				assert !add.enabled
				assert clock_utility_element(tree, 'clock.timer.select.3') != none
				assert clock_utility_element(tree, 'clock.timer.name') != none
			}
			free_tree(tree)
		}
	}
}
