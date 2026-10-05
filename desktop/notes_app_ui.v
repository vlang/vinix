// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn (mut a NotesApp) rewrap() {
	a.wrap_count = 1
	a.wrap_starts[0] = 0
	mut at := 0
	mut column := 0
	for at < a.body.len {
		newline := a.body[at] == `\n`
		at += editor_char_length(a.body, at)
		column++
		if newline || column >= a.text_columns {
			a.wrap_starts[a.wrap_count] = at
			a.wrap_count++
			column = 0
		}
	}
}

fn (a &NotesApp) wrapped_end(row int) int {
	mut end := if row + 1 < a.wrap_count { a.wrap_starts[row + 1] } else { a.body.len }
	if end > a.wrap_starts[row] && a.body[end - 1] == `\n` { end-- }
	return end
}

fn (a &NotesApp) cursor_row() int {
	mut row := 0
	for row + 1 < a.wrap_count && a.wrap_starts[row + 1] <= a.cursor { row++ }
	return row
}

fn (mut a NotesApp) show_cursor() {
	a.rewrap()
	row := a.cursor_row()
	if row < a.body_scroll { a.body_scroll = row }
	if row >= a.body_scroll + a.text_rows { a.body_scroll = row - a.text_rows + 1 }
}

fn (mut a NotesApp) focus_field(field int) {
	a.focus = field
	a.pending_len = 0
	a.select_all = false
	a.delete_pending = false
}

fn (mut a NotesApp) handle(event_id string) ! {
	a.pending_len = 0
	if event_id.starts_with('notes.row.') {
		index := notes_number(console_borrow(event_id, 10, event_id.len)) or { return }
		if index < u64(a.count) { a.select_note(int(index)) }
		return
	}
	match event_id {
		'notes.search' { a.focus_field(0) }
		'notes.title' { a.focus_field(1) }
		'notes.body' { a.focus_field(2) }
		'notes.export_path' { a.focus_field(3) }
		'notes.new' { a.new_note() }
		'notes.save' { a.save() }
		'notes.refresh' { a.reload() }
		'notes.delete' { a.delete_note() }
		'notes.cancel_delete' {
			a.delete_pending = false
			a.status = if a.dirty { 'notes.unsaved' } else { 'notes.ready' }
		}
		'notes.previous' {
			a.list_scroll = if a.list_scroll >= a.page_rows {
				a.list_scroll - a.page_rows
			} else {
				0
			}
		}
		'notes.next' {
			if a.list_scroll + a.page_rows < a.matched { a.list_scroll += a.page_rows }
		}
		'notes.export' {
			if a.selected >= 0 {
				path := editor_bytes_text(a.export_path)
				a.export_status = if path == a.default_export {
					notes_export_at(a.home_fd, 'vinix-note.txt', editor_bytes_text(a.title), editor_bytes_text(a.body))
				} else {
					notes_export(path, editor_bytes_text(a.title), editor_bytes_text(a.body))
				}
			}
		}
		else {}
	}
}

fn (mut a NotesApp) insert_text(text string) {
	if a.focus == 0 || a.focus == 3 {
		if a.focus == 0 {
			console_edit_character(mut a.query, text, 256, a.select_all)
			a.refilter()
		} else {
			console_edit_character(mut a.export_path, text, 512, a.select_all)
			a.export_status = ''
		}
		a.select_all = false
		return
	}
	if a.selected < 0 || a.focus < 1 || a.focus > 2 { return }
	if a.focus == 1 {
		if text == '\n' || text == '\t' { return }
		if (if a.select_all { 0 } else { a.title.len }) + text.len > notes_title_limit {
			a.status = 'notes.limit'
			return
		}
		console_edit_character(mut a.title, text, notes_title_limit, a.select_all)
	} else {
		if (if a.select_all { 0 } else { a.body.len }) + text.len > notes_body_limit {
			a.status = 'notes.limit'
			return
		}
		if a.select_all {
			a.body.clear()
			a.cursor = 0
		}
		for ch in text {
			if a.cursor == a.body.len {
				a.body << ch
			} else {
				a.body.insert(a.cursor, unsafe { &ch })
			}
			a.cursor++
		}
	}
	a.select_all = false
	a.mark_dirty()
	a.refilter()
	a.show_cursor()
}

