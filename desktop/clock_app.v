// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// A clock and stopwatch utility with enough room to be read across a desk.
module main

import ui2

const clock_action_toggle = 'clock.stopwatch.toggle'
const clock_action_reset = 'clock.stopwatch.reset'
const clock_action_lap = 'clock.stopwatch.lap'
const clock_lap_limit = 64
const clock_idle_poll_ms = u64(1000)
const clock_running_poll_ms = u64(100)

struct ClockApp {
mut:
	tz_offset       i64
	time_text       string
	date_text       string
	stopwatch_text  string
	running         bool
	started_ms      u64
	accumulated_ms  u64
	last_refresh_ms u64
	// The wall-clock second the time on show was read at.
	shown_seconds i64 = -1
	// The language date_text was written in. build rewrites it after a
	// change rather than waiting for the next second.
	language           DesktopLanguage
	tab                int
	lap_count          int
	lap_scroll         int
	lap_number         int
	last_lap_ms        u64
	lap_text           [clock_lap_limit]string
	timer_text         string
	timers             [clock_timer_limit]ClockTimer
	timer_count        int
	selected_timer     int
	name_focus         bool
	name_selected      bool
	name_pending       [4]u8
	name_pending_len   int
}

fn open_clock(mut desktop Desktop) !NativeApp {
	mut app := &ClockApp{
		tz_offset: desktop.tz_offset_seconds
	}
	app.refresh()
	return app
}

fn clock_stopwatch_text(milliseconds u64) string {
	tenths := milliseconds / 100
	hours := tenths / 36000
	minutes := (tenths / 600) % 60
	seconds := (tenths / 10) % 60
	fraction := tenths % 10
	hour_text := pad2(int(hours))
	minute_text := pad2(int(minutes))
	second_text := pad2(int(seconds))
	fraction_text := fraction.str()
	result := '${hour_text}:${minute_text}:${second_text}.${fraction_text}'
	unsafe {
		hour_text.free()
		minute_text.free()
		second_text.free()
		fraction_text.free()
	}
	return result
}

fn (a &ClockApp) elapsed(now u64) u64 {
	if !a.running || now == ~u64(0) || now < a.started_ms {
		return a.accumulated_ms
	}
	return a.accumulated_ms + now - a.started_ms
}

fn clock_replace_text(old string, next string) string {
	if old.len > 0 {
		unsafe { old.free() }
	}
	return next
}

fn (mut a ClockApp) refresh() {
	a.initialize_timers()
	seconds, _ := desktop_realtime()
	if seconds < 0 {
		a.time_text = clock_replace_text(a.time_text, '--:--:--'.clone())
		a.date_text = clock_replace_text(a.date_text, tr('clock.unavailable').clone())
	} else {
		civil := civil_from_epoch(seconds + a.tz_offset)
		hour := pad2(civil.hour)
		minute := pad2(civil.minute)
		second := pad2(civil.second)
		next_time := '${hour}:${minute}:${second}'
		unsafe {
			hour.free()
			minute.free()
			second.free()
		}
		next_date := date_long_text(civil.year, civil.month, civil.day, civil.weekday)
		a.time_text = clock_replace_text(a.time_text, next_time)
		a.date_text = clock_replace_text(a.date_text, next_date)
	}
	a.shown_seconds = seconds
	a.language = desktop_language
	now := desktop_monotonic_ms()
	a.stopwatch_text = clock_replace_text(a.stopwatch_text, clock_stopwatch_text(a.elapsed(now)))
	a.update_timer(now)
	a.timer_text = clock_replace_text(a.timer_text, clock_timer_text(a.timer_remaining(now)))
	a.last_refresh_ms = now
}

fn (mut a ClockApp) poll() bool {
	now := desktop_monotonic_ms()
	if now == ~u64(0) {
		return false
	}
	if !a.running && !a.any_timer_running() {
		// Only the seconds can have changed, so there is nothing to redraw
		// until the wall clock reaches the next one.
		seconds, _ := desktop_realtime()
		if seconds == a.shown_seconds {
			return false
		}
		a.refresh()
		return true
	}
	if a.last_refresh_ms != ~u64(0) && now >= a.last_refresh_ms
		&& now - a.last_refresh_ms < clock_running_poll_ms {
		return false
	}
	a.refresh()
	return true
}

// next_poll_ms asks for the stopwatch's tenths while it runs, and otherwise
// for the moment the next wall-clock second begins, so the time turns over
// on the second rather than up to one poll interval after it.
fn (a &ClockApp) next_poll_ms() u64 {
	if a.running || a.any_timer_running() {
		return clock_running_poll_ms
	}
	_, nanoseconds := desktop_realtime()
	if nanoseconds < 0 || nanoseconds >= 1_000_000_000 {
		return clock_idle_poll_ms
	}
	return u64(1_000_000_000 - nanoseconds) / 1_000_000 + 1
}

