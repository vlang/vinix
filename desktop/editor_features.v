// SPDX-License-Identifier: GPL-2.0-or-later
// Bounded document history and plain-text Find / Replace for Text Editor.
module main

fn editor_history_clear(mut history []EditorSnapshot) {
	for snapshot in history {
		unsafe { snapshot.text.free() }
	}
	history.clear()
}

fn editor_history_push(mut history []EditorSnapshot, snapshot EditorSnapshot) {
	if history.cap == 0 {
		history = []EditorSnapshot{cap: editor_history_limit}
	}
	if history.len == editor_history_limit {
		unsafe { history[0].text.free() }
		for index in 1 .. history.len {
			history[index - 1] = history[index]
		}
		unsafe { history.len-- }
	}
	history << snapshot
}

fn (a &TextEditorApp) snapshot() EditorSnapshot {
	return EditorSnapshot{
		text:     a.text.clone()
		cursor:   a.cursor
		revision: a.revision
	}
}

fn (mut a TextEditorApp) reset_history() {
	editor_history_clear(mut a.undo_history)
	editor_history_clear(mut a.redo_history)
	a.revision = 0
	a.next_revision = 0
	a.saved_revision = 0
	a.document_has_save = false
	a.edit_recorded = false
	a.pending_len = 0
	a.clear_match()
}

// A history entry owns its byte array. Undo and redo transfer that ownership
// back into the document, and evicted entries release it explicitly.
fn (mut a TextEditorApp) record_edit() {
	if !a.edit_group || !a.edit_recorded {
		editor_history_clear(mut a.redo_history)
		editor_history_push(mut a.undo_history, a.snapshot())
		a.next_revision++
		a.revision = a.next_revision
		a.edit_recorded = true
	}
	a.clear_match()
}

fn (mut a TextEditorApp) restore_snapshot(snapshot EditorSnapshot) {
	unsafe { a.text.free() }
	a.text = snapshot.text
	a.cursor = snapshot.cursor
	a.revision = snapshot.revision
	a.modified = a.revision != a.saved_revision
	a.edit_recorded = false
	a.pending_len = 0
	a.clear_match()
	if a.modified {
		a.set_status('editor.status.unsaved')
	} else if a.document_has_save {
		a.set_file_status('editor.status.saved')
	} else {
		a.set_status('editor.status.new_document')
	}
	a.follow_cursor()
}

fn (mut a TextEditorApp) undo_edit() {
	if a.undo_history.len == 0 {
		return
	}
	snapshot := a.undo_history.pop()
	editor_history_push(mut a.redo_history, a.snapshot())
	a.restore_snapshot(snapshot)
}

fn (mut a TextEditorApp) redo_edit() {
	if a.redo_history.len == 0 {
		return
	}
	snapshot := a.redo_history.pop()
	editor_history_push(mut a.undo_history, a.snapshot())
	a.restore_snapshot(snapshot)
}

fn (mut a TextEditorApp) clear_match() {
	a.match_start = -1
	a.match_end = -1
}

fn (mut a TextEditorApp) close_find() {
	a.find_open = false
	a.focus = .document
	a.edit_recorded = false
	a.clear_match()
}

// Match only whole characters, including each invalid UTF-8 byte that the
// editor preserves as a character. Neither finding nor replacing splits a
// valid sequence even when clipboard text contains a stray continuation.
fn editor_match_at(text []u8, query []u8, start int) bool {
	if query.len == 0 || start < 0 || start + query.len > text.len {
		return false
	}
	for index, ch in query {
		if text[start + index] != ch {
			return false
		}
	}
	end := start + query.len
	mut at := start
	for at < end {
		at += editor_char_length(text, at)
	}
	return at == end
}

fn (mut a TextEditorApp) find_match(previous bool) {
	if a.query.len == 0 {
		a.clear_match()
		return
	}
	start := if a.match_start >= 0 {
		if previous { a.match_start } else { a.match_end }
	} else {
		a.cursor
	}
	mut chosen := -1
	mut wrapped := -1
	mut at := 0
	for at < a.text.len {
		if editor_match_at(a.text, a.query, at) {
			if previous {
				wrapped = at
				if at < start { chosen = at }
			} else {
				if wrapped < 0 { wrapped = at }
				if at >= start {
					chosen = at
					break
				}
			}
		}
		at += editor_char_length(a.text, at)
	}
	if chosen < 0 { chosen = wrapped }
	if chosen < 0 {
		a.clear_match()
		a.set_status('editor.status.no_match')
		return
	}
	a.match_start = chosen
	a.match_end = chosen + a.query.len
	a.cursor = chosen
	a.edit_recorded = false
	a.set_status('editor.status.match')
	a.follow_cursor()
}

