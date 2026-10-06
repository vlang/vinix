// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

const calendar_events_filename = '.vinix-calendar-events'
const calendar_events_limit = 128
const calendar_events_max_bytes = 65536
const calendar_event_title_limit = 160
const calendar_event_location_limit = 128

struct CalendarEvent {
mut:
	year  int
	month int
	day   int
	// -1 is an all-day event, otherwise minutes since local midnight.
	minutes  int = -1
	title    string
	location string
}

struct CalendarEvents {
mut:
	items         [calendar_events_limit]CalendarEvent
	count         int
	home          string
	record        string
	read_failed   bool
	save_conflict bool
	actions       [calendar_events_limit]string
}

fn calendar_borrow(record string, start int, end int) string {
	if end <= start { return '' }
	return unsafe { tos(record.str + start, end - start) }
}

fn calendar_integer(text string) ?int {
	if text.len == 0 || text.len > 5 { return none }
	mut value := 0
	for byte in text {
		if byte < `0` || byte > `9` { return none }
		value = value * 10 + int(byte - `0`)
	}
	return value
}

fn calendar_clean_field(text string, maximum int) bool {
	if text.len > maximum { return false }
	for byte in text { if byte < 0x20 || byte == 0x7f { return false } }
	return true
}

// Validate the entire record before allocating owned event strings. A damaged
// record is never silently turned into an empty calendar and overwritten.
// Validation uses an Option so discarded failures do not allocate IError boxes.
fn calendar_parse_events(record string) ?CalendarEvents {
	if record.len > calendar_events_max_bytes || !record.starts_with('VINIX-CALENDAR 1\n') {
		return none
	}
	mut model := CalendarEvents{}
	mut start := 'VINIX-CALENDAR 1\n'.len
	defer {
		// On a parse failure, free any completed rows before returning the error.
		if start < record.len { model.free_items() }
	}
	for start < record.len {
		if model.count >= calendar_events_limit { return none }
		mut end := start
		for end < record.len && record[end] != `\n` { end++ }
		if end == record.len { return none }
		mut fields := [7]int{}
		fields[0] = start
		mut count := 1
		for at in start .. end {
			if record[at] == `\t` {
				if count >= 6 { return none }
				fields[count] = at + 1
				count++
			}
		}
		if count != 6 { return none }
		fields[6] = end + 1
		year := calendar_integer(calendar_borrow(record, fields[0], fields[1] - 1)) or { return none }
		month := calendar_integer(calendar_borrow(record, fields[1], fields[2] - 1)) or { return none }
		day := calendar_integer(calendar_borrow(record, fields[2], fields[3] - 1)) or { return none }
		time := calendar_borrow(record, fields[3], fields[4] - 1)
		minutes := if time == '-1' {
			-1
		} else {
			calendar_integer(time) or { return none }
		}
		title := calendar_borrow(record, fields[4], fields[5] - 1)
		location := calendar_borrow(record, fields[5], end)
		if year < 1 || year > 9999 || month < 1 || month > 12 || day < 1
			|| day > calendar_days_in_month(year, month) || minutes < -1 || minutes >= 1440
			|| title.len == 0 || !calendar_clean_field(title, calendar_event_title_limit)
			|| !calendar_clean_field(location, calendar_event_location_limit) {
			return none
		}
		model.items[model.count] = CalendarEvent{
			year:     year
			month:    month
			day:      day
			minutes:  minutes
			title:    title.clone()
			location: location.clone()
		}
		model.count++
		start = end + 1
	}
	return model
}

fn (mut model CalendarEvents) free_items() {
	for index in 0 .. model.count {
		unsafe {
			model.items[index].title.free()
			model.items[index].location.free()
		}
		model.items[index] = CalendarEvent{}
	}
	model.count = 0
}

fn (mut model CalendarEvents) load(home string) {
	path := '${home}/${calendar_events_filename}'
	defer { unsafe { path.free() } }
	if os.exists(path) {
		info := os.lstat(path) or {
			model.read_failed = true
			return
		}
		if info.get_filetype() != .regular || info.size > calendar_events_max_bytes {
			model.read_failed = true
		} else {
			record := os.read_file(path) or {
				model.read_failed = true
				return
			}
			defer { unsafe { record.free() } }
			model = calendar_parse_events(record) or { CalendarEvents{ read_failed: true } }
			model.record = record.clone()
		}
	}
	model.home = home.clone()
	for index in 0 .. calendar_events_limit {
		index_text := index.str()
		model.actions[index] = 'calendar.event.row.${index_text}'
		unsafe { index_text.free() }
	}
}

