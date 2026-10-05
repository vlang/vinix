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
	app.set_timer_duration(5000)
	app.toggle_timer_at(1000)
	assert app.timer_running
	assert app.timer_remaining(2000) == 4000
	assert app.timer_remaining(999) == 5000
	assert app.timer_remaining(~u64(0)) == 5000
	app.toggle_timer_at(2500)
	assert !app.timer_running
	assert app.timer_remaining_ms == 3500
	assert app.timer_remaining(20_000) == 3500
	app.toggle_timer_at(20_000)
	app.update_timer(23_499)
	assert app.timer_running
	app.update_timer(23_500)
	assert !app.timer_running
	assert app.timer_done
	assert app.tab == 1
	assert app.timer_remaining_ms == 0
	app.toggle_timer_at(30_000)
	assert !app.timer_done
	assert app.timer_remaining(30_000) == 5000
	app.reset_timer()
	assert !app.timer_running
	assert app.timer_remaining_ms == 5000
}

fn test_countdown_duration_is_bounded_and_cannot_change_while_running() {
	mut app := ClockApp{}
	app.set_timer_duration(0)
	assert app.timer_duration_ms == 300_000
	app.adjust_timer(-400_000)
	assert app.timer_duration_ms == 1000
	app.adjust_timer(100_000_000)
	assert app.timer_duration_ms == 86_400_000
	app.toggle_timer_at(1000)
	app.adjust_timer(-60_000)
	app.set_timer_duration(5000)
	assert app.timer_duration_ms == 86_400_000
	assert app.next_poll_ms() == clock_running_poll_ms
}

fn test_countdown_formats_remaining_fraction_as_next_whole_second() {
	assert clock_timer_text(0) == '00:00:00'
	assert clock_timer_text(1) == '00:00:01'
	assert clock_timer_text(60_001) == '00:01:01'
	assert clock_timer_text(86_400_000) == '24:00:00'
}

fn clock_utility_element(root ui2.Element, id string) ?ui2.Element {
	if root.id == id { return root }
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