fn (mut a ClockApp) toggle_stopwatch() {
	now := desktop_monotonic_ms()
	a.toggle_stopwatch_at(now)
	a.refresh()
}

fn (mut a ClockApp) toggle_stopwatch_at(now u64) {
	if now == ~u64(0) {
		return
	}
	if a.running {
		if now >= a.started_ms {
			a.accumulated_ms += now - a.started_ms
		}
		a.running = false
	} else {
		a.started_ms = now
		a.running = true
	}
}

fn (mut a ClockApp) reset_stopwatch() {
	a.accumulated_ms = 0
	a.clear_laps()
	if a.running {
		now := desktop_monotonic_ms()
		if now != ~u64(0) {
			a.started_ms = now
		}
	}
	a.refresh()
}

fn (mut a ClockApp) build(size ui2.Rect) !ui2.Element {
	a.initialize_timers()
	if a.language != desktop_language {
		a.refresh()
	}
	width := int(size.width)
	height := int(size.height)
	pad := 24
	inner := width - 2 * pad
	mut children := frame_elements(24)
	if width < 400 || height < 370 {
		children << ui2.label('', tr('clock.enlarge'), ui2.rect(12, 12,
			f64(if width > 24 { width - 24 } else { 0 }),
			f64(if height > 24 { height - 24 } else { 0 })),
			ui2.TextStyle{color: body_muted, size: 12, lines: 3})
		return ui2.screen(app_surface, children)
	}

	children << ui2.label('', a.time_text, ui2.rect(f64(pad), 12, f64(inner), 60), ui2.TextStyle{
		color: body_heading
		size:  32
		bold:  true
		align: .center
	})
	children << ui2.label('', a.date_text, ui2.rect(f64(pad), 74, f64(inner), 26), ui2.TextStyle{
		color: body_muted
		size:  13
		align: .center
	})
	children << clock_control('clock.tab.stopwatch', tr('clock.stopwatch'), pad, 110, inner / 2 - 5, a.tab == 0)
	children << clock_control('clock.tab.timer', tr('clock.timer'), width / 2 + 5, 110, inner / 2 - 5, a.tab == 1)
	if a.tab == 1 {
		a.append_timer(mut children, width)
		return ui2.screen(app_surface, children)
	}

	stopwatch_top := 154
	children << ui2.label('', tr('clock.stopwatch'), ui2.rect(f64(pad), f64(stopwatch_top), f64(inner), 20), ui2.TextStyle{
		color: body_muted
		size:  11
		bold:  true
		align: .center
	})
	children << ui2.label('', a.stopwatch_text, ui2.rect(f64(pad), f64(stopwatch_top + 24), f64(inner), 52), ui2.TextStyle{
		color:       clock_stopwatch
		font_family: 'mono'
		size:        24
		bold:        true
		align:       .center
	})

	button_width := if inner >= 330 { 100 } else { (inner - 24) / 3 }
	button_gap := 12
	buttons_width := 3 * button_width + 2 * button_gap
	button_x := (width - buttons_width) / 2
	button_y := stopwatch_top + 82
	children << ui2.button(clock_action_toggle, if a.running {
		tr('clock.stop')
	} else {
		tr('clock.start')
	}, ui2.rect(f64(button_x), f64(button_y), f64(button_width), 32), ui2.BoxStyle{
		bg:     if a.running { clock_stop } else { app_accent }
		radius: 7
	}, ui2.TextStyle{
		color: app_on_accent
		size:  13
		bold:  true
		align: .center
	})
	children << ui2.button(clock_action_reset, tr('clock.reset'), ui2.rect(f64(button_x + button_width + button_gap), f64(button_y), f64(button_width), 32), ui2.BoxStyle{
		bg:     clock_button
		radius: 7
	}, ui2.TextStyle{
		color: body_text
		size:  13
		align: .center
	})
	children << clock_control(clock_action_lap, tr('clock.lap'), button_x + 2 * (button_width + button_gap), button_y, button_width, false)
	if a.lap_count > 0 {
		children << ui2.label('', tr('clock.laps'), ui2.rect(f64(pad), f64(button_y + 38), f64(inner - 60), 20), ui2.TextStyle{ color: body_muted, size: 11 })
		if a.lap_count > 3 {
			children << clock_control('clock.laps.older', '<', width - pad - 52, button_y + 34, 24, false)
			children << clock_control('clock.laps.newer', '>', width - pad - 24, button_y + 34, 24, false)
		}
		mut row := 0
		for index := a.lap_count - 1 - a.lap_scroll; index >= 0 && row < 3; index-- {
			y := button_y + 60 + row * 22
			if y + 22 > height { break }
			children << ui2.label('', a.lap_text[index], ui2.rect(f64(pad), f64(y), f64(inner), 22), ui2.TextStyle{ color: body_text, font_family: 'mono', size: 12, align: .center })
			row++
		}
	}

	return ui2.screen(app_surface, children)
}