fn (model &CalendarEvents) has_date(year int, month int, day int) bool {
	for index in 0 .. model.count {
		event := model.items[index]
		if event.year == year && event.month == month && event.day == day { return true }
	}
	return false
}

fn (model &CalendarEvents) encode() string {
	mut bytes := []u8{cap: 4096}
	unsafe { bytes.flags |= .noslices }
	editor_append(mut bytes, 'VINIX-CALENDAR 1\n')
	for index in 0 .. model.count {
		event := model.items[index]
		year := event.year.str()
		month := event.month.str()
		day := event.day.str()
		minutes := event.minutes.str()
		for field in [year, month, day, minutes, event.title]! {
			editor_append(mut bytes, field)
			bytes << `\t`
		}
		editor_append(mut bytes, event.location)
		bytes << `\n`
		unsafe {
			year.free()
			month.free()
			day.free()
			minutes.free()
		}
	}
	data := editor_bytes_text(bytes).clone()
	unsafe { bytes.free() }
	return data
}

fn (mut model CalendarEvents) save() bool {
	model.save_conflict = false
	if model.read_failed || model.home.len == 0 || !os.is_dir(model.home) { return false }
	lock_fd := calendar_lock_acquire(model.home)
	if lock_fd < 0 { return false }
	defer { desktop_close(lock_fd) }
	path := '${model.home}/${calendar_events_filename}'
	defer { unsafe { path.free() } }
	// Reject stale snapshots so a second Calendar window cannot erase events
	// saved since this window opened. Reopening reloads the latest record.
	if os.exists(path) {
		info := os.lstat(path) or { return false }
		if info.get_filetype() != .regular || info.size > calendar_events_max_bytes { return false }
		current := os.read_file(path) or { return false }
		matches := current == model.record
		unsafe { current.free() }
		if !matches {
			model.save_conflict = true
			return false
		}
	} else if model.record.len > 0 {
		model.save_conflict = true
		return false
	}
	data := model.encode()
	defer { unsafe { data.free() } }
	fd, temporary := calendar_temporary_file(model.home)
	if fd < 0 { return false }
	mut published := false
	defer {
		if !published { calendar_remove_temporary(fd, temporary) }
		desktop_close(fd)
		unsafe { temporary.free() }
	}
	if !desktop_write_all(fd, data.str, u64(data.len)) || !desktop_preferences_fsync(fd) {
		return false
	}
	if !calendar_temporary_matches(fd, temporary) { return false }
	if C.rename(&char(temporary.str), &char(path.str)) != 0 { return false }
	published = true
	unsafe { model.record.free() }
	model.record = data.clone()
	// Publication already succeeded. Keep the in-memory state consistent with
	// the visible record even if the final directory durability check fails.
	if !desktop_preferences_sync_directory(model.home, fd) {
		eprintln('vinix-calendar: events saved, but directory synchronization failed')
	}
	return true
}

fn calendar_event_time(minutes int) string {
	if minutes < 0 { return tr('calendar.event.all_day').clone() }
	hour := pad2(minutes / 60)
	minute := pad2(minutes % 60)
	result := '${hour}:${minute}'
	unsafe {
		hour.free()
		minute.free()
	}
	return result
}

fn calendar_parse_time(text string) ?int {
	if text.len != 5 || text[2] != `:` { return none }
	hour := calendar_integer(calendar_borrow(text, 0, 2)) or { return none }
	minute := calendar_integer(calendar_borrow(text, 3, 5)) or { return none }
	if hour > 23 || minute > 59 { return none }
	return hour * 60 + minute
}

fn calendar_event_button(action string, text string, x int, y int, width int, active bool) ui2.Element {
	return ui2.button(action, text, ui2.rect(f64(x), f64(y), f64(width), 28), ui2.BoxStyle{
		bg:     if active { app_accent } else { calendar_button }
		radius: 5
	}, ui2.TextStyle{ color: if active { app_on_accent } else { body_text }, size: 12, align: .center })
}

