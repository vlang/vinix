// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn (mut a ArchiveApp) focus_field(field int) {
	if a.operation != .idle { return }
	a.focus = field
	a.pending_len = 0
	a.select_all = false
}

fn archive_set_field(mut bytes []u8, text string) {
	bytes.clear()
	console_paste_field(mut bytes, text, archive_path_limit, false)
}

fn (mut a ArchiveApp) handle(event_id string) ! {
	a.pending_len = 0
	if event_id == 'archive.cancel' {
		a.cancel()
		return
	}
	if a.operation != .idle { return }
	if event_id.starts_with(jump_open_prefix) {
		path := unsafe { tos(event_id.str + jump_open_prefix.len, event_id.len - jump_open_prefix.len) }
		if archive_absolute_valid(path) && path.len <= archive_path_limit {
			archive_set_field(mut a.archive_input, path)
			a.browse_archive()
		} else {
			a.status_key = 'archive.invalid_path'
		}
		return
	}
	match event_id {
		'archive.path' { a.focus_field(0) }
		'archive.destination' { a.focus_field(1) }
		'archive.source' { a.focus_field(2) }
		'archive.output' { a.focus_field(3) }
		'archive.browse' { a.browse_archive() }
		'archive.extract' { a.extract_archive() }
		'archive.create' { a.create_archive() }
		'archive.up' {
			a.scroll -= a.page_rows
			a.clamp_scroll()
		}
		'archive.down' {
			a.scroll += a.page_rows
			a.clamp_scroll()
		}
		else {}
	}
}

fn (mut a ArchiveApp) clamp_scroll() {
	maximum := if a.entries.len > a.page_rows { a.entries.len - a.page_rows } else { 0 }
	if a.scroll < 0 { a.scroll = 0 }
	if a.scroll > maximum { a.scroll = maximum }
}

fn (mut a ArchiveApp) edit_character(character string) {
	match a.focus {
		0 {
			console_edit_character(mut a.archive_input, character, archive_path_limit, a.select_all)
		}
		1 {
			console_edit_character(mut a.extract_input, character, archive_path_limit, a.select_all)
		}
		2 {
			console_edit_character(mut a.source_input, character, archive_path_limit, a.select_all)
		}
		3 {
			console_edit_character(mut a.output_input, character, archive_path_limit, a.select_all)
		}
		else { return }
	}
	a.select_all = false
}

fn (mut a ArchiveApp) key_input(input string) {
	if a.operation != .idle {
		if input == '\x1b' { a.cancel() }
		return
	}
	match input {
		'\x1b[A' {
			a.scroll--
			a.clamp_scroll()
			return
		}
		'\x1b[B' {
			a.scroll++
			a.clamp_scroll()
			return
		}
		'\x1b[5~' {
			a.scroll -= a.page_rows
			a.clamp_scroll()
			return
		}
		'\x1b[6~' {
			a.scroll += a.page_rows
			a.clamp_scroll()
			return
		}
		'\x1b[H', '\x1b[1~' {
			a.scroll = 0
			return
		}
		'\x1b[F', '\x1b[4~' {
			a.scroll = a.entries.len
			a.clamp_scroll()
			return
		}
		else {}
	}
	if input.len > 1 && input[0] == 0x1b {
		a.pending_len = 0
		return
	}
	for byte in input {
		if a.pending_len > 0 {
			if editor_utf8_follows(a.pending[0], a.pending_len, byte) {
				a.pending[a.pending_len] = byte
				a.pending_len++
				if a.pending_len == editor_utf8_length(a.pending[0]) {
					a.edit_character(unsafe { tos(&a.pending[0], a.pending_len) })
					a.pending_len = 0
				}
				continue
			}
			a.pending_len = 0
		}
		match byte {
			0x1b {
				a.focus = -1
				a.select_all = false
			}
			`\t` { a.focus_field((a.focus + 1) % 4) }
			`\r`, `\n` {
				if a.focus == 0 {
					a.browse_archive()
				} else if a.focus == 1 {
					a.extract_archive()
				} else if a.focus >= 2 {
					a.create_archive()
				}
			}
			0x01 { a.select_all = true }
			0x7f, 0x08 {
				match a.focus {
					0 { console_backspace(mut a.archive_input, a.select_all) }
					1 { console_backspace(mut a.extract_input, a.select_all) }
					2 { console_backspace(mut a.source_input, a.select_all) }
					3 { console_backspace(mut a.output_input, a.select_all) }
					else {}
				}
				a.select_all = false
			}
			else {
				if byte >= 0x20 && byte < 0x7f {
					a.edit_character(unsafe { tos(&byte, 1) })
				} else if editor_utf8_length(byte) > 1 {
					a.pending[0] = byte
					a.pending_len = 1
				}
			}
		}
	}
}