fn (mut a NotesApp) backspace(forward bool) {
	if a.focus == 0 {
		console_backspace(mut a.query, a.select_all)
		a.refilter()
	} else if a.focus == 3 {
		console_backspace(mut a.export_path, a.select_all)
		a.export_status = ''
	} else if a.selected >= 0 {
		if a.focus == 1 {
			console_backspace(mut a.title, a.select_all)
		} else if a.focus == 2 {
			if a.select_all {
				a.body.clear()
				a.cursor = 0
			} else if forward && a.cursor < a.body.len {
				a.body.delete_many(a.cursor, editor_char_length(a.body, a.cursor))
			} else if !forward && a.cursor > 0 {
				start := editor_char_before(a.body, a.cursor)
				a.body.delete_many(start, a.cursor - start)
				a.cursor = start
			}
		} else {
			return
		}
		a.mark_dirty()
		a.refilter()
		a.show_cursor()
	}
	a.select_all = false
}

fn (mut a NotesApp) key_input(input string) {
	if input.len > 1 && input[0] == 0x1b {
		a.pending_len = 0
		a.select_all = false
		if a.focus == 2 && a.selected >= 0 {
			row := a.cursor_row()
			column := editor_columns(a.body, a.wrap_starts[row], a.cursor)
			match input {
				'\x1b[D' { a.cursor = editor_char_before(a.body, a.cursor) }
				'\x1b[C' {
					if a.cursor < a.body.len { a.cursor += editor_char_length(a.body, a.cursor) }
				}
				'\x1b[H', '\x1b[1~' { a.cursor = a.wrap_starts[row] }
				'\x1b[F', '\x1b[4~' { a.cursor = a.wrapped_end(row) }
				'\x1b[A' {
					if row > 0 {
						a.cursor = editor_column_offset(a.body, a.wrap_starts[row - 1], a.wrapped_end(row - 1), column)
					}
				}
				'\x1b[B' {
					if row + 1 < a.wrap_count {
						a.cursor = editor_column_offset(a.body, a.wrap_starts[row + 1], a.wrapped_end(row + 1), column)
					}
				}
				'\x1b[5~' {
					target := if row > a.text_rows { row - a.text_rows } else { 0 }
					a.cursor = a.wrap_starts[target]
				}
				'\x1b[6~' {
					target := if row + a.text_rows < a.wrap_count {
						row + a.text_rows
					} else {
						a.wrap_count - 1
					}
					a.cursor = a.wrap_starts[target]
				}
				'\x1b[3~' { a.backspace(true) }
				else {}
			}
			a.show_cursor()
		}
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
		if byte == 0x01 {
			a.select_all = true
		} else if byte == 0x13 {
			a.save()
		} else if byte == 0x0e {
			a.new_note()
		} else if byte == 0x1b {
			a.select_all = false
			a.delete_pending = false
		} else if byte == 0x7f || byte == 8 {
			a.backspace(false)
		} else if byte == `\r` || byte == `\n` {
			if a.focus == 2 {
				a.insert_text('\n')
			} else if a.focus == 1 {
				a.focus_field(2)
			}
		} else if byte == `\t` {
			a.focus_field((a.focus + 1) % 4)
		} else if byte >= 0x20 && byte < 0x7f {
			a.insert_text(unsafe { tos(&byte, 1) })
		} else if editor_utf8_length(byte) > 1 {
			a.pending[0] = byte
			a.pending_len = 1
		}
	}
}

fn (mut a NotesApp) paste_input(text string) {
	a.pending_len = 0
	// A paste is one bounded UTF-8 edit. Reject malformed/control text as a
	// whole, preserving a selected draft if the replacement is invalid.
	if !notes_valid_text(text, if a.focus == 2 { notes_body_limit } else { 512 }, a.focus == 2) {
		a.status = 'notes.invalid_text'
		return
	}
	a.insert_text(text)
}

fn (a &NotesApp) pointer_input_enabled() bool { return true }

fn (a &NotesApp) pointer_moves_matter() bool { return false }

fn (mut a NotesApp) pointer_event(phase AppPointerPhase, button AppPointerButton, scroll int,
	x int, y int, _ int, height int) {
	if phase == .scroll {
		if x < 230 {
			a.list_scroll -= scroll * 3
			if a.list_scroll < 0 { a.list_scroll = 0 }
			if a.list_scroll >= a.matched {
				a.list_scroll = if a.matched > 0 { a.matched - 1 } else { 0 }
			}
		} else {
			a.body_scroll -= scroll * 3
			if a.body_scroll < 0 { a.body_scroll = 0 }
			if a.body_scroll >= a.wrap_count { a.body_scroll = a.wrap_count - 1 }
		}
	} else if phase == .down && button == .left && x >= 248 && y >= 101 && y < height - 118 && a.selected >= 0 {
		row := a.body_scroll + (y - 101) / 18
		if row < a.wrap_count {
			a.focus_field(2)
			a.cursor = editor_column_offset(a.body, a.wrap_starts[row], a.wrapped_end(row), (x - 248) / 8)
		}
	}
}