fn (mut a CalendarApp) append_agenda(mut children []ui2.Element, width int, top int) {
	children << ui2.view('', ui2.rect(18, f64(top), f64(width - 36), 1), ui2.BoxStyle{ bg: body_rule }, [])
	children << ui2.label('', tr('calendar.events'), ui2.rect(18, f64(top + 8), f64(width - 308), 24), ui2.TextStyle{ color: body_heading, size: 13, bold: true })
	children << calendar_event_button('calendar.ics.open', tr('calendar.ics.open'), width - 276, top + 6, 144, false)
	children << calendar_event_button('calendar.event.new', tr('calendar.event.new'), width - 124, top + 6, 106, false)
	mut indices := [calendar_events_limit]int{}
	mut count := 0
	for index in 0 .. a.events.count {
		event := a.events.items[index]
		if event.year == a.year && event.month == a.month && event.day == a.selected_day {
			// All-day first, then local time. Stable ordering for equal times.
			mut at := count
			for at > 0 && a.events.items[indices[at - 1]].minutes > event.minutes {
				indices[at] = indices[at - 1]
				at--
			}
			indices[at] = index
			count++
		}
	}
	maximum := if count > 3 { count - 3 } else { 0 }
	if a.agenda_scroll > maximum { a.agenda_scroll = maximum }
	if count == 0 {
		children << ui2.label('', tr(if a.events.read_failed {
			'calendar.event.read_failed'
		} else {
			'calendar.events.empty'
		}), ui2.rect(18, f64(top + 44), f64(width - 36), 30), ui2.TextStyle{ color: body_muted, size: 12 })
	}
	for row := 0; row < 3 && row + a.agenda_scroll < count; row++ {
		index := indices[row + a.agenda_scroll]
		event := a.events.items[index]
		y := top + 40 + row * 30
		time := calendar_event_time(event.minutes)
		children << ui2.label(frame_owned_text_id, time, ui2.rect(18, f64(y), 74, 26), ui2.TextStyle{ color: body_muted, size: 11 })
		children << ui2.button(a.events.actions[index], event.title, ui2.rect(96, f64(y), f64(width - 170), 26), ui2.BoxStyle{ transparent: true }, ui2.TextStyle{ color: body_text, size: 12 })
	}
	if count > 3 {
		children << calendar_event_button('calendar.agenda.previous', '<', width - 66, top + 48, 22, false)
		children << calendar_event_button('calendar.agenda.next', '>', width - 42, top + 48, 22, false)
	}
	if a.status_key.len > 0 {
		children << ui2.label('', tr(a.status_key), ui2.rect(18, f64(top + 128), f64(width - 36), 20), ui2.TextStyle{ color: body_text, size: 11 })
	}
}

fn (mut a CalendarApp) begin_event(index int) {
	if a.events.read_failed {
		a.status_key = 'calendar.event.read_failed'
		return
	}
	if index < 0 && a.events.count >= calendar_events_limit {
		a.status_key = 'calendar.event.limit'
		return
	}
	a.edit_index = index
	a.edit_focus = 0
	a.edit_select_all = false
	a.edit_pending_len = 0
	a.status_key = ''
	a.editing = true
	a.search_focus = false
	a.search_selected = false
	a.search_pending_len = 0
	a.search_escape_len = 0
	if a.edit_title.cap == 0 {
		a.edit_title = []u8{cap: calendar_event_title_limit}
		a.edit_time = []u8{cap: 5}
		a.edit_location = []u8{cap: calendar_event_location_limit}
	}
	a.edit_title.clear()
	a.edit_time.clear()
	a.edit_location.clear()
	if index >= 0 {
		event := a.events.items[index]
		a.edit_all_day = event.minutes < 0
		editor_append(mut a.edit_title, event.title)
		editor_append(mut a.edit_location, event.location)
		time := calendar_event_time(if event.minutes < 0 { 540 } else { event.minutes })
		editor_append(mut a.edit_time, time)
		unsafe { time.free() }
	} else {
		a.edit_all_day = true
		editor_append(mut a.edit_time, '09:00')
	}
}

fn (mut a CalendarApp) save_event() {
	if !a.editing { return }
	title := editor_bytes_text(a.edit_title)
	location := editor_bytes_text(a.edit_location)
	minutes := if a.edit_all_day {
		-1
	} else {
		calendar_parse_time(editor_bytes_text(a.edit_time)) or {
			a.status_key = 'calendar.event.invalid_time'
			return
		}
	}
	if title.len == 0 || !calendar_clean_field(title, calendar_event_title_limit) {
		a.status_key = 'calendar.event.title_required'
		return
	}
	if !calendar_clean_field(location, calendar_event_location_limit) {
		a.status_key = 'calendar.event.invalid_location'
		return
	}
	index := if a.edit_index >= 0 { a.edit_index } else { a.events.count }
	previous := a.events.items[index]
	a.events.items[index] = CalendarEvent{
		year:     a.year
		month:    a.month
		day:      a.selected_day
		minutes:  minutes
		title:    title.clone()
		location: location.clone()
	}
	if a.edit_index < 0 { a.events.count++ }
	if !a.events.save() {
		unsafe {
			a.events.items[index].title.free()
			a.events.items[index].location.free()
		}
		a.events.items[index] = previous
		if a.edit_index < 0 { a.events.count-- }
		a.status_key = if a.events.save_conflict {
			'calendar.event.changed'
		} else {
			'calendar.event.save_failed'
		}
		return
	}
	unsafe {
		previous.title.free()
		previous.location.free()
	}
	a.editing = false
	a.status_key = ''
}

