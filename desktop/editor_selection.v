// SPDX-License-Identifier: GPL-2.0-or-later
// UTF-8 document selections and acknowledged guest clipboard operations.
module main

import ui2

const editor_action_select_all = 'editor.selection.all'
const editor_action_copy = 'editor.selection.copy'
const editor_action_cut = 'editor.selection.cut'

fn editor_clamp(value int, low int, high int) int {
	return if value < low { low } else if value > high { high } else { value }
}

fn (a &TextEditorApp) has_selection() bool {
	return a.selection_anchor >= 0 && a.selection_anchor != a.cursor
}

fn (a &TextEditorApp) selection_bounds() (int, int) {
	anchor := editor_clamp(a.selection_anchor, 0, a.text.len)
	caret := editor_clamp(a.cursor, 0, a.text.len)
	return if anchor < caret { anchor } else { caret }, if anchor < caret { caret } else { anchor }
}

fn (mut a TextEditorApp) clear_selection() {
	a.selection_anchor = -1
	a.selection_dragging = false
	a.selection_marking = false
}

fn (mut a TextEditorApp) select_document() {
	a.focus = .document
	a.pending_len = 0
	a.edit_recorded = false
	a.clear_match()
	a.clear_selection()
	a.selection_anchor = 0
	a.cursor = a.text.len
	a.set_status('editor.selection.selected')
	a.follow_cursor()
}

fn (mut a TextEditorApp) delete_selection() bool {
	if !a.has_selection() { return false }
	start, end := a.selection_bounds()
	a.delete_char(start, end - start)
	a.follow_cursor()
	return true
}

fn (mut a TextEditorApp) prepare_selection_insertion(length int) bool {
	start, end := a.selection_bounds()
	removed := if a.has_selection() { end - start } else { 0 }
	if length > editor_max_file_size || a.text.len - removed > editor_max_file_size - length {
		a.set_status('editor.status.limit')
		return false
	}
	a.record_edit()
	if removed > 0 {
		a.text.delete_many(start, removed)
		a.cursor = start
	}
	return true
}

// Parameters are held in fixed storage, including across a split CSI read.
// Unknown/modifier sequences are consumed whole without inserting their tail.
fn (mut a TextEditorApp) selection_navigation(final u8) {
	if a.focus != .document { return }
	params := if a.key_csi_len > 0 { unsafe { tos(&a.key_csi[0], a.key_csi_len) } } else { '' }
	extend := params == '1;2'
	mut command := final
	if final == `~` {
		command = match params {
			'1', '7', '1;2', '7;2' { u8(`H`) }
			'4', '8', '4;2', '8;2' { u8(`F`) }
			'3' { u8(127) }
			'5', '5;2' { u8(`P`) }
			'6', '6;2' { u8(`N`) }
			else { return }
		}
	} else if params != '' && params != '1' && !extend { return }
	if command != `A` && command != `B` && command != `C` && command != `D`
		&& command != `H` && command != `F` && command != `P` && command != `N`
		&& command != 127 { return }
	a.edit_recorded = false
	a.clear_match()
	if command == 127 {
		if !a.delete_selection() && a.cursor < a.text.len {
			a.delete_char(a.cursor, editor_char_length(a.text, a.cursor))
		}
		return
	}
	shift := a.selection_marking || extend || (final == `~` && (params == '7;2' || params == '4;2' || params == '8;2' || params == '5;2' || params == '6;2'))
	if !shift && a.has_selection() && (command == `C` || command == `D`) {
		start, end := a.selection_bounds()
		a.cursor = if command == `D` { start } else { end }
		a.clear_selection()
		return
	}
	if shift {
		if a.selection_anchor < 0 { a.selection_anchor = a.cursor }
	} else { a.clear_selection() }
	match command {
		`A` { a.move_vertical(-1) }
		`B` { a.move_vertical(1) }
		`C` { a.cursor += editor_char_length(a.text, a.cursor) }
		`D` { a.cursor = editor_char_before(a.text, a.cursor) }
		`H` { a.cursor = a.line_start(a.cursor) }
		`F` { a.cursor = a.line_end(a.cursor) }
		`P`, `N` { for _ in 0 .. a.visible_rows { a.move_vertical(if command == `P` { -1 } else { 1 }) } }
		else {}
	}
}

fn (mut a TextEditorApp) expire_key_escape(now u64) bool {
	if !a.key_csi_active || (now != ~u64(0) && now >= a.key_csi_ms && now - a.key_csi_ms < 100) { return false }
	bare := a.key_csi_len == -1
	a.key_csi_active = false
	a.key_csi_len = 0
	a.key_csi_overflow = false
	if bare {
		if a.save_as_open || a.pending_action != .none_ {
			a.cancel_editor_choice()
			a.save_as_open = false
		}
		a.close_find()
		a.clear_selection()
		a.follow_cursor()
	}
	return true
}

fn (mut a TextEditorApp) poll() bool { return a.expire_key_escape(desktop_monotonic_ms()) }

fn (a &TextEditorApp) next_poll_ms() u64 { return if a.key_csi_active { u64(100) } else { u64(2000) } }