fn (mut a NotesApp) build(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)
	a.page_rows = if height > 250 { (height - 213) / 30 } else { 1 }
	a.text_rows = if height > 240 { (height - 225) / 18 } else { 1 }
	a.text_columns = if width > 296 { (width - 276) / 8 } else { 1 }
	a.rewrap()
	mut children := frame_elements(24 + a.page_rows + a.text_rows)
	for index, key in ['notes.new', 'notes.save', 'notes.refresh', 'notes.delete']! {
		children << console_button(key, key, 12 + index * 112, 10, 104, a.delete_pending && index == 3)
	}
	if a.delete_pending {
		children << console_button('notes.cancel_delete', 'notes.cancel_delete', 460, 10, 130, false)
	}
	children << console_field('notes.search', editor_bytes_text(a.query), 12, 58, 216, a.focus == 0)
	children << ui2.label('', tr('notes.search_hint'), ui2.rect(12, 91, 216, 18), ui2.TextStyle{ size: 11, color: body_muted })
	for row in 0 .. a.page_rows {
		match_index := a.list_scroll + row
		if match_index >= a.matched { break }
		index := a.matches[match_index]
		title := if index == a.selected { editor_bytes_text(a.title) } else { a.items[index].title }
		children << ui2.button(a.actions[index], title, ui2.rect(12, f64(114 + row * 30), 216, 26),
			ui2.BoxStyle{ bg: if index == a.selected { app_accent } else { body_panel }, radius: 4 },
			ui2.TextStyle{ color: if index == a.selected { app_on_accent } else { body_text }, size: 12 })
	}
	if a.matched == 0 {
		children << ui2.label('', tr('notes.empty'), ui2.rect(12, 118, 216, 50), ui2.TextStyle{ size: 12, color: body_muted })
	}
	children << console_button('notes.previous', 'notes.previous', 12, height - 75, 104, false)
	children << console_button('notes.next', 'notes.next', 124, height - 75, 104, false)
	children << console_field('notes.title', editor_bytes_text(a.title), 240, 58, width - 252, a.focus == 1)
	mut lines := frame_elements(a.text_rows + 1)
	for visible in 0 .. a.text_rows {
		row := a.body_scroll + visible
		if row >= a.wrap_count { break }
		start := a.wrap_starts[row]
		end := a.wrapped_end(row)
		lines << ui2.label('', editor_slice_text(a.body, start, end - start), ui2.rect(8, f64(visible * 18 + 6), f64(width - 276), 18), ui2.TextStyle{ color: body_text, size: 13, font_family: 'mono' })
	}
	if a.focus == 2 && a.selected >= 0 {
		row := a.cursor_row()
		if row >= a.body_scroll && row < a.body_scroll + a.text_rows {
			column := editor_columns(a.body, a.wrap_starts[row], a.cursor)
			lines << ui2.view('', ui2.rect(f64(8 + column * 8), f64(6 + (row - a.body_scroll) * 18), 1, 17), ui2.BoxStyle{ bg: app_accent }, [])
		}
	}
	children << ui2.clickable_view('notes.body', ui2.rect(240, 95, f64(width - 252), f64(height - 213)), ui2.BoxStyle{ bg: body_panel, radius: 4 }, lines)
	children << console_field('notes.export_path', editor_bytes_text(a.export_path), 240, height - 108, width - 360, a.focus == 3)
	children << console_button('notes.export', 'notes.export', width - 112, height - 108, 100, false)
	children << ui2.label('', tr(if a.export_status.len > 0 { a.export_status } else { a.status }), ui2.rect(240, f64(height - 73), f64(width - 252), 28), ui2.TextStyle{
		color: if a.dirty || a.read_failed {
			app_accent
		} else {
			body_text
		}
		size:  12
	})
	children << ui2.label('', tr('notes.hint'), ui2.rect(12, f64(height - 32), f64(width - 24), 24), ui2.TextStyle{ color: body_muted, size: 11 })
	return ui2.screen(app_surface, children)
}
