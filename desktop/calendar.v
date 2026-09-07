// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// A month calendar, built into the desktop with ui2.
module main

import ui2

const calendar_action_previous = 'calendar.previous'
const calendar_action_next = 'calendar.next'
const calendar_action_today = 'calendar.today'
const calendar_action_day = 'calendar.day.'

const calendar_weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
const calendar_days = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14',
	'15', '16', '17', '18', '19', '20', '21', '22', '23', '24', '25', '26', '27', '28', '29', '30',
	'31']
const calendar_day_actions = ['calendar.day.1', 'calendar.day.2', 'calendar.day.3', 'calendar.day.4',
	'calendar.day.5', 'calendar.day.6', 'calendar.day.7', 'calendar.day.8', 'calendar.day.9',
	'calendar.day.10', 'calendar.day.11', 'calendar.day.12', 'calendar.day.13', 'calendar.day.14',
	'calendar.day.15', 'calendar.day.16', 'calendar.day.17', 'calendar.day.18', 'calendar.day.19',
	'calendar.day.20', 'calendar.day.21', 'calendar.day.22', 'calendar.day.23', 'calendar.day.24',
	'calendar.day.25', 'calendar.day.26', 'calendar.day.27', 'calendar.day.28', 'calendar.day.29',
	'calendar.day.30', 'calendar.day.31']

const calendar_padding = 18
const calendar_header_height = 54
const calendar_weekday_height = 28
const calendar_footer_height = 34

struct CalendarApp {
mut:
	year         int
	month        int
	selected_day int
	today_year   int
	today_month  int
	today_day    int
	tz_offset    i64
	month_title  string
	selection    string
}

fn open_calendar(mut desktop Desktop) !NativeApp {
	mut app := &CalendarApp{
		tz_offset: desktop.tz_offset_seconds
	}
	app.go_today()
	return app
}

