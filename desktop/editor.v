// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// A small, real text editor for Vinix.
//
// It edits plain ASCII files in memory and uses the same whole-file POSIX
// boundary as the file browser. Vinix has no file picker yet, so the path in
// the toolbar is itself editable: click it, type a path, then Open or Save.
// Clicking the page returns the keyboard to the document. Ctrl-N, Ctrl-O and
// Ctrl-S work while the editor is focused.
module main

import ui2

const editor_default_path = '/root/notes.txt'
const editor_max_file_size = 64 * 1024
const editor_max_path = 512

const editor_action_new = 'editor.new'
const editor_action_open = 'editor.open'
const editor_action_save = 'editor.save'
const editor_action_path = 'editor.path'
const editor_action_document = 'editor.document'

const editor_toolbar_height = 44
const editor_status_height = 24
const editor_row_height = 18
const editor_padding = 10
// The baked 13 px monospace face advances by eight logical pixels.
const editor_character_width = 8

enum EditorFocus {
	document
	path
}

struct TextEditorApp {
mut:
	text         []u8
	path         []u8
	status       []u8
	cursor       int
	focus        EditorFocus = .document
	scroll       int
	visible_rows int = 1
	modified     bool
}

fn open_editor(mut _ Desktop) !HostedApp {
	mut app := &TextEditorApp{}
	app.set_path(editor_default_path)
	app.set_status('New document')
	return app
}

// editor_bytes_text lends an array to the element tree for the duration of
// this frame. The renderer consumes the tree before the application can be
// edited again, so no copy (and no allocation every redraw) is needed.
fn editor_bytes_text(bytes []u8) string {
	if bytes.len == 0 {
		return ''
	}
	return unsafe { tos(bytes.data, bytes.len) }
}

fn editor_slice_text(bytes []u8, start int, length int) string {
	if length <= 0 {
		return ''
	}
	return unsafe { tos(&u8(bytes.data) + start, length) }
}

fn editor_append(mut destination []u8, text string) {
	for ch in text {
		destination << u8(ch)
	}
}

fn (mut a TextEditorApp) set_path(path string) {
	a.path.clear()
	editor_append(mut a.path, path)
}

fn (mut a TextEditorApp) set_status(status string) {
	a.status.clear()
	editor_append(mut a.status, status)
}

fn (mut a TextEditorApp) set_file_status(prefix string) {
	a.status.clear()
	editor_append(mut a.status, prefix)
	if a.path.len > 0 {
		a.status << ` `
		a.status << a.path
	}
}

fn (mut a TextEditorApp) new_document() {
	a.text.clear()
	a.cursor = 0
	a.scroll = 0
	a.modified = false
	a.focus = .document
	a.set_path(editor_default_path)
	a.set_status('New document')
}

fn (mut a TextEditorApp) open_document() {
	if a.path.len == 0 {
		a.set_status('Enter a path first')
		return
	}
	path := editor_bytes_text(a.path)
	info := desktop_stat(path) or {
		a.set_file_status('Cannot open')
		return
	}
	if info.is_dir {
		a.set_file_status('Path is a directory:')
		return
	}
	if info.size > editor_max_file_size {
		a.set_status('File is larger than 64 KB')
		return
	}

	mut next := []u8{len: int(info.size)}
	got := if next.len == 0 { i64(0) } else { desktop_read_file(path, next.data, info.size) }
	if got < 0 {
		unsafe { next.free() }
		a.set_file_status('Cannot read')
		return
	}
	if got < i64(next.len) {
		next.trim(int(got))
	}
	unsafe { a.text.free() }
	a.text = next
	a.cursor = a.text.len
	a.scroll = 0
	a.modified = false
	a.focus = .document
	a.set_file_status('Opened')
}

fn (mut a TextEditorApp) save_document() {
	if a.path.len == 0 {
		a.set_status('Enter a path first')
		return
	}
	path := editor_bytes_text(a.path)
	mut data := voidptr(unsafe { nil })
	if a.text.len > 0 {
		data = voidptr(a.text.data)
	}
	if !desktop_write_file(path, data, u64(a.text.len)) {
		a.set_file_status('Cannot save')
		return
	}
	a.modified = false
	a.set_file_status('Saved')
}

fn (a &TextEditorApp) line_start(position int) int {
	mut start := if position < a.text.len { position } else { a.text.len }
	for start > 0 && a.text[start - 1] != `\n` {
		start--
	}
	return start
}

