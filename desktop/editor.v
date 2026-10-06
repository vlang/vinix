// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// A small, real text editor for Vinix.
//
// It edits UTF-8 text files in memory and uses the same whole-file POSIX
// boundary as the file browser. The cursor moves by whole characters. A byte
// that is not valid UTF-8 is kept as it is and counts as one character, so
// saving writes back exactly the bytes that were opened.
//
// Vinix has no file picker yet, so the path in the toolbar is itself
// editable: click it, type a path, then Open or Save. Clicking the page
// returns the keyboard to the document. Ctrl-N, Ctrl-O and Ctrl-S work while
// the editor is focused.
module main

import ui2

const editor_default_path = '/root/notes.txt'
const editor_max_file_size = 64 * 1024
const editor_max_path = 512
// The document limit bounds each snapshot, and history never holds more than
// 32 snapshots across both stacks (at most 2 MB of document bytes).
const editor_history_limit = 32
const editor_find_height = 76

const editor_action_new = 'editor.new'
const editor_action_open = 'editor.open'
const editor_action_save = 'editor.save'
const editor_action_path = 'editor.path'
const editor_action_document = 'editor.document'
const editor_action_undo = 'editor.undo'
const editor_action_redo = 'editor.redo'
const editor_action_find = 'editor.find'
const editor_action_query = 'editor.find.query'
const editor_action_replacement = 'editor.find.replacement'
const editor_action_next = 'editor.find.next'
const editor_action_previous = 'editor.find.previous'
const editor_action_replace = 'editor.replace'
const editor_action_replace_all = 'editor.replace.all'
const editor_action_find_close = 'editor.find.close'

const editor_toolbar_height = 80
const editor_status_height = 24
const editor_row_height = 18
const editor_padding = 10
// The baked 13 px monospace face advances by eight logical pixels.
const editor_character_width = 8

enum EditorFocus {
	document
	path
	query
	replacement
	save_as
}

struct EditorSnapshot {
	text     []u8
	cursor   int
	revision u64
	selection_anchor int = -1
}

struct TextEditorApp {
mut:
	text         []u8
	path         []u8
	status       []u8
	// The status line's translation key, whether the path follows it, and the
	// language it was written in, so that it follows a change of language.
	status_key        string
	status_path       bool
	status_language   DesktopLanguage
	cursor            int
	selection_anchor  int = -1
	selection_dragging bool
	selection_marking bool
	copy_text []u8
	copy_sequence u32
	copy_queued bool
	copy_waiting bool
	copy_cut bool
	copy_start int
	copy_end int
	copy_revision u64
	key_csi_active bool
	key_csi_len int
	key_csi_overflow bool
	key_csi [16]u8
	key_csi_ms u64
	focus             EditorFocus = .document
	scroll            int
	visible_rows      int = 1
	modified          bool
	undo_history      []EditorSnapshot
	redo_history      []EditorSnapshot
	revision          u64
	next_revision     u64
	document_has_save bool
	saved_revision    u64
	// One delivered typing run is one edit; navigation splits that run.
	edit_group    bool
	edit_recorded bool
	find_open     bool
	query         []u8
	replacement   []u8
	default_path  []u8
	document_path []u8
	pending_path  []u8
	pending_action EditorPendingAction
	discard_pending bool
	discard_close bool
	save_as_open bool
	save_as_path []u8
	match_start   int = -1
	match_end     int = -1
	// pending gathers a multibyte character until its last byte arrives. The
	// keyboard is read 64 bytes at a time, so that can be the next key_input.
	pending     [4]u8
	pending_len int
}

fn open_editor(mut _ Desktop) !NativeApp {
	mut app := &TextEditorApp{}
	home := if desktop_user_home.len > 0 { desktop_user_home } else { desktop_home }
	editor_append(mut app.default_path, home)
	if app.default_path[app.default_path.len - 1] != `/` { editor_append(mut app.default_path, '/') }
	editor_append(mut app.default_path, 'notes.txt')
	editor_append(mut app.document_path, editor_bytes_text(app.default_path))
	app.set_path(editor_bytes_text(app.default_path))
	app.set_status('editor.status.new_document')
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
	unsafe { destination.flags |= .noslices }
	for ch in text {
		destination << u8(ch)
	}
}

