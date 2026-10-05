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

fn (mut a CalendarApp) build_interchange(size ui2.Rect) ui2.Element {
	mut children := frame_elements(16)
	w := int(size.width)
	children << ui2.label('', tr('calendar.ics.title'), ui2.rect(18, 12, f64(w - 180), 28), ui2.TextStyle{ size: 18, bold: true, color: body_heading })
	children << calendar_event_button('calendar.ics.back', tr('calendar.ics.back'), w - 136, 12, 118, false)
	if size.width < 400 || size.height < 430 {
		children << ui2.label('', tr('calendar.ics.scope'), ui2.rect(18, 54, f64(w - 36), 140), ui2.TextStyle{ size: 12, color: body_muted, lines: 6 })
		return ui2.screen(app_surface, children)
	}
	children << ui2.label('', tr('calendar.ics.scope'), ui2.rect(18, 48, f64(w - 36), 54), ui2.TextStyle{ size: 11, color: body_muted, lines: 3 })
	children << ui2.label('', tr('calendar.ics.import_path'), ui2.rect(18, 110, f64(w - 36), 18), ui2.TextStyle{ size: 11, color: body_muted })
	children << console_field('calendar.ics.import_path', editor_bytes_text(a.ics_import_path), 18, 132, w - 36, a.ics_focus == 0)
	children << calendar_event_button('calendar.ics.import', tr('calendar.ics.import'), 18, 168, 154, false)
	children << ui2.label('', tr('calendar.ics.export_path'), ui2.rect(18, 208, f64(w - 36), 18), ui2.TextStyle{ size: 11, color: body_muted })
	children << console_field('calendar.ics.export_path', editor_bytes_text(a.ics_export_path), 18, 230, w - 36, a.ics_focus == 1)
	children << calendar_event_button('calendar.ics.export', tr('calendar.ics.export'), 18, 266, 154, false)
	children << ui2.label('', tr('calendar.ics.merge'), ui2.rect(18, 310, f64(w - 36), 60), ui2.TextStyle{ size: 11, color: body_muted, lines: 3 })
	children << ui2.label('', tr(a.ics_status), ui2.rect(18, 382, f64(w - 36), 42), ui2.TextStyle{ size: 11, color: body_text, lines: 2 })
	return ui2.screen(app_surface, children)
}
