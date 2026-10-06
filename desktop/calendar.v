// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// A month calendar, built into the desktop with ui2.
module main

import ui2

const calendar_action_previous = 'calendar.previous'
const calendar_action_next = 'calendar.next'
const calendar_action_today = 'calendar.today'
const calendar_action_day = 'calendar.day.'

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
const calendar_header_height = 88
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
	// The language the two labels above were written in. build rewrites them
	// after a change.
	language         DesktopLanguage
	events           CalendarEvents
	agenda_scroll    int
	editing          bool
	edit_index       int = -1
	edit_focus       int
	edit_select_all  bool
	edit_all_day     bool = true
	edit_title       []u8
	edit_time        []u8
	edit_location    []u8
	edit_pending     [4]u8
	edit_pending_len int
	status_key       string
	interchange      bool
	ics_import_path  []u8
	ics_export_path  []u8
	ics_focus        int
	ics_selected     bool
	ics_pending      [4]u8
	ics_pending_len  int
	ics_status       string = 'calendar.ics.ready'
	// The query and result indices are inline; filtering borrows event text.
	search           [128]u8
	search_len       int
	search_active    bool
	search_focus     bool
	search_selected  bool
	search_pending   [4]u8
	search_pending_len int
	search_indices   [calendar_events_limit]int
	search_count     int
	search_scroll    int
	search_visible   int = 1
	search_escape    [16]u8
	search_escape_len int
	search_escape_ms u64
}

fn open_calendar(mut desktop Desktop) !NativeApp {
	mut app := &CalendarApp{
		tz_offset: desktop.tz_offset_seconds
	}
	app.go_today()
	app.events.load(if desktop_user_home != '' { desktop_user_home } else { desktop_home })
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

// Sunday is zero, matching the clock's CivilTime.
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

// calendar_first_weekday is the weekday a week starts on where the desktop's
// language is spoken: Sunday in the United States, Monday in Russia, Spain
// and France.
fn calendar_first_weekday() int {
	return match desktop_language {
		.en { 0 }
		.ru, .es, .fr { 1 }
	}
}

// calendar_heading_month is a month's name standing on its own, as the
// heading shows it; Russian's nominative, where a date takes the genitive.
fn calendar_heading_month(month int) string {
	return match month {
		1 { tr('calendar.heading.month.jan') }
		2 { tr('calendar.heading.month.feb') }
		3 { tr('calendar.heading.month.mar') }
		4 { tr('calendar.heading.month.apr') }
		5 { tr('calendar.heading.month.may') }
		6 { tr('calendar.heading.month.jun') }
		7 { tr('calendar.heading.month.jul') }
		8 { tr('calendar.heading.month.aug') }
		9 { tr('calendar.heading.month.sep') }
		10 { tr('calendar.heading.month.oct') }
		11 { tr('calendar.heading.month.nov') }
		else { tr('calendar.heading.month.dec') }
	}
}

fn (mut a CalendarApp) refresh_labels() {
	year := a.year.str()
	next_title := tr_fill2('calendar.heading', calendar_heading_month(a.month), year)
	if a.month_title.len > 0 {
		unsafe { a.month_title.free() }
	}
	a.month_title = next_title

	next_selection := date_long_text(a.year, a.month, a.selected_day, calendar_weekday(a.year,
		a.month, a.selected_day))
	if a.selection.len > 0 {
		unsafe { a.selection.free() }
	}
	a.selection = next_selection
	unsafe { year.free() }
	a.language = desktop_language
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
	a.agenda_scroll = 0
	a.refresh_labels()
}

fn (mut a CalendarApp) change_month(delta int) {
	if (a.year <= 1 && a.month == 1 && delta < 0)
		|| (a.year >= 9999 && a.month == 12 && delta > 0) {
		return
	}
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
	a.agenda_scroll = 0
}

fn (mut a CalendarApp) build(size ui2.Rect) !ui2.Element {
	if a.language != desktop_language {
		a.refresh_labels()
	}
	width := int(size.width)
	height := int(size.height)
	if a.interchange { return a.build_interchange(size) }
	if a.editing { return a.build_event_editor(width, height) }
	if width < 360 || height < if a.search_active { 210 } else { 400 } {
		return a.build_small_calendar(width, height)
	}
	if a.search_active { return a.build_search(width, height) }
	inner := width - 2 * calendar_padding
	mut children := frame_elements(100)

	children << ui2.button(calendar_action_previous, '<', ui2.rect(f64(calendar_padding), 14, 34, 28), ui2.BoxStyle{
		bg:     calendar_button
		radius: 6
	}, ui2.TextStyle{
		color: body_text
		size:  13
		align: .center
	})
	children << ui2.label('', a.month_title, ui2.rect(f64(calendar_padding + 44), 10, f64(inner - 88), 36), ui2.TextStyle{
		color: body_heading
		size:  20
		bold:  true
		align: .center
	})
	children << ui2.button(calendar_action_next, '>', ui2.rect(f64(width - calendar_padding - 34), 14, 34, 28), ui2.BoxStyle{
		bg:     calendar_button
		radius: 6
	}, ui2.TextStyle{
		color: body_text
		size:  13
		align: .center
	})
	a.append_search_field(mut children, width)

	cell_width := if inner > 7 { inner / 7 } else { 1 }
	// Columns run from the language's first day of the week.
	first_weekday := calendar_first_weekday()
	for column in 0 .. 7 {
		children << ui2.label('', date_weekday_short((first_weekday + column) % 7), ui2.rect(f64(calendar_padding + column * cell_width), f64(calendar_header_height), f64(cell_width), f64(calendar_weekday_height)), ui2.TextStyle{
			color: body_muted
			size:  11
			bold:  true
			align: .center
		})
	}

	grid_top := calendar_header_height + calendar_weekday_height
	agenda_height := 150
	available_grid_height := height - grid_top - calendar_footer_height - calendar_padding - agenda_height
	cell_height := if available_grid_height > 6 { available_grid_height / 6 } else { 1 }
	first := (calendar_weekday(a.year, a.month, 1) - first_weekday + 7) % 7
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
			bg:          if selected {
				app_accent
			} else if today {
				calendar_today
			} else {
				app_surface
			}
			radius:      7
			transparent: !selected && !today
		}, frame_child(ui2.label('', calendar_days[day - 1], ui2.rect(0, 0, f64(cell_width - 4), f64(cell_height - 4)), ui2.TextStyle{
			color: if selected { app_on_accent } else { body_text }
			size:  13
			bold:  selected || today
			align: .center
		})))
		if a.events.has_date(a.year, a.month, day) {
			children << ui2.view('', ui2.rect(f64(x + cell_width / 2 - 2), f64(y + cell_height - 9), 4, 4), ui2.BoxStyle{
				bg:     if selected { app_on_accent } else { app_accent }
				radius: 2
			}, [])
		}
	}
	a.append_agenda(mut children, width, height - calendar_footer_height - agenda_height)

	footer_y := height - calendar_footer_height
	children << ui2.view('', ui2.rect(0, f64(footer_y), f64(width), 1), ui2.BoxStyle{
		bg: body_rule
	}, [])
	children << ui2.label('', a.selection, ui2.rect(f64(calendar_padding), f64(footer_y), f64(inner - 86), f64(calendar_footer_height)), ui2.TextStyle{
		color: body_text
		size:  12
	})
	children << ui2.button(calendar_action_today, tr('calendar.today'), ui2.rect(f64(width - calendar_padding - 72), f64(footer_y + 5), 72, 24), ui2.BoxStyle{
		bg:     calendar_button
		radius: 5
	}, ui2.TextStyle{
		color: body_text
		size:  12
		align: .center
	})

	return ui2.screen(app_surface, children)
}