fn calendar_is_leap_year(year int) bool {
	return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

fn calendar_days_in_month(year int, month int) int {
	return match month {
		2 {
			if calendar_is_leap_year(year) { 29 } else { 28 }
		}
		4, 6, 9, 11 { 30 }
		else { 31 }
	}
}

// Sunday is zero, matching the clock's CivilTime and the column order above.
// This is the civil-to-days half of the same Gregorian algorithm clock.v uses.
fn calendar_weekday(year int, month int, day int) int {
	mut adjusted_year := year
	if month <= 2 {
		adjusted_year--
	}
	era := adjusted_year / 400
	year_of_era := adjusted_year - era * 400
	month_prime := month + if month > 2 { -3 } else { 9 }
	day_of_year := (153 * month_prime + 2) / 5 + day - 1
	day_of_era := year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year
	days := era * 146097 + day_of_era - 719468
	return ((days % 7) + 11) % 7
}

fn (mut a CalendarApp) refresh_labels() {
	year := a.year.str()
	next_title := '${month_names[a.month - 1]} ${year}'
	if a.month_title.len > 0 {
		unsafe { a.month_title.free() }
	}
	a.month_title = next_title

	day := a.selected_day.str()
	next_selection := '${weekday_names[calendar_weekday(a.year, a.month, a.selected_day)]}, ${month_names[a.month - 1]} ${day}, ${year}'
	if a.selection.len > 0 {
		unsafe { a.selection.free() }
	}
	a.selection = next_selection
	unsafe {
		day.free()
		year.free()
	}
}

fn (mut a CalendarApp) go_today() {
	seconds, _ := desktop_realtime()
	civil := if seconds >= 0 {
		civil_from_epoch(seconds + a.tz_offset)
	} else {
		CivilTime{ year: 1970, month: 1, day: 1, weekday: 4 }
	}
	a.today_year = civil.year
	a.today_month = civil.month
	a.today_day = civil.day
	a.year = civil.year
	a.month = civil.month
	a.selected_day = civil.day
	a.refresh_labels()
}

fn (mut a CalendarApp) change_month(delta int) {
	a.month += delta
	for a.month < 1 {
		a.month += 12
		a.year--
	}
	for a.month > 12 {
		a.month -= 12
		a.year++
	}
	last := calendar_days_in_month(a.year, a.month)
	if a.selected_day > last {
		a.selected_day = last
	}
	a.refresh_labels()
}

fn (mut a CalendarApp) build(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)
	inner := width - 2 * calendar_padding
	mut children := frame_elements(45)

	children << ui2.button(calendar_action_previous, '<', ui2.rect(f64(calendar_padding), 14, 34, 28), ui2.BoxStyle{
		bg: calendar_button
		radius: 6
	}, ui2.TextStyle{
		color: body_text
		size: 13
		align: .center
	})
	children << ui2.label('', a.month_title, ui2.rect(f64(calendar_padding + 44), 10, f64(inner - 88), 36), ui2.TextStyle{
		color: body_heading
		size: 20
		bold: true
		align: .center
	})
	children << ui2.button(calendar_action_next, '>', ui2.rect(f64(width - calendar_padding - 34), 14, 34, 28), ui2.BoxStyle{
		bg: calendar_button
		radius: 6
	}, ui2.TextStyle{
		color: body_text
		size: 13
		align: .center
	})

	cell_width := if inner > 7 { inner / 7 } else { 1 }
	for column, weekday in calendar_weekdays {
		children << ui2.label('', weekday, ui2.rect(f64(calendar_padding + column * cell_width), f64(calendar_header_height), f64(cell_width), f64(calendar_weekday_height)), ui2.TextStyle{
			color: body_muted
			size: 11
			bold: true
			align: .center
		})
	}

	grid_top := calendar_header_height + calendar_weekday_height
	available_grid_height := height - grid_top - calendar_footer_height - calendar_padding
	cell_height := if available_grid_height > 6 { available_grid_height / 6 } else { 1 }
	first := calendar_weekday(a.year, a.month, 1)
	days := calendar_days_in_month(a.year, a.month)
	for day := 1; day <= days; day++ {
		cell := first + day - 1
		column := cell % 7
		row := cell / 7
		x := calendar_padding + column * cell_width
		y := grid_top + row * cell_height
		selected := day == a.selected_day
		today := a.year == a.today_year && a.month == a.today_month && day == a.today_day
		children << ui2.clickable_view(calendar_day_actions[day - 1], ui2.rect(f64(x + 2), f64(y + 2), f64(cell_width - 4), f64(cell_height - 4)), ui2.BoxStyle{
			bg: if selected {
				app_accent
			} else if today { calendar_today } else { app_surface }
			radius: 7
			transparent: !selected && !today
		}, frame_child(ui2.label('', calendar_days[day - 1], ui2.rect(0, 0, f64(cell_width - 4), f64(cell_height - 4)), ui2.TextStyle{
			color: if selected { app_on_accent } else { body_text }
			size: 13
			bold: selected || today
			align: .center
		})))
	}

	footer_y := height - calendar_footer_height
	children << ui2.view('', ui2.rect(0, f64(footer_y), f64(width), 1), ui2.BoxStyle{
		bg: body_rule
	}, [])
	children << ui2.label('', a.selection, ui2.rect(f64(calendar_padding), f64(footer_y), f64(inner - 86), f64(calendar_footer_height)), ui2.TextStyle{
		color: body_text
		size: 12
	})
	children << ui2.button(calendar_action_today, 'Today', ui2.rect(f64(width - calendar_padding - 72), f64(footer_y + 5), 72, 24), ui2.BoxStyle{
		bg: calendar_button
		radius: 5
	}, ui2.TextStyle{
		color: body_text
		size: 12
		align: .center
	})

	return ui2.screen(app_surface, children)
}

fn (mut a CalendarApp) handle(event_id string) ! {
	match event_id {
		calendar_action_previous {
			a.change_month(-1)
			return
		}
		calendar_action_next {
			a.change_month(1)
			return
		}
		calendar_action_today {
			a.go_today()
			return
		}
		else {}
	}
	if event_id.starts_with(calendar_action_day) {
		day := event_id[calendar_action_day.len..].int()
		if day >= 1 && day <= calendar_days_in_month(a.year, a.month) {
			a.selected_day = day
			a.refresh_labels()
		}
	}
}