fn (mut a TextEditorApp) copy_selection(cut bool) {
	if !a.has_selection() { return }
	if app_compositor_features & app_feature_text_copy == 0 {
		a.set_status('editor.selection.unavailable')
		return
	}
	start, end := a.selection_bounds()
	a.copy_text.clear()
	unsafe { a.copy_text.flags |= .noslices }
	for index in start .. end { a.copy_text << a.text[index] }
	a.copy_sequence++
	if a.copy_sequence == 0 { a.copy_sequence = 1 }
	a.copy_start = start
	a.copy_end = end
	a.copy_revision = a.revision
	a.copy_cut = cut
	a.copy_queued = true
	a.copy_waiting = false
	a.edit_recorded = false
}

fn (mut a TextEditorApp) take_clipboard_copy_request() []u8 {
	if !a.copy_queued { return []u8{} }
	a.copy_queued = false
	a.copy_waiting = true
	return text_copy_request(a.copy_sequence, editor_bytes_text(a.copy_text))
}

fn (mut a TextEditorApp) receive_clipboard_copy_reply(payload string) {
	if payload.len != text_copy_reply_size || color_meter_read_u32(payload, 0) != text_copy_magic
		|| !a.copy_waiting || color_meter_read_u32(payload, 4) != a.copy_sequence
		|| color_meter_read_u32(payload, 8) > 1 { return }
	a.copy_waiting = false
	if color_meter_read_u32(payload, 8) == 0 {
		a.set_status('editor.selection.unavailable')
	} else {
		start, end := a.selection_bounds()
		// Cut removes text only after the compositor confirms the copy, and
		// only while this exact document revision and selection still exist.
		if a.copy_cut && a.revision == a.copy_revision && a.has_selection()
			&& start == a.copy_start && end == a.copy_end {
			a.delete_selection()
		} else { a.set_status('editor.selection.copied') }
	}
	a.copy_text.clear()
}

fn (a &TextEditorApp) document_top() int {
	return editor_toolbar_height + if a.find_open { editor_find_height } else { 0 }
		+ if a.save_as_open { editor_save_as_height } else { 0 }
		+ if a.pending_action != .none_ { editor_guard_height } else { 0 }
}

fn (a &TextEditorApp) document_scroll_limit() int {
	mut rows := 1
	for byte in a.text { if byte == `\n` { rows++ } }
	return if rows > a.visible_rows { rows - a.visible_rows } else { 0 }
}

fn (a &TextEditorApp) pointer_offset(x int, y int) int {
	top := a.document_top()
	row := editor_clamp((y - top - editor_padding) / editor_row_height, 0, a.visible_rows - 1)
	start := a.offset_for_line(a.scroll + row)
	end := a.line_end(start)
	column := if x > editor_padding { (x - editor_padding + editor_character_width / 2) / editor_character_width } else { 0 }
	return editor_column_offset(a.text, start, end, column)
}

fn (a &TextEditorApp) pointer_input_enabled() bool { return true }
fn (a &TextEditorApp) pointer_moves_matter() bool { return a.selection_dragging }

fn (mut a TextEditorApp) pointer_event(phase AppPointerPhase, button AppPointerButton, scroll int, x int, y int, width int, height int) {
	if width <= 0 || height <= 0 { return }
	top := a.document_top()
	if phase == .scroll && y >= top && y < height - editor_status_height {
		a.scroll = editor_clamp(a.scroll - scroll * 3, 0, a.document_scroll_limit())
		return
	}
	if phase == .down && button == .left && y >= top && y < height - editor_status_height {
		a.selection_marking = false
		a.focus = .document
		a.pending_len = 0
		a.key_csi_active = false
		a.key_csi_len = 0
		a.key_csi_overflow = false
		a.edit_recorded = false
		a.clear_match()
		a.cursor = a.pointer_offset(x, y)
		a.selection_anchor = a.cursor
		a.selection_dragging = true
	} else if a.selection_dragging && (phase == .move || phase == .up) {
		if y < top + editor_padding { a.scroll = editor_clamp(a.scroll - 1, 0, a.document_scroll_limit()) }
		else if y >= height - editor_status_height - editor_padding { a.scroll = editor_clamp(a.scroll + 1, 0, a.document_scroll_limit()) }
		a.cursor = a.pointer_offset(x, y)
		if a.has_selection() { a.set_status('editor.selection.selected') }
		if phase == .up { a.selection_dragging = false }
	}
}

fn (a &TextEditorApp) build_selection_highlight(mut lines []ui2.Element, start int, end int, row int, width int) {
	if !a.has_selection() { return }
	left, right := a.selection_bounds()
	if right <= start || left > end { return }
	first := if left > start { left } else { start }
	last := if right < end { right } else { end }
	x := editor_padding + editor_columns(a.text, start, first) * editor_character_width
	columns := editor_columns(a.text, first, last) + if right > end && end < a.text.len { 1 } else { 0 }
	w := editor_clamp(columns * editor_character_width, 0, if width > x { width - x } else { 0 })
	if w == 0 { return }
	lines << ui2.view('editor.selection.highlight', ui2.rect(f64(x), f64(editor_padding + row * editor_row_height), f64(w), editor_row_height), ui2.BoxStyle{ bg: editor_path_focus }, [])
}