// editor_utf8_length is the length a UTF-8 lead byte announces, or 0 for a
// byte that cannot start a character: a continuation, an overlong C0/C1 lead,
// or F5..FF, which could only encode past U+10FFFF.
fn editor_utf8_length(lead u8) int {
	if lead < 0x80 {
		return 1
	}
	if lead >= 0xc2 && lead <= 0xdf {
		return 2
	}
	if lead >= 0xe0 && lead <= 0xef {
		return 3
	}
	if lead >= 0xf0 && lead <= 0xf4 {
		return 4
	}
	return 0
}

// editor_utf8_follows reports whether `next` may be byte `index` of the
// character `lead` starts. Narrowing the second byte after E0, ED, F0 and F4
// rejects overlong forms, UTF-16 surrogates and code points past U+10FFFF.
fn editor_utf8_follows(lead u8, index int, next u8) bool {
	if next < 0x80 || next > 0xbf {
		return false
	}
	if index != 1 {
		return true
	}
	return match lead {
		0xe0 { next >= 0xa0 }
		0xed { next <= 0x9f }
		0xf0 { next >= 0x90 }
		0xf4 { next <= 0x8f }
		else { true }
	}
}

// editor_char_length measures the character at `position`: a whole valid
// UTF-8 sequence, or one byte where the text is not valid UTF-8. A newline is
// never part of a sequence, so a character does not cross a line end.
fn editor_char_length(bytes []u8, position int) int {
	if position >= bytes.len {
		return 0
	}
	lead := bytes[position]
	length := editor_utf8_length(lead)
	if length <= 1 || position + length > bytes.len {
		return 1
	}
	for k := 1; k < length; k++ {
		if !editor_utf8_follows(lead, k, bytes[position + k]) {
			return 1
		}
	}
	return length
}

// editor_char_before steps back over one character. A lead byte is never a
// continuation, so a valid sequence ending at `position` is the character a
// scan forward from the line start would also find there.
fn editor_char_before(bytes []u8, position int) int {
	if position <= 0 {
		return 0
	}
	for length := 2; length <= 4 && length <= position; length++ {
		if editor_char_length(bytes, position - length) == length {
			return position - length
		}
	}
	return position - 1
}

// editor_columns counts the characters from `start` up to `position`. The
// face is monospace, so this is also the on-screen column.
fn editor_columns(bytes []u8, start int, position int) int {
	mut columns := 0
	mut at := start
	for at < position {
		at += editor_char_length(bytes, at)
		columns++
	}
	return columns
}

// editor_column_offset walks `columns` characters from `start`, stopping at
// `end` when the line is shorter.
fn editor_column_offset(bytes []u8, start int, end int, columns int) int {
	mut at := start
	for n := 0; n < columns && at < end; n++ {
		at += editor_char_length(bytes, at)
	}
	return at
}

fn (mut a TextEditorApp) set_path(path string) {
	a.path.clear()
	editor_append(mut a.path, path)
}

// set_status shows the translation of key on the status line.
fn (mut a TextEditorApp) set_status(key string) {
	a.status_key = key
	a.status_path = false
	a.status_language = desktop_language
	a.status.clear()
	editor_append(mut a.status, tr(key))
}

// set_file_status shows the translation of key followed by the path.
fn (mut a TextEditorApp) set_file_status(key string) {
	a.status_key = key
	a.status_path = true
	a.status_language = desktop_language
	a.status.clear()
	editor_append(mut a.status, tr(key))
	if a.path.len > 0 {
		a.status << ` `
		a.status << a.path
	}
}

// follow_language writes the status line again after a change of language.
fn (mut a TextEditorApp) follow_language() {
	if a.status_key.len == 0 || a.status_language == desktop_language {
		return
	}
	if a.status_path {
		a.set_file_status(a.status_key)
	} else {
		a.set_status(a.status_key)
	}
}

