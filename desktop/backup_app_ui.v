// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn (mut a BackupApp) focus_field(field int) {
	if a.active { return }
	a.focus = field
	a.select_all = false
	a.pending_len = 0
}

fn (mut a BackupApp) handle(event_id string) ! {
	a.pending_len = 0
	if event_id.starts_with('backup.version.') {
		if a.active { return }
		index := console_borrow(event_id, 15, event_id.len).int()
		if index >= 0 && index < a.versions.len { a.selected = index }
		return
	}
	match event_id {
		'backup.source' { a.focus_field(0) }
		'backup.store' { a.focus_field(1) }
		'backup.restore_path' { a.focus_field(2) }
		'backup.start' { a.start_backup() }
		'backup.refresh' { a.refresh_versions() }
		'backup.restore' { a.start_restore() }
		'backup.cancel' {
			a.stop_scan()
			if a.active { a.fail('backup.cancelled') }
		}
		'backup.previous' { if a.scroll >= a.page_rows { a.scroll -= a.page_rows } else { a.scroll = 0 } }
		'backup.next' {
			if a.scroll + a.page_rows < a.versions.len { a.scroll += a.page_rows }
		}
		else {}
	}
}

fn (mut a BackupApp) append_character(character string) {
	if a.active { return }
	match a.focus {
		0 { console_edit_character(mut a.source_input, character, backup_path_limit, a.select_all) }
		1 { console_edit_character(mut a.store_input, character, backup_path_limit, a.select_all) }
		2 { console_edit_character(mut a.restore_input, character, backup_path_limit, a.select_all) }
		else { return }
	}
	a.select_all = false
}

fn (mut a BackupApp) paste_input(text string) {
	if a.active || a.focus < 0 { return }
	a.pending_len = 0
	match a.focus {
		0 { console_paste_field(mut a.source_input, text, backup_path_limit, a.select_all) }
		1 { console_paste_field(mut a.store_input, text, backup_path_limit, a.select_all) }
		2 { console_paste_field(mut a.restore_input, text, backup_path_limit, a.select_all) }
		else { return }
	}
	a.select_all = false
}

fn (mut a BackupApp) key_input(input string) {
	if input == '\x1b[5~' { a.handle('backup.previous') or {} return }
	if input == '\x1b[6~' { a.handle('backup.next') or {} return }
	if input.len > 1 && input[0] == 0x1b { a.pending_len = 0 return }
	for byte in input {
		if a.pending_len > 0 {
			if editor_utf8_follows(a.pending[0], a.pending_len, byte) {
				a.pending[a.pending_len] = byte
				a.pending_len++
				if a.pending_len == editor_utf8_length(a.pending[0]) {
					a.append_character(unsafe { tos(&a.pending[0], a.pending_len) })
					a.pending_len = 0
				}
				continue
			}
			a.pending_len = 0
		}
		if byte == 0x1b { a.focus = -1 a.select_all = false }
		else if byte == `\t` { a.focus_field((a.focus + 1) % 3) }
		else if byte == `\n` || byte == `\r` {
			if a.focus == 2 { a.start_restore() } else { a.start_backup() }
		} else if byte == 0x01 { a.select_all = true }
		else if byte == 0x7f || byte == 0x08 {
			if a.active { continue }
			match a.focus {
				0 { console_backspace(mut a.source_input, a.select_all) }
				1 { console_backspace(mut a.store_input, a.select_all) }
				2 { console_backspace(mut a.restore_input, a.select_all) }
				else {}
			}
			a.select_all = false
		} else if byte >= 0x20 && byte < 0x7f { a.append_character(unsafe { tos(&byte, 1) }) }
		else if editor_utf8_length(byte) > 1 { a.pending[0] = byte a.pending_len = 1 }
	}
}

fn (mut a BackupApp) build(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)
	a.page_rows = if height > 400 { (height - 386) / 30 } else { 1 }
	if a.page_rows < 1 { a.page_rows = 1 }
	mut children := frame_elements(24 + a.page_rows)
	for field in 0 .. 3 {
		key := match field { 0 { 'backup.source' } 1 { 'backup.store' } else { 'backup.restore_path' } }
		value := match field { 0 { editor_bytes_text(a.source_input) } 1 { editor_bytes_text(a.store_input) } else { editor_bytes_text(a.restore_input) } }
		y := 10 + field * 61
		children << ui2.label('', tr(key), ui2.rect(14, f64(y), f64(width - 28), 20), ui2.TextStyle{color: body_muted, size: 12})
		children << console_field(key, value, 14, y + 23, width - 28, a.focus == field && !a.active)
	}
	for index, key in ['backup.start', 'backup.refresh', 'backup.restore', 'backup.cancel']! {
		children << console_button(key, key, 14 + index * 130, 197, 120, a.active && index == 3)
	}
	children << ui2.label('', tr('backup.versions'), ui2.rect(14, 239, f64(width - 28), 20), ui2.TextStyle{color: body_text, size: 13})
	if a.versions.len == 0 {
		children << ui2.label('', tr('backup.no_versions'), ui2.rect(14, 268, f64(width - 28), 28), ui2.TextStyle{color: body_muted, size: 12})
	}
	for row in 0 .. a.page_rows {
		index := a.scroll + row
		if index >= a.versions.len { break }
		children << ui2.button(a.version_ids[index], a.versions[index], ui2.rect(14, f64(266 + row * 30), f64(width - 28), 26),
			ui2.BoxStyle{bg: if a.selected == index { app_accent } else { body_panel }, radius: 4},
			ui2.TextStyle{color: if a.selected == index { app_on_accent } else { body_text }, size: 12})
	}
	footer := height - 110
	children << console_button('backup.previous', 'backup.previous', 14, footer, 110, false)
	children << console_button('backup.next', 'backup.next', 132, footer, 90, false)
	if a.version_limit {
		children << ui2.label('', tr('backup.version_limit'), ui2.rect(234, f64(footer), f64(width - 248), 28), ui2.TextStyle{color: body_muted, size: 11})
	}
	children << ui2.label('', tr(a.status), ui2.rect(14, f64(footer + 33), f64(width - 28), 22), ui2.TextStyle{color: body_text, size: 12})
	children << ui2.label('', tr('backup.progress'), ui2.rect(14, f64(footer + 58), 245, 20), ui2.TextStyle{color: body_muted, size: 11})
	children << ui2.label('', a.progress, ui2.rect(263, f64(footer + 58), 150, 20), ui2.TextStyle{color: body_text, size: 11})
	children << ui2.label('', a.output_path, ui2.rect(423, f64(footer + 58), f64(width - 437), 20), ui2.TextStyle{color: body_muted, size: 11})
	children << ui2.label('', tr('backup.hint'), ui2.rect(14, f64(footer + 81), f64(width - 28), 22), ui2.TextStyle{color: body_muted, size: 11})
	return ui2.screen(app_surface, children)
}