fn (mut a ArchiveApp) paste_input(text string) {
	if a.operation != .idle { return }
	a.pending_len = 0
	match a.focus {
		0 { console_paste_field(mut a.archive_input, text, archive_path_limit, a.select_all) }
		1 { console_paste_field(mut a.extract_input, text, archive_path_limit, a.select_all) }
		2 { console_paste_field(mut a.source_input, text, archive_path_limit, a.select_all) }
		3 { console_paste_field(mut a.output_input, text, archive_path_limit, a.select_all) }
		else { return }
	}
	a.select_all = false
}

fn archive_button(id string, x int, y int, width int, active bool) ui2.Element {
	return console_button(id, id, x, y, width, active)
}

fn archive_label(key string, x int, y int, width int) ui2.Element {
	return ui2.label('', tr(key), ui2.rect(f64(x), f64(y), f64(width), 28),
		ui2.TextStyle{ color: body_muted, size: 12 })
}

fn (mut a ArchiveApp) build(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)
	footer := height - 202
	a.page_rows = if footer > 140 { (footer - 136) / 22 } else { 1 }
	a.clamp_scroll()
	mut children := frame_elements(a.page_rows * 2 + 24)
	children << archive_label('archive.subtitle', 14, 8, width - 28)
	children << archive_label('archive.path_label', 14, 44, 100)
	children << console_field('archive.path', editor_bytes_text(a.archive_input), 116, 42, width - 216, a.focus == 0)
	children << archive_button('archive.browse', width - 92, 43, 78, false)
	children << archive_label('archive.destination_label', 14, 84, 100)
	children << console_field('archive.destination', editor_bytes_text(a.extract_input), 116, 82, width - 216, a.focus == 1)
	children << archive_button('archive.extract', width - 92, 83, 78, false)
	if a.entries.len == 0 {
		children << archive_label('archive.empty', 18, 138, width - 36)
	} else {
		for row in 0 .. a.page_rows {
			index := a.scroll + row
			if index >= a.entries.len { break }
			entry := a.entries[index]
			children << ui2.label('', entry.name, ui2.rect(18, f64(136 + row * 22), f64(width - 170), 22),
				ui2.TextStyle{ color: body_text, size: 12 })
			children << ui2.label('', if entry.directory {
				tr('archive.directory')
			} else {
				entry.size_text
			},
				ui2.rect(f64(width - 145), f64(136 + row * 22), 127, 22),
				ui2.TextStyle{ color: body_muted, size: 12, align: .right })
		}
	}
	children << archive_button('archive.up', 14, footer, 76, false)
	children << archive_button('archive.down', 98, footer, 76, false)
	children << archive_button('archive.cancel', 190, footer, 88, a.operation != .idle)
	children << ui2.label('', a.progress_text, ui2.rect(298, f64(footer), f64(width - 312), 28),
		ui2.TextStyle{ color: body_muted, size: 12 })
	children << archive_label('archive.source_label', 14, footer + 46, 100)
	children << console_field('archive.source', editor_bytes_text(a.source_input), 116, footer + 44, width - 130, a.focus == 2)
	children << archive_label('archive.output_label', 14, footer + 86, 100)
	children << console_field('archive.output', editor_bytes_text(a.output_input), 116, footer + 84, width - 248, a.focus == 3)
	children << archive_button('archive.create', width - 124, footer + 85, 110, false)
	children << ui2.label('', tr(a.status_key), ui2.rect(14, f64(footer + 126), f64(width - 28), 40),
		ui2.TextStyle{ color: body_muted, size: 12, lines: 2 })
	children << ui2.label('', tr('archive.limits'), ui2.rect(14, f64(footer + 170), f64(width - 28), 24),
		ui2.TextStyle{ color: body_muted, size: 11 })
	return ui2.screen(app_surface, children)
}