fn (mut a TextEditorApp) perform_new_document() {
	a.reset_history()
	a.text.clear()
	a.cursor = 0
	a.scroll = 0
	a.modified = false
	a.focus = .document
	path := if a.default_path.len > 0 { editor_bytes_text(a.default_path) } else { editor_default_path }
	a.set_path(path)
	a.document_path.clear()
	editor_append(mut a.document_path, path)
	a.set_status('editor.status.new_document')
}

fn (mut a TextEditorApp) perform_open_document() bool {
	if !editor_valid_save_path(editor_bytes_text(a.path)) {
		a.set_status('editor.workflow.invalid_path')
		return false
	}
	// Editable buffers may retain an older suffix after shortening. POSIX
	// needs a NUL-terminated copy, rather than the frame's borrowed view.
	path := editor_bytes_text(a.path).clone()
	defer { unsafe { path.free() } }
	info := desktop_stat(path) or {
		a.set_file_status('editor.status.cannot_open')
		return false
	}
	if info.is_dir {
		a.set_file_status('editor.status.is_directory')
		return false
	}
	if info.size > editor_max_file_size {
		a.set_status('editor.status.too_large')
		return false
	}

	mut next := []u8{len: int(info.size)}
	got := if next.len == 0 { i64(0) } else { desktop_read_file(path, next.data, info.size) }
	if got < 0 {
		unsafe { next.free() }
		a.set_file_status('editor.status.cannot_read')
		return false
	}
	if got < i64(next.len) {
		next.trim(int(got))
	}
	a.reset_history()
	unsafe { a.text.free() }
	a.text = next
	a.cursor = a.text.len
	a.scroll = 0
	a.modified = false
	a.document_has_save = true
	a.document_path.clear()
	editor_append(mut a.document_path, path)
	a.focus = .document
	a.set_file_status('editor.status.opened')
	record_recent_item('vinix-editor', path)
	return true
}