fn (mut a ClockApp) handle(event_id string) ! {
	a.initialize_timers()
	if event_id == 'clock.timer.name' {
		a.name_focus = true
		a.name_selected = true
		a.name_pending_len = 0
		return
	}
	a.name_focus = false
	a.name_pending_len = 0
	for index, action in clock_timer_actions {
		if event_id == action && index < a.timer_count {
			a.selected_timer = index
			a.refresh()
			return
		}
	}
	match event_id {
		'clock.tab.stopwatch' { a.tab = 0 }
		'clock.tab.timer' { a.tab = 1 }
		'clock.timer.add' {
			if a.add_timer() {
				a.name_focus = true
				a.name_selected = true
			}
			a.refresh()
		}
		'clock.timer.remove' { a.remove_timer(); a.refresh() }
		clock_action_toggle { a.toggle_stopwatch() }
		clock_action_reset { a.reset_stopwatch() }
		clock_action_lap { a.add_lap_at(desktop_monotonic_ms()) }
		'clock.laps.older' {
			if a.lap_scroll < a.lap_count - 3 { a.lap_scroll++ }
		}
		'clock.laps.newer' {
			if a.lap_scroll > 0 { a.lap_scroll-- }
		}
		'clock.timer.toggle' {
			a.toggle_timer_at(desktop_monotonic_ms())
			a.refresh()
		}
		'clock.timer.reset' {
			a.reset_timer()
			a.refresh()
		}
		'clock.timer.less' {
			a.adjust_timer(-60_000)
			a.refresh()
		}
		'clock.timer.more' {
			a.adjust_timer(60_000)
			a.refresh()
		}
		'clock.timer.preset.1' {
			a.set_timer_duration(60_000)
			a.refresh()
		}
		'clock.timer.preset.5' {
			a.set_timer_duration(300_000)
			a.refresh()
		}
		'clock.timer.preset.15' {
			a.set_timer_duration(900_000)
			a.refresh()
		}
		else {}
	}
}

fn clock_timer_text(milliseconds u64) string {
	seconds := (milliseconds + 999) / 1000
	hour := pad2(int(seconds / 3600))
	minute := pad2(int(seconds / 60 % 60))
	second := pad2(int(seconds % 60))
	result := '${hour}:${minute}:${second}'
	unsafe {
		hour.free()
		minute.free()
		second.free()
	}
	return result
}

fn (mut a ClockApp) clear_laps() {
	for index in 0 .. a.lap_count {
		unsafe { a.lap_text[index].free() }
		a.lap_text[index] = ''
	}
	a.lap_count = 0
	a.lap_scroll = 0
	a.lap_number = 0
	a.last_lap_ms = 0
}

fn (mut a ClockApp) add_lap_at(now u64) {
	if !a.running || now == ~u64(0) || now < a.started_ms { return }
	elapsed := a.elapsed(now)
	if elapsed < a.last_lap_ms { return }
	if a.lap_count == clock_lap_limit {
		unsafe { a.lap_text[0].free() }
		for index in 1 .. clock_lap_limit { a.lap_text[index - 1] = a.lap_text[index] }
		a.lap_count--
	}
	a.lap_number++
	number := a.lap_number.str()
	split := clock_stopwatch_text(elapsed - a.last_lap_ms)
	total := clock_stopwatch_text(elapsed)
	a.lap_text[a.lap_count] = '${number}    ${split}    ${total}'
	unsafe {
		number.free()
		split.free()
		total.free()
	}
	a.lap_count++
	a.lap_scroll = 0
	a.last_lap_ms = elapsed
}

fn clock_control(action string, text string, x int, y int, width int, active bool) ui2.Element {
	return ui2.button(action, text, ui2.rect(f64(x), f64(y), f64(width), 30), ui2.BoxStyle{
		bg:     if active { app_accent } else { clock_button }
		radius: 6
	}, ui2.TextStyle{ color: if active { app_on_accent } else { body_text }, size: 12, align: .center })
}

fn (mut a ClockApp) close_app() {
	a.clear_laps()
	unsafe {
		a.time_text.free()
		a.date_text.free()
		a.stopwatch_text.free()
		a.timer_text.free()
	}
	a.time_text = ''
	a.date_text = ''
	a.stopwatch_text = ''
	a.timer_text = ''
	a.timers = [clock_timer_limit]ClockTimer{}
	a.timer_count = 0
	a.selected_timer = 0
	a.name_focus = false
	a.name_pending_len = 0
	a.running = false
}