fn (a &TextEditorApp) line_end(position int) int {
	mut end := if position < a.text.len { position } else { a.text.len }
	for end < a.text.len && a.text[end] != `\n` {
		end++
	}
	return end
}

fn (a &TextEditorApp) cursor_line() int {
	mut line := 0
	limit := if a.cursor < a.text.len { a.cursor } else { a.text.len }
	for i := 0; i < limit; i++ {
		if a.text[i] == `\n` {
			line++
		}
	}
	return line
}

fn (a &TextEditorApp) offset_for_line(wanted int) int {
	if wanted <= 0 {
		return 0
	}
	mut line := 0
	for i, ch in a.text {
		if ch == `\n` {
			line++
			if line == wanted {
				return i + 1
			}
		}
	}
	return a.text.len
}

fn (mut a TextEditorApp) move_vertical(delta int) {
	start := a.line_start(a.cursor)
	column := a.cursor - start
	if delta < 0 {
		if start == 0 {
			return
		}
		target_end := start - 1
		target_start := a.line_start(target_end)
		target_length := target_end - target_start
		a.cursor = target_start + if column < target_length { column } else { target_length }
		return
	}
	end := a.line_end(a.cursor)
	if end >= a.text.len {
		return
	}
	target_start := end + 1
	target_end := a.line_end(target_start)
	target_length := target_end - target_start
	a.cursor = target_start + if column < target_length { column } else { target_length }
}

fn (mut a TextEditorApp) insert(ch u8) {
	if a.text.len >= editor_max_file_size {
		a.set_status('Document limit is 64 KB')
		return
	}
	if a.cursor >= a.text.len {
		a.text << ch
	} else {
		a.text.insert(a.cursor, ch)
	}
	a.cursor++
	a.modified = true
	a.set_status('Unsaved changes')
}

fn (mut a TextEditorApp) edit_path(ch u8) {
	match ch {
		8, 127 {
			if a.path.len > 0 {
				a.path.delete_last()
			}
		}
		`\n`, `\r` { a.open_document() }
		else {
			if ch >= 0x20 && ch < 0x7f && a.path.len < editor_max_path {
				a.path << ch
			}
		}
	}
}

// document_key handles one ordinary byte. Escape sequences are consumed by
// key_input before they reach here.
fn (mut a TextEditorApp) document_key(ch u8) {
	match ch {
		8, 127 {
			if a.cursor > 0 {
				a.text.delete(a.cursor - 1)
				a.cursor--
				a.modified = true
				a.set_status('Unsaved changes')
			}
		}
		`\n`, `\r` { a.insert(`\n`) }
		`\t` {
			for _ in 0 .. 4 {
				a.insert(` `)
			}
		}
		else {
			if ch >= 0x20 && ch < 0x7f {
				a.insert(ch)
			}
		}
	}
}

fn (mut a TextEditorApp) key_input(input string) {
	mut i := 0
	for i < input.len {
		ch := input[i]
		// Editor-wide shortcuts remain available because focused applications
		// receive control bytes before the desktop considers its own shortcuts.
		match ch {
			0x0e {
				a.new_document()
				i++
				continue
			}
			0x0f {
				a.open_document()
				i++
				continue
			}
			0x13 {
				a.save_document()
				i++
				continue
			}
			else {}
		}

		if a.focus == .path {
			a.edit_path(ch)
			i++
			continue
		}

		if ch == 0x1b && i + 2 < input.len && input[i + 1] == `[` {
			code := input[i + 2]
			match code {
				`A` { a.move_vertical(-1) }
				`B` { a.move_vertical(1) }
				`C` {
					if a.cursor < a.text.len {
						a.cursor++
					}
				}
				`D` {
					if a.cursor > 0 {
						a.cursor--
					}
				}
				`H` {
					a.cursor = a.line_start(a.cursor)
				}
				`F` {
					a.cursor = a.line_end(a.cursor)
				}
				`3` {
					if i + 3 < input.len && input[i + 3] == `~` {
						if a.cursor < a.text.len {
							a.text.delete(a.cursor)
							a.modified = true
							a.set_status('Unsaved changes')
						}
						i += 4
						continue
					}
				}
				else {}
			}
			i += 3
			continue
		}

		a.document_key(ch)
		i++
	}
	a.follow_cursor()
}