fn (mut a CalendarApp) delete_event() {
	if !a.editing || a.edit_index < 0 || a.edit_index >= a.events.count { return }
	index := a.edit_index
	previous := a.events.items[index]
	for at := index + 1; at < a.events.count; at++ { a.events.items[at - 1] = a.events.items[at] }
	a.events.count--
	a.events.items[a.events.count] = CalendarEvent{}
	if !a.events.save() {
		for at := a.events.count; at > index; at-- { a.events.items[at] = a.events.items[at - 1] }
		a.events.items[index] = previous
		a.events.count++
		a.status_key = if a.events.save_conflict {
			'calendar.event.changed'
		} else {
			'calendar.event.save_failed'
		}
		return
	}
	unsafe {
		previous.title.free()
		previous.location.free()
	}
	a.editing = false
	a.status_key = ''
}

fn calendar_edit_bytes(mut bytes []u8, input u8, maximum int, select_all bool) {
	if input == 8 || input == 127 {
		if select_all {
			bytes.clear()
			return
		}
		if bytes.len > 0 { unsafe { bytes.len = editor_char_before(bytes, bytes.len) } }
	} else if input >= 0x20 && input != 127 {
		if select_all { bytes.clear() }
		if bytes.len < maximum { bytes << input }
	}
}

fn (mut a CalendarApp) key_input(input string) {
	if a.interchange { a.ics_key_input(input) return }
	if !a.editing { a.search_key_input(input) return }
	mut at := 0
	for at < input.len {
		byte := input[at]
		if a.edit_pending_len > 0 {
			if editor_utf8_follows(a.edit_pending[0], a.edit_pending_len, byte) {
				a.edit_pending[a.edit_pending_len] = byte
				a.edit_pending_len++
				if a.edit_pending_len == editor_utf8_length(a.edit_pending[0]) {
					a.type_event_character()
				}
				at++
				continue
			}
			a.edit_pending_len = 0
		}
		if byte >= 0x80 {
			if editor_utf8_length(byte) > 1 {
				a.edit_pending[0] = byte
				a.edit_pending_len = 1
			}
			at++
			continue
		}
		if byte == 0x1b {
			if at + 1 < input.len && (input[at + 1] == `[` || input[at + 1] == `O`) {
				at += 2
				for at < input.len && (input[at] < 0x40 || input[at] > 0x7e) { at++ }
				at++
				continue
			}
			a.editing = false
			a.status_key = ''
			return
		}
		if byte == `\r` || byte == `\n` {
			a.save_event()
			return
		}
		if byte == `\t` {
			a.edit_focus = (a.edit_focus + 1) % 3
			if a.edit_focus == 1 && a.edit_all_day { a.edit_focus = 2 }
			a.edit_select_all = true
		} else if byte == 1 {
			a.edit_select_all = true
		} else {
			match a.edit_focus {
				0 {
					calendar_edit_bytes(mut a.edit_title, byte, calendar_event_title_limit, a.edit_select_all)
				}
				1 { calendar_edit_bytes(mut a.edit_time, byte, 5, a.edit_select_all) }
				else {
					calendar_edit_bytes(mut a.edit_location, byte, calendar_event_location_limit, a.edit_select_all)
				}
			}
			if byte >= 0x20 || byte == 8 || byte == 127 { a.edit_select_all = false }
		}
		at++
	}
}

fn calendar_append_character(mut bytes []u8, character string, maximum int, select_all bool) {
	if select_all { bytes.clear() }
	if bytes.len + character.len <= maximum { editor_append(mut bytes, character) }
}

// Clipboard data is text, never keyboard commands. Skip controls and invalid
// UTF-8 without accidentally triggering Save, Escape, or switching fields.
fn calendar_paste_bytes(mut bytes []u8, text string, maximum int, select_all bool) bool {
	mut at := 0
	mut pasted := false
	for at < text.len {
		lead := text[at]
		length := editor_utf8_length(lead)
		if lead < 0x20 || lead == 0x7f || length == 0 || at + length > text.len {
			at++
			continue
		}
		mut valid := true
		for index := 1; index < length; index++ {
			if !editor_utf8_follows(lead, index, text[at + index]) {
				valid = false
				break
			}
		}
		if !valid {
			at++
			continue
		}
		if !pasted && select_all { bytes.clear() }
		if bytes.len + length > maximum { break }
		editor_append(mut bytes, calendar_borrow(text, at, at + length))
		pasted = true
		at += length
	}
	return pasted
}