fn (mut a TextEditorApp) replace_match() {
	if a.match_start < 0 {
		a.find_match(false)
		if a.match_start < 0 { return }
	}
	start := a.match_start
	end := a.match_end
	if a.text.len - (end - start) + a.replacement.len > editor_max_file_size {
		a.set_status('editor.status.limit')
		return
	}
	if a.query == a.replacement {
		a.find_match(false)
		return
	}
	mut next := []u8{cap: a.text.len - (end - start) + a.replacement.len}
	for index in 0 .. start { next << a.text[index] }
	next << a.replacement
	for index in end .. a.text.len { next << a.text[index] }
	a.record_edit()
	unsafe { a.text.free() }
	a.text = next
	a.cursor = start + a.replacement.len
	a.settle_cursor()
	a.modified = true
	a.set_status('editor.status.replaced')
	a.find_match(false)
	if a.match_start < 0 { a.set_status('editor.status.replaced') }
}

fn (mut a TextEditorApp) replace_all() {
	if a.query.len == 0 { return }
	mut count := 0
	mut at := 0
	for at < a.text.len {
		if editor_match_at(a.text, a.query, at) {
			count++
			at += a.query.len
		} else {
			at += editor_char_length(a.text, at)
		}
	}
	if count == 0 {
		a.clear_match()
		a.set_status('editor.status.no_match')
		return
	}
	if a.query == a.replacement { return }
	length := a.text.len + count * (a.replacement.len - a.query.len)
	if length > editor_max_file_size {
		a.set_status('editor.status.limit')
		return
	}
	mut next := []u8{cap: length}
	at = 0
	for at < a.text.len {
		if editor_match_at(a.text, a.query, at) {
			next << a.replacement
			at += a.query.len
		} else {
			step := editor_char_length(a.text, at)
			for index in at .. at + step { next << a.text[index] }
			at += step
		}
	}
	a.record_edit()
	unsafe { a.text.free() }
	a.text = next
	a.cursor = 0
	a.modified = true
	a.set_status('editor.status.replaced')
	a.follow_cursor()
}

fn (mut a TextEditorApp) append_field_character(length int) {
	// Copying a four-byte stack buffer slice is unnecessary on every key.
	mut field := match a.focus {
		.path { &a.path }
		.query { &a.query }
		else { &a.replacement }
	}
	unsafe { field.flags |= .noslices }
	if field.len + length > editor_max_path { return }
	for index in 0 .. length { field << a.pending[index] }
	if a.focus == .query { a.clear_match() }
}

fn (mut a TextEditorApp) field_key(ch u8) {
	if a.focus == .path {
		a.edit_path(ch)
		return
	}
	if ch == `\r` || ch == `\n` {
		if a.focus == .query { a.find_match(false) } else { a.replace_match() }
		return
	}
	if ch == `\t` {
		a.focus = if a.focus == .query { EditorFocus.replacement } else { EditorFocus.query }
		return
	}
	mut field := if a.focus == .query { &a.query } else { &a.replacement }
	unsafe { field.flags |= .noslices }
	if ch == 8 || ch == 127 {
		if field.len > 0 { field.trim(editor_char_before(*field, field.len)) }
	} else if ch >= 0x20 && ch < 0x7f && field.len < editor_max_path {
		field << ch
	}
	if a.focus == .query { a.clear_match() }
}

fn (mut a TextEditorApp) paste_field(text string) {
	mut field := match a.focus {
		.path { &a.path }
		.query { &a.query }
		else { &a.replacement }
	}
	unsafe { field.flags |= .noslices }
	if field.len + text.len > editor_max_path { return }
	for ch in text {
		if ch >= 32 && ch != 127 { field << ch }
	}
	if a.focus == .query { a.clear_match() }
}

fn (mut a TextEditorApp) close_app() {
	a.reset_history()
	unsafe {
		a.undo_history.free()
		a.redo_history.free()
		a.text.free()
		a.path.free()
		a.status.free()
		a.query.free()
		a.replacement.free()
	}
	a = TextEditorApp{}
}