fn (mut a CalendarApp) handle(event_id string) ! {
	match event_id {
		'calendar.search' { if !a.editing && !a.interchange { a.focus_search(true) } return }
		'calendar.search.clear', 'calendar.search.back' { a.clear_search() return }
		'calendar.search.previous' { a.search_scroll -= a.search_visible a.clamp_search_scroll() return }
		'calendar.search.next' { a.search_scroll += a.search_visible a.clamp_search_scroll() return }
		'calendar.ics.open' { if !a.editing { a.open_interchange() } return }
		'calendar.ics.back' { a.interchange = false a.ics_pending_len = 0 return }
		'calendar.ics.import_path' { a.ics_focus = 0 a.ics_selected = true a.ics_pending_len = 0 return }
		'calendar.ics.export_path' { a.ics_focus = 1 a.ics_selected = true a.ics_pending_len = 0 return }
		'calendar.ics.import' { if a.interchange { a.import_ics(editor_bytes_text(a.ics_import_path)) } return }
		'calendar.ics.export' { if a.interchange { a.export_ics(editor_bytes_text(a.ics_export_path)) } return }
		'calendar.event.new' {
			a.begin_event(-1)
			return
		}
		'calendar.event.save' {
			a.save_event()
			return
		}
		'calendar.event.cancel' {
			a.editing = false
			a.status_key = ''
			return
		}
		'calendar.event.delete' {
			a.delete_event()
			return
		}
		'calendar.event.title' {
			a.edit_focus = 0
			a.edit_select_all = true
			return
		}
		'calendar.event.time' {
			a.edit_focus = 1
			a.edit_select_all = true
			return
		}
		'calendar.event.location' {
			a.edit_focus = 2
			a.edit_select_all = true
			return
		}
		'calendar.event.all_day' {
			a.edit_all_day = !a.edit_all_day
			if a.edit_all_day && a.edit_focus == 1 { a.edit_focus = 2 }
			return
		}
		'calendar.agenda.previous' {
			if a.agenda_scroll > 0 { a.agenda_scroll-- }
			return
		}
		'calendar.agenda.next' {
			a.agenda_scroll++
			return
		}
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
	if event_id.starts_with('calendar.event.row.') {
		index := calendar_borrow(event_id, 'calendar.event.row.'.len, event_id.len).int()
		if index >= 0 && index < a.events.count {
			if a.search_active {
				event := a.events.items[index]
				a.year = event.year
				a.month = event.month
				a.selected_day = event.day
				a.agenda_scroll = 0
				a.refresh_labels()
			}
			a.begin_event(index)
		}
		return
	}
	if event_id.starts_with(calendar_action_day) {
		day := calendar_borrow(event_id, calendar_action_day.len, event_id.len).int()
		if day >= 1 && day <= calendar_days_in_month(a.year, a.month) {
			a.selected_day = day
			a.refresh_labels()
			a.agenda_scroll = 0
		}
	}
}