fn (mut a CalendarApp) paste_input(text string) {
	if a.interchange { a.ics_paste(text) return }
	if !a.editing { a.paste_search(text) return }
	if text.len == 0 { return }
	a.edit_pending_len = 0
	pasted := match a.edit_focus {
		0 {
			calendar_paste_bytes(mut a.edit_title, text, calendar_event_title_limit, a.edit_select_all)
		}
		1 { calendar_paste_bytes(mut a.edit_time, text, 5, a.edit_select_all) }
		else {
			calendar_paste_bytes(mut a.edit_location, text, calendar_event_location_limit, a.edit_select_all)
		}
	}
	if pasted { a.edit_select_all = false }
}

fn (mut a CalendarApp) type_event_character() {
	character := unsafe { tos(&a.edit_pending[0], a.edit_pending_len) }
	match a.edit_focus {
		0 {
			calendar_append_character(mut a.edit_title, character, calendar_event_title_limit, a.edit_select_all)
		}
		1 { calendar_append_character(mut a.edit_time, character, 5, a.edit_select_all) }
		else {
			calendar_append_character(mut a.edit_location, character, calendar_event_location_limit, a.edit_select_all)
		}
	}
	a.edit_pending_len = 0
	a.edit_select_all = false
}

fn (mut a CalendarApp) build_event_editor(width int, height int) ui2.Element {
	mut children := frame_elements(20)
	children << ui2.label('', a.selection, ui2.rect(18, 12, f64(width - 36), 32), ui2.TextStyle{ color: body_heading, size: 16, bold: true })
	labels := [tr('calendar.event.title'), tr('calendar.event.time'), tr('calendar.event.location')]!
	actions := ['calendar.event.title', 'calendar.event.time', 'calendar.event.location']!
	values := [editor_bytes_text(a.edit_title), editor_bytes_text(a.edit_time),
		editor_bytes_text(a.edit_location)]!
	for field in 0 .. 3 {
		y := 60 + field * 76
		children << ui2.label('', labels[field], ui2.rect(18, f64(y), f64(width - 36), 20), ui2.TextStyle{ color: body_muted, size: 12 })
		if field == 1 {
			children << calendar_event_button('calendar.event.all_day', tr('calendar.event.all_day'), 18, y + 24, 106, a.edit_all_day)
			if a.edit_all_day { continue }
		}
		x := if field == 1 { 138 } else { 18 }
		field_width := if field == 1 { 100 } else { width - 36 }
		children << ui2.clickable_view(actions[field], ui2.rect(f64(x), f64(y + 24), f64(field_width), 32), ui2.BoxStyle{
			bg:            calendar_button
			radius:        5
			border_color:  if a.edit_focus == field { app_accent } else { body_rule }
			border_left:   1
			border_right:  1
			border_top:    1
			border_bottom: 1
		}, frame_child(ui2.text_field('', '', values[field], ui2.rect(8, 0, f64(field_width - 16), 32), ui2.BoxStyle{ transparent: true }, ui2.TextStyle{ color: body_text, size: 13 }, 0)))
	}
	if a.status_key.len > 0 {
		children << ui2.label('', tr(a.status_key), ui2.rect(18, 295, f64(width - 36), 36), ui2.TextStyle{ color: body_text, size: 12 })
	}
	y := if height > 370 { height - 48 } else { 334 }
	children << calendar_event_button('calendar.event.save', tr('calendar.event.save'), width - 206, y, 90, true)
	children << calendar_event_button('calendar.event.cancel', tr('calendar.event.cancel'), width - 106, y, 88, false)
	if a.edit_index >= 0 {
		children << calendar_event_button('calendar.event.delete', tr('calendar.event.delete'), 18, y, 90, false)
	}
	return ui2.screen(app_surface, children)
}

fn (mut a CalendarApp) close_app() {
	a.events.free_items()
	for action in a.events.actions {
		unsafe { action.free() }
	}
	unsafe {
		a.events.home.free()
		a.events.record.free()
		a.month_title.free()
		a.selection.free()
		a.edit_title.free()
		a.edit_time.free()
		a.edit_location.free()
		a.ics_import_path.free()
		a.ics_export_path.free()
	}
	a.ics_import_path = []u8{}
	a.ics_export_path = []u8{}
}
