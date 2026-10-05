// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn (mut a CalendarApp) open_interchange() {
	a.interchange = true
	a.ics_focus = 0
	a.ics_selected = true
	a.ics_pending_len = 0
	if a.ics_import_path.cap > 0 { return }
	a.ics_import_path = []u8{cap: calendar_ics_path_limit}
	a.ics_export_path = []u8{cap: calendar_ics_path_limit}
	unsafe { a.ics_import_path.flags |= .noslices a.ics_export_path.flags |= .noslices }
	home := calendar_ics_home(a.events.home)
	defer { unsafe { home.free() } }
	editor_append(mut a.ics_import_path, home)
	editor_append(mut a.ics_import_path, '/Calendar.ics')
	editor_append(mut a.ics_export_path, home)
	editor_append(mut a.ics_export_path, '/Calendar-export.ics')
	a.ics_status = 'calendar.ics.ready'
}

fn (mut a CalendarApp) ics_paste(text string) {
	a.ics_pending_len = 0
	pasted := if a.ics_focus == 0 {
		calendar_paste_bytes(mut a.ics_import_path, text, calendar_ics_path_limit, a.ics_selected)
	} else { calendar_paste_bytes(mut a.ics_export_path, text, calendar_ics_path_limit, a.ics_selected) }
	if pasted { a.ics_selected = false }
}

fn (mut a CalendarApp) ics_character(text string) {
	if a.ics_focus == 0 { calendar_append_character(mut a.ics_import_path, text, calendar_ics_path_limit, a.ics_selected) }
	else { calendar_append_character(mut a.ics_export_path, text, calendar_ics_path_limit, a.ics_selected) }
	a.ics_selected = false
}

fn (mut a CalendarApp) ics_key_input(input string) {
	mut at := 0
	for at < input.len {
		byte := input[at]
		if a.ics_pending_len > 0 {
			if editor_utf8_follows(a.ics_pending[0], a.ics_pending_len, byte) {
				a.ics_pending[a.ics_pending_len] = byte a.ics_pending_len++
				if a.ics_pending_len == editor_utf8_length(a.ics_pending[0]) {
					a.ics_character(unsafe { tos(&a.ics_pending[0], a.ics_pending_len) })
					a.ics_pending_len = 0
				}
				at++ continue
			}
			a.ics_pending_len = 0
		}
		if byte >= 128 {
			if editor_utf8_length(byte) > 1 { a.ics_pending[0] = byte a.ics_pending_len = 1 }
		} else if byte == 27 {
			if at + 1 < input.len && (input[at + 1] == `[` || input[at + 1] == `O`) {
				at += 2
				for at < input.len && (input[at] < 0x40 || input[at] > 0x7e) { at++ }
			} else { a.interchange = false return }
		} else if byte == 9 { a.ics_focus = 1 - a.ics_focus a.ics_selected = true }
		else if byte == 1 { a.ics_selected = true }
		else if byte == 13 || byte == 10 {
			if a.ics_focus == 0 { a.import_ics(editor_bytes_text(a.ics_import_path)) }
			else { a.export_ics(editor_bytes_text(a.ics_export_path)) }
		} else if byte == 8 || byte == 127 {
			if a.ics_focus == 0 { calendar_edit_bytes(mut a.ics_import_path, byte, calendar_ics_path_limit, a.ics_selected) }
			else { calendar_edit_bytes(mut a.ics_export_path, byte, calendar_ics_path_limit, a.ics_selected) }
			a.ics_selected = false
		} else if byte >= 32 { a.ics_character(unsafe { tos(&byte, 1) }) }
		at++
	}
}

// The desktop label renderer draws one line. Each row borrows a UTF-8 span of
// the translation, whose storage outlives the frame; no copied text is needed.
fn calendar_ics_explanation(mut children []ui2.Element, id string, text string, width int, top int, row_height int, maximum_rows int) {
	columns := if width / 7 > 0 { width / 7 } else { 1 }
	mut at := 0
	for row in 0 .. maximum_rows {
		for at < text.len && text[at] == ` ` { at++ }
		if at == text.len { break }
		start := at
		mut end := at
		mut last_space := -1
		mut count := 0
		for end < text.len && count < columns {
			if text[end] == ` ` { last_space = end }
			length := editor_utf8_length(text[end])
			end += if length > 0 { length } else { 1 }
			count++
		}
		if end < text.len && text[end] != ` ` && last_space > start { end = last_space }
		// Preserve the remaining text even in a window below the usable size.
		if row + 1 == maximum_rows { end = text.len }
		children << ui2.label(id, calendar_borrow(text, start, end), ui2.rect(18, f64(top + row * row_height), f64(width), f64(row_height)), ui2.TextStyle{ size: 11, color: body_muted })
		at = end
	}
}

fn (mut a CalendarApp) build_interchange(size ui2.Rect) ui2.Element {
	mut children := frame_elements(24)
	w := int(size.width)
	children << ui2.label('', tr('calendar.ics.title'), ui2.rect(18, 12, f64(w - 180), 28), ui2.TextStyle{ size: 18, bold: true, color: body_heading })
	children << calendar_event_button('calendar.ics.back', tr('calendar.ics.back'), w - 136, 12, 118, false)
	if size.width < 400 || size.height < 430 {
		calendar_ics_explanation(mut children, 'calendar.ics.scope.row', tr('calendar.ics.scope'), w - 36, 54, 13, 10)
		return ui2.screen(app_surface, children)
	}
	calendar_ics_explanation(mut children, 'calendar.ics.scope.row', tr('calendar.ics.scope'), w - 36, 48, 13, 4)
	children << ui2.label('', tr('calendar.ics.import_path'), ui2.rect(18, 110, f64(w - 36), 18), ui2.TextStyle{ size: 11, color: body_muted })
	children << console_field('calendar.ics.import_path', editor_bytes_text(a.ics_import_path), 18, 132, w - 36, a.ics_focus == 0)
	children << calendar_event_button('calendar.ics.import', tr('calendar.ics.import'), 18, 168, 154, false)
	children << ui2.label('', tr('calendar.ics.export_path'), ui2.rect(18, 208, f64(w - 36), 18), ui2.TextStyle{ size: 11, color: body_muted })
	children << console_field('calendar.ics.export_path', editor_bytes_text(a.ics_export_path), 18, 230, w - 36, a.ics_focus == 1)
	children << calendar_event_button('calendar.ics.export', tr('calendar.ics.export'), 18, 266, 154, false)
	calendar_ics_explanation(mut children, 'calendar.ics.merge.row', tr('calendar.ics.merge'), w - 36, 310, 12, 5)
	children << ui2.label('', tr(a.ics_status), ui2.rect(18, 382, f64(w - 36), 42), ui2.TextStyle{ size: 11, color: body_text, lines: 2 })
	return ui2.screen(app_surface, children)
}