fn (mut a TextEditorApp) follow_cursor() {
	line := a.cursor_line()
	if line < a.scroll {
		a.scroll = line
	} else if line >= a.scroll + a.visible_rows {
		a.scroll = line - a.visible_rows + 1
	}
	if a.scroll < 0 {
		a.scroll = 0
	}
}

fn editor_toolbar_button(id string, text string, x int, width int) ui2.Element {
	return ui2.button(id, text, ui2.rect(f64(x), 9, f64(width), 26), ui2.BoxStyle{
		bg: editor_button
		radius: 5
	}, ui2.TextStyle{
		color: app_on_accent
		size: 12
		align: .center
	})
}

fn (mut a TextEditorApp) build(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)
	mut children := frame_elements(8)

	button_width := 54
	children << editor_toolbar_button(editor_action_new, 'New', editor_padding, button_width)
	children << editor_toolbar_button(editor_action_open, 'Open', editor_padding + button_width + 6, button_width)
	children << editor_toolbar_button(editor_action_save, 'Save', editor_padding + 2 * (button_width + 6), button_width)

	path_x := editor_padding + 3 * (button_width + 6) + 4
	path_width := if width - path_x - editor_padding > 40 {
		width - path_x - editor_padding
	} else {
		40
	}
	children << ui2.clickable_view(editor_action_path, ui2.rect(f64(path_x), 8, f64(path_width), 28), ui2.BoxStyle{
		bg: if a.focus == .path { editor_path_focus } else { body_panel }
		radius: 5
	}, frame_child(ui2.label('', editor_bytes_text(a.path), ui2.rect(0, 0, f64(path_width), 28), ui2.TextStyle{
		color: body_text
		font_family: 'mono'
		size: 13
	})))
	children << ui2.view('', ui2.rect(0, f64(editor_toolbar_height - 1), f64(width), 1), ui2.BoxStyle{
		bg: body_rule
	}, [])

	document_height := if height > editor_toolbar_height + editor_status_height {
		height - editor_toolbar_height - editor_status_height
	} else {
		editor_row_height
	}
	a.visible_rows = if document_height > 2 * editor_padding {
		(document_height - 2 * editor_padding) / editor_row_height
	} else {
		1
	}
	a.follow_cursor()

	mut lines := frame_elements(a.visible_rows * 2)
	mut position := a.offset_for_line(a.scroll)
	for row := 0; row < a.visible_rows; row++ {
		if position > a.text.len {
			break
		}
		end := a.line_end(position)
		lines << ui2.label('', editor_slice_text(a.text, position, end - position), ui2.rect(f64(editor_padding), f64(editor_padding + row * editor_row_height), f64(width - 2 * editor_padding), f64(editor_row_height)), ui2.TextStyle{
			color: body_text
			font_family: 'mono'
			size: 13
		})
		if a.cursor >= position && a.cursor <= end {
			cursor_x := editor_padding + (a.cursor - position) * editor_character_width
			lines << ui2.view('', ui2.rect(f64(cursor_x), f64(editor_padding + row * editor_row_height + 2), 2, f64(editor_row_height - 4)), ui2.BoxStyle{
				bg: if a.focus == .document { editor_cursor } else { body_muted }
			}, [])
		}
		if end >= a.text.len {
			break
		}
		position = end + 1
	}
	children << ui2.clickable_view(editor_action_document, ui2.rect(0, f64(editor_toolbar_height), f64(width), f64(document_height)), ui2.BoxStyle{
		bg: app_surface
	}, lines)

	status_y := height - editor_status_height
	children << ui2.view('', ui2.rect(0, f64(status_y), f64(width), 1), ui2.BoxStyle{
		bg: body_rule
	}, [])
	children << ui2.label('', editor_bytes_text(a.status), ui2.rect(f64(editor_padding), f64(status_y), f64(width - 2 * editor_padding), f64(editor_status_height)), ui2.TextStyle{
		color: if a.modified { editor_modified } else { body_muted }
		size: 11
	})

	return ui2.screen(app_surface, children)
}

fn (mut a TextEditorApp) handle(event_id string) ! {
	match event_id {
		editor_action_new { a.new_document() }
		editor_action_open { a.open_document() }
		editor_action_save { a.save_document() }
		editor_action_path {
			a.focus = .path
		}
		editor_action_document {
			a.focus = .document
		}
		else {}
	}
}
