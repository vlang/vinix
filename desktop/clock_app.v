// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// A clock and stopwatch utility with enough room to be read across a desk.
module main

import ui2

const clock_action_toggle = 'clock.stopwatch.toggle'
const clock_action_reset = 'clock.stopwatch.reset'
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
	seconds, _ := desktop_realtime()
	if seconds < 0 {
		a.time_text = clock_replace_text(a.time_text, '--:--:--'.clone())
		a.date_text = clock_replace_text(a.date_text, 'Clock unavailable'.clone())
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
		day := civil.day.str()
		year := civil.year.str()
		next_date := '${weekday_names[civil.weekday]}, ${month_names[civil.month - 1]} ${day}, ${year}'
		unsafe {
			day.free()
			year.free()
		}
		a.time_text = clock_replace_text(a.time_text, next_time)
		a.date_text = clock_replace_text(a.date_text, next_date)
	}
	now := desktop_monotonic_ms()
	a.stopwatch_text = clock_replace_text(a.stopwatch_text, clock_stopwatch_text(a.elapsed(now)))
	a.last_refresh_ms = now
}

fn (mut a ClockApp) poll() bool {
	now := desktop_monotonic_ms()
	if now == ~u64(0) {
		return false
	}
	interval := if a.running { clock_running_poll_ms } else { clock_idle_poll_ms }
	if a.last_refresh_ms != ~u64(0) && now >= a.last_refresh_ms
		&& now - a.last_refresh_ms < interval {
		return false
	}
	a.refresh()
	return true
}

fn (mut a ClockApp) toggle_stopwatch() {
	now := desktop_monotonic_ms()
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
	a.refresh()
}

fn (mut a ClockApp) reset_stopwatch() {
	a.accumulated_ms = 0
	if a.running {
		now := desktop_monotonic_ms()
		if now != ~u64(0) {
			a.started_ms = now
		}
	}
	a.refresh()
}

fn (mut a ClockApp) build(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)
	pad := 24
	inner := width - 2 * pad
	mut children := frame_elements(8)

	children << ui2.label('', a.time_text, ui2.rect(f64(pad), 28, f64(inner), 72), ui2.TextStyle{
		color: body_heading
		size: 32
		bold: true
		align: .center
	})
	children << ui2.label('', a.date_text, ui2.rect(f64(pad), 94, f64(inner), 26), ui2.TextStyle{
		color: body_muted
		size: 13
		align: .center
	})
	children << ui2.view('', ui2.rect(f64(pad), 132, f64(inner), 1), ui2.BoxStyle{
		bg: body_rule
	}, [])

	stopwatch_top := 154
	children << ui2.label('', 'STOPWATCH', ui2.rect(f64(pad), f64(stopwatch_top), f64(inner), 20), ui2.TextStyle{
		color: body_muted
		size: 11
		bold: true
		align: .center
	})
	children << ui2.label('', a.stopwatch_text, ui2.rect(f64(pad), f64(stopwatch_top + 24), f64(inner), 52), ui2.TextStyle{
		color: clock_stopwatch
		font_family: 'mono'
		size: 24
		bold: true
		align: .center
	})

	button_width := 112
	button_gap := 12
	buttons_width := 2 * button_width + button_gap
	button_x := (width - buttons_width) / 2
	button_y := if height - 54 > stopwatch_top + 78 { height - 54 } else { stopwatch_top + 82 }
	children << ui2.button(clock_action_toggle, if a.running { 'Stop' } else { 'Start' }, ui2.rect(f64(button_x), f64(button_y), f64(button_width), 32), ui2.BoxStyle{
		bg: if a.running { clock_stop } else { app_accent }
		radius: 7
	}, ui2.TextStyle{
		color: app_on_accent
		size: 13
		bold: true
		align: .center
	})
	children << ui2.button(clock_action_reset, 'Reset', ui2.rect(f64(button_x + button_width + button_gap), f64(button_y), f64(button_width), 32), ui2.BoxStyle{
		bg: clock_button
		radius: 7
	}, ui2.TextStyle{
		color: body_text
		size: 13
		align: .center
	})

	return ui2.screen(app_surface, children)
}

fn (mut a ClockApp) handle(event_id string) ! {
	match event_id {
		clock_action_toggle { a.toggle_stopwatch() }
		clock_action_reset { a.reset_stopwatch() }
		else {}
	}
}