fn (mut a TextEditorApp) save_document() bool {
	a.discard_pending = false
	a.discard_close = false
	if !editor_valid_save_path(editor_bytes_text(a.path)) {
		a.set_status('editor.workflow.invalid_path')
		return false
	}
	path := editor_bytes_text(a.path).clone()
	defer { unsafe { path.free() } }
	mut data := voidptr(unsafe { nil })
	if a.text.len > 0 {
		data = voidptr(a.text.data)
	}
	if !desktop_write_file(path, data, u64(a.text.len)) {
		a.set_file_status('editor.status.cannot_save')
		return false
	}
	a.document_has_save = true
	a.saved_revision = a.revision
	a.modified = false
	a.document_path.clear()
	editor_append(mut a.document_path, path)
	a.set_file_status('editor.status.saved')
	record_recent_item('vinix-editor', path)
	a.complete_editor_action()
	return true
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

// move_vertical keeps the column in characters, so the cursor stays above or
// below the same glyph when the lines hold multibyte text.
fn (mut a TextEditorApp) move_vertical(delta int) {
	start := a.line_start(a.cursor)
	column := editor_columns(a.text, start, a.cursor)
	if delta < 0 {
		if start == 0 {
			return
		}
		target_end := start - 1
		target_start := a.line_start(target_end)
		a.cursor = editor_column_offset(a.text, target_start, target_end, column)
		return
	}
	end := a.line_end(a.cursor)
	if end >= a.text.len {
		return
	}
	target_start := end + 1
	target_end := a.line_end(target_start)
	a.cursor = editor_column_offset(a.text, target_start, target_end, column)
}

// settle_cursor moves the cursor back to the start of the character it is in.
// Deleting whatever sat between two stray bytes of a malformed file can join
// them into one valid sequence around the cursor, and only a scan from the
// line start knows where characters begin.
fn (mut a TextEditorApp) settle_cursor() {
	mut at := a.line_start(a.cursor)
	for at < a.cursor {
		next := at + editor_char_length(a.text, at)
		if next > a.cursor {
			a.cursor = at
			return
		}
		at = next
	}
}

// delete_char removes the character of `length` bytes at `start`.
fn (mut a TextEditorApp) delete_char(start int, length int) {
	a.record_edit()
	a.text.delete_many(start, length)
	a.cursor = start
	a.settle_cursor()
	a.modified = true
	a.set_status('editor.status.unsaved')
}

// insert_byte places one byte at the cursor. Every byte of a character goes in
// before anything else looks at the cursor, so it rests on a boundary.
fn (mut a TextEditorApp) insert_byte(ch u8) {
	// The element tree borrows text only until its frame is rendered. History
	// snapshots own clones, so growth can release the old document buffer.
	unsafe { a.text.flags |= .noslices }
	if a.cursor >= a.text.len {
		a.text << ch
	} else {
		a.text.insert(a.cursor, ch)
	}
	a.cursor++
}

fn (mut a TextEditorApp) insert(ch u8) {
	if !a.prepare_selection_insertion(1) { return }
	a.insert_byte(ch)
	a.modified = true
	a.set_status('editor.status.unsaved')
}

// type_pending gives the multibyte character gathered in `pending` to
// whichever field has the keyboard, whole or not at all.
fn (mut a TextEditorApp) type_pending() {
	length := a.pending_len
	a.pending_len = 0
	if a.focus != .document {
		a.append_field_character(length)
		return
	}
	if !a.prepare_selection_insertion(length) { return }
	for k := 0; k < length; k++ {
		a.insert_byte(a.pending[k])
	}
	a.modified = true
	a.set_status('editor.status.unsaved')
}

fn (mut a TextEditorApp) edit_path(ch u8) {
	if ch != `\r` && ch != `\n` { a.cancel_editor_choice() }
	unsafe { a.path.flags |= .noslices }
	match ch {
		8, 127 {
			if a.path.len > 0 {
				a.path.trim(editor_char_before(a.path, a.path.len))
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

// document_key handles one ASCII byte. Escape sequences and multibyte
// characters are consumed by key_input before they reach here.
fn (mut a TextEditorApp) document_key(ch u8) {
	match ch {
		8, 127 {
			if a.delete_selection() { return }
			if a.cursor > 0 {
				start := editor_char_before(a.text, a.cursor)
				a.delete_char(start, a.cursor - start)
			}
		}
		`\n`, `\r` { a.insert(`\n`) }
		`\t` {
			if !a.prepare_selection_insertion(4) { return }
			for _ in 0 .. 4 {
				a.insert_byte(` `)
			}
			a.modified = true
			a.set_status('editor.status.unsaved')
		}
		else {
			if ch >= 0x20 && ch < 0x7f {
				a.insert(ch)
			}
		}
	}
}

fn (mut a TextEditorApp) key_input(input string) {
	a.edit_group = true
	a.edit_recorded = false
	defer {
		a.edit_group = false
		a.edit_recorded = false
	}
	mut i := 0
	for i < input.len {
		ch := input[i]
		if a.key_csi_active && a.key_csi_len == -1 {
			if ch == `[` || ch == `O` {
				a.key_csi_len = 0
				i++
				continue
			}
			// Resolve a bare Escape, then process the following ordinary key.
			a.expire_key_escape(~u64(0))
		}
		if a.key_csi_active {
			if ch == 0x1b {
				// A malformed prefix cannot release a nested CSI's numeric tail.
				a.key_csi_len = -1
				a.key_csi_overflow = false
				a.key_csi_ms = desktop_monotonic_ms()
			} else if ch >= 0x40 && ch <= 0x7e {
				if !a.key_csi_overflow { a.selection_navigation(ch) }
				a.key_csi_active = false
				a.key_csi_len = 0
				a.key_csi_overflow = false
			} else if a.key_csi_len < a.key_csi.len && ch >= 0x20 && ch < 0x40 {
				a.key_csi[a.key_csi_len] = ch
				a.key_csi_len++
			} else { a.key_csi_overflow = true }
			i++
			continue
		}
		// A multibyte character is gathered and typed as one. A byte that cannot
		// continue it ends it early: the partial character is dropped and that
		// byte is read afresh, so a control key or escape is never swallowed.
		if a.pending_len > 0 {
			if editor_utf8_follows(a.pending[0], a.pending_len, ch) {
				a.pending[a.pending_len] = ch
				a.pending_len++
				if a.pending_len == editor_utf8_length(a.pending[0]) {
					a.type_pending()
				}
				i++
				continue
			}
			a.pending_len = 0
		}
		if ch >= 0x80 {
			// A stray continuation, or a byte no character starts with, is dropped.
			if editor_utf8_length(ch) > 1 {
				a.pending[0] = ch
				a.pending_len = 1
			}
			i++
			continue
		}

		// Editor-wide shortcuts remain available because focused applications
		// receive control bytes before the desktop considers its own shortcuts.
		match ch {
			0x01 {
				if a.focus == .document { a.select_document() i++ continue }
			}
			0x03, 0x18 {
				if a.focus == .document { a.copy_selection(ch == 0x18) }
				i++
				continue
			}
			0x02 {
				if a.focus == .document {
					a.selection_marking = !a.selection_marking
					if a.selection_marking { a.selection_anchor = a.cursor }
					a.edit_recorded = false
					a.set_status('editor.selection.selected')
				}
				i++
				continue
			}
			0x1a {
				a.undo_edit()
				i++
				continue
			}
			0x19 {
				a.redo_edit()
				i++
				continue
			}
			0x06 {
				a.edit_recorded = false
				a.find_open = true
				a.focus = .query
				i++
				continue
			}
			0x07 {
				a.find_match(false)
				i++
				continue
			}
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
				a.edit_recorded = false
				a.save_document()
				i++
				continue
			}
			else {}
		}

		if ch == 0x1b {
			// Keep the first byte across keyboard reads. Polling disambiguates
			// the Escape key from a split CSI/SS3 prefix after 100 milliseconds.
			a.key_csi_active = true
			a.key_csi_len = -1
			a.key_csi_overflow = false
			a.key_csi_ms = desktop_monotonic_ms()
			i++
			continue
		}
		if a.focus != .document {
			a.field_key(ch)
			i++
			continue
		}

		a.document_key(ch)
		i++
	}
	a.follow_cursor()
}

fn (mut a TextEditorApp) paste_input(text string) {
	if text.len == 0 {
		return
	}
	a.pending_len = 0
	a.key_csi_active = false
	a.key_csi_len = 0
	a.key_csi_overflow = false
	if a.focus != .document {
		a.paste_field(text)
		return
	}
	if !a.prepare_selection_insertion(text.len) { return }
	for ch in text {
		a.insert_byte(ch)
	}
	a.modified = true
	a.set_status('editor.status.unsaved')
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
	a.follow_language()
	width := int(size.width)
	height := int(size.height)
	mut children := frame_elements(48)

	// Wide enough for the longest translation, Russian «Сохранить».
	button_width := 68
	children << editor_toolbar_button(editor_action_new, tr('editor.new'), editor_padding, button_width)
	children << editor_toolbar_button(editor_action_open, tr('editor.open'), editor_padding + button_width + 6, button_width)
	children << editor_toolbar_button(editor_action_save, tr('editor.save'), editor_padding + 2 * (button_width + 6), button_width)

	children << editor_toolbar_button(editor_action_save_as, tr('editor.workflow.save_as'), 232, 112)
	path_x := 350
	path_width := if width - path_x - editor_padding > 40 {
		width - path_x - editor_padding
	} else {
		40
	}
	mut path_label := frame_elements(1)
	path_label << ui2.label('', editor_bytes_text(a.path), ui2.rect(0, 0, f64(path_width), 28), ui2.TextStyle{
		color: body_text
		font_family: 'mono'
		size: 13
	})
	children << ui2.clickable_view(editor_action_path, ui2.rect(f64(path_x), 8, f64(path_width), 28), ui2.BoxStyle{
		bg: if a.focus == .path { editor_path_focus } else { body_panel }
		radius: 5
	}, path_label)
	a.build_edit_toolbar(mut children)
	mut document_top := editor_toolbar_height + if a.find_open { editor_find_height } else { 0 }
	if a.find_open { a.build_find_panel(mut children, width) }
	if a.save_as_open {
		a.build_save_as_panel(mut children, width, document_top)
		document_top += editor_save_as_height
	}
	if a.pending_action != .none_ {
		a.build_guard_panel(mut children, width, document_top)
		document_top += editor_guard_height
	}
	children << ui2.view('', ui2.rect(0, f64(document_top - 1), f64(width), 1), ui2.BoxStyle{
		bg: body_rule
	}, [])

	document_height := if height > document_top + editor_status_height {
		height - document_top - editor_status_height
	} else {
		editor_row_height
	}
	a.visible_rows = if document_height > 2 * editor_padding {
		(document_height - 2 * editor_padding) / editor_row_height
	} else {
		1
	}
	a.scroll = editor_clamp(a.scroll, 0, a.document_scroll_limit())

	mut lines := frame_elements(a.visible_rows * 3 + 1)
	mut position := a.offset_for_line(a.scroll)
	for row := 0; row < a.visible_rows; row++ {
		if position > a.text.len {
			break
		}
		end := a.line_end(position)
		a.build_selection_highlight(mut lines, position, end, row, width)
		a.build_match_highlight(mut lines, position, end, row)
		lines << ui2.label('', editor_slice_text(a.text, position, end - position), ui2.rect(f64(editor_padding), f64(editor_padding + row * editor_row_height), f64(width - 2 * editor_padding), f64(editor_row_height)), ui2.TextStyle{
			color: body_text
			font_family: 'mono'
			size: 13
		})
		if a.cursor >= position && a.cursor <= end {
			cursor_x := editor_padding + editor_columns(a.text, position, a.cursor) * editor_character_width
			lines << ui2.view('', ui2.rect(f64(cursor_x), f64(editor_padding + row * editor_row_height + 2), 2, f64(editor_row_height - 4)), ui2.BoxStyle{
				bg: if a.focus == .document { editor_cursor } else { body_muted }
			}, [])
		}
		if end >= a.text.len {
			break
		}
		position = end + 1
	}
	children << ui2.clickable_view(editor_action_document, ui2.rect(0, f64(document_top), f64(width), f64(document_height)), ui2.BoxStyle{
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
	// A click between the two reads of a split character abandons it.
	a.pending_len = 0
	a.key_csi_active = false
	a.key_csi_len = 0
	a.key_csi_overflow = false
	// A Jump List or Recent Items entry opens its document in a new window.
	if event_id.starts_with(jump_open_prefix) {
		path := event_id[jump_open_prefix.len..]
		a.set_path(path)
		unsafe { path.free() }
		a.open_document()
		return
	}
	match event_id {
		editor_action_select_all { a.select_document() }
		editor_action_copy { a.copy_selection(false) }
		editor_action_cut { a.copy_selection(true) }
		editor_action_save_as { a.begin_save_as() }
		editor_action_save_as_path { a.focus = .save_as }
		editor_action_save_as_create { a.create_save_as() }
		editor_action_save_as_cancel { a.save_as_open = false a.focus = .document }
		editor_action_guard_save { a.save_before_replacement() }
		editor_action_keep_editing { a.cancel_editor_choice() a.save_as_open = false a.focus = .document }
		editor_action_discard { if a.pending_action != .none_ && a.modified { a.discard_pending = true a.discard_close = false } }
		editor_action_confirm_discard { a.confirm_editor_discard() }
		editor_action_undo { a.undo_edit() }
		editor_action_redo { a.redo_edit() }
		editor_action_find {
			if a.find_open {
				a.close_find()
			} else {
				a.find_open = true
				a.focus = .query
			}
		}
		editor_action_query { a.focus = .query }
		editor_action_replacement { a.focus = .replacement }
		editor_action_next { a.find_match(false) }
		editor_action_previous { a.find_match(true) }
		editor_action_replace { a.replace_match() }
		editor_action_replace_all { a.replace_all() }
		editor_action_find_close { a.close_find() }
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
