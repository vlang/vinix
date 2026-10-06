// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn (mut a NotesApp) import_key_input(input string) {
	if input.len > 1 && input[0] == 0x1b {
		a.pending_len = 0
		if input == '\x1b[3~' { a.backspace(true) }
		return
	}
	for byte in input {
		if a.pending_len > 0 {
			if editor_utf8_follows(a.pending[0], a.pending_len, byte) {
				a.pending[a.pending_len] = byte
				a.pending_len++
				if a.pending_len == editor_utf8_length(a.pending[0]) {
					character := unsafe { tos(&a.pending[0], a.pending_len) }
					if notes_valid_text(character, 4, false) { a.insert_text(character) }
					a.pending_len = 0
				}
				continue
			}
			a.pending_len = 0
		}
		if byte == 0x01 { a.select_all = true }
		else if byte == 0x1b { a.cancel_import() return }
		else if byte == `\r` || byte == `\n` { a.import_note() return }
		else if byte == 0x7f || byte == 8 { a.backspace(false) }
		else if byte == `\t` { a.focus_field(4) }
		else if byte >= 0x20 && byte < 0x7f { a.insert_text(unsafe { tos(&byte, 1) }) }
		else if editor_utf8_length(byte) > 1 { a.pending[0] = byte a.pending_len = 1 }
	}
}

fn (a &NotesApp) build_import(size ui2.Rect) ui2.Element {
	width := int(size.width)
	height := int(size.height)
	mut children := frame_elements(7)
	if width < 380 || height < 218 {
		available_width := if width > 24 { width - 24 } else { 0 }
		available_height := if height > 24 { height - 24 } else { 0 }
		children << ui2.label('', tr('notes.import_enlarge'),
			ui2.rect(f64(if width > 24 { 12 } else { 0 }), f64(if height > 24 { 12 } else { 0 }),
				f64(available_width), f64(available_height)), ui2.TextStyle{ size: 11, color: body_muted })
		return ui2.screen(app_surface, children)
	}
	children << ui2.label('', tr('notes.import_title'), ui2.rect(12, 12, f64(width - 24), 24),
		ui2.TextStyle{ size: 15, bold: true, color: body_heading })
	children << ui2.label('', tr('notes.import_scope'), ui2.rect(12, 44, f64(width - 24), 44),
		ui2.TextStyle{ size: 11, color: body_muted })
	children << console_field('notes.import_path', editor_bytes_text(a.import_path), 12, 100, width - 24, a.focus == 4)
	children << console_button('notes.import_confirm', 'notes.import_confirm', 12, 140, (width - 32) / 2, false)
	children << console_button('notes.import_cancel', 'notes.import_cancel', 20 + (width - 32) / 2, 140, (width - 32) / 2, false)
	children << ui2.label('', tr(if a.import_status.len > 0 { a.import_status } else { 'notes.import_hint' }),
		ui2.rect(12, 178, f64(width - 24), 28), ui2.TextStyle{ size: 11, color: app_accent })
	return ui2.screen(app_surface, children)
}
