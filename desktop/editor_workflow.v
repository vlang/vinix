// SPDX-License-Identifier: GPL-2.0-or-later
module main

enum EditorPendingAction { none_ close new_document open_document }

const editor_action_save_as = 'editor.save_as'
const editor_action_save_as_path = 'editor.save_as.path'
const editor_action_save_as_create = 'editor.save_as.create'
const editor_action_save_as_cancel = 'editor.save_as.cancel'
const editor_action_guard_save = 'editor.guard.save'
const editor_action_keep_editing = 'editor.guard.keep_editing'
const editor_action_discard = 'editor.guard.discard'
const editor_action_confirm_discard = 'editor.guard.confirm_discard'

fn editor_valid_save_path(path string) bool {
	if path.len == 0 || path.len > editor_max_path || path[path.len - 1] == `/` { return false }
	for byte in path { if byte < 32 || byte == 127 { return false } }
	return true
}

fn (mut a TextEditorApp) cancel_editor_choice() {
	a.pending_action = .none_
	a.pending_path.clear()
	a.discard_pending = false
	a.discard_close = false
	if a.status_key == 'editor.workflow.discard_ready' { a.set_status('editor.status.unsaved') }
}

fn (mut a TextEditorApp) request_editor_action(action EditorPendingAction) bool {
	if action == .close && a.discard_close { return true }
	if a.modified {
		keep_open_target := action == .open_document && a.pending_action == .open_document
			&& editor_bytes_text(a.path) == editor_bytes_text(a.document_path)
		a.pending_action = action
		if !keep_open_target {
			a.pending_path.clear()
			if action == .open_document { editor_append(mut a.pending_path, editor_bytes_text(a.path)) }
		}
		if action == .open_document && a.document_path.len > 0 { a.set_path(editor_bytes_text(a.document_path)) }
		a.discard_pending = false
		a.discard_close = false
		a.set_status('editor.status.unsaved')
		return false
	}
	a.cancel_editor_choice()
	if action == .new_document { a.perform_new_document() }
	else if action == .open_document { return a.perform_open_document() }
	return true
}

fn (mut a TextEditorApp) new_document() { a.request_editor_action(.new_document) }
fn (mut a TextEditorApp) open_document() { a.request_editor_action(.open_document) }
fn (mut a TextEditorApp) prepare_close() bool { return a.request_editor_action(.close) }

fn (mut a TextEditorApp) complete_editor_action() {
	a.discard_pending = false
	match a.pending_action {
		.new_document { a.cancel_editor_choice() a.save_as_open = false a.perform_new_document() }
		.open_document {
			a.set_path(editor_bytes_text(a.pending_path))
			if a.perform_open_document() { a.cancel_editor_choice() a.save_as_open = false }
			else {
				original := if a.document_path.len > 0 { editor_bytes_text(a.document_path) }
					else if a.default_path.len > 0 { editor_bytes_text(a.default_path) } else { editor_default_path }
				a.set_path(original)
			}
		}
		.close { if !a.modified { a.cancel_editor_choice() } }
		else {}
	}
}

fn (mut a TextEditorApp) confirm_editor_discard() {
	if !a.modified || !a.discard_pending || a.pending_action == .none_ { return }
	if a.pending_action == .close {
		a.discard_pending = false
		a.discard_close = true
		a.set_status('editor.workflow.discard_ready')
	} else { a.complete_editor_action() }
}

fn (mut a TextEditorApp) save_before_replacement() {
	a.discard_pending = false
	a.discard_close = false
	if a.pending_action == .none_ { return }
	if !a.document_has_save { a.begin_save_as() return }
	// The toolbar may already contain the next Open target. Save this document
	// back to its original file, then use the independently latched target.
	a.set_path(editor_bytes_text(a.document_path))
	a.save_document()
}

fn (mut a TextEditorApp) begin_save_as() {
	a.discard_pending = false
	a.discard_close = false
	a.save_as_path.clear()
	editor_append(mut a.save_as_path, editor_bytes_text(a.path))
	a.save_as_open = true
	a.focus = .save_as
	a.pending_len = 0
}

fn (mut a TextEditorApp) create_save_as() bool {
	a.discard_pending = false
	a.discard_close = false
	if !a.save_as_open { return false }
	path := editor_bytes_text(a.save_as_path).clone()
	defer { unsafe { path.free() } }
	if !editor_valid_save_path(path) { a.set_status('editor.workflow.invalid_path') return false }
	result := editor_create_file(path, a.text)
	if result != '' { a.set_status(result) return false }
	a.set_path(path)
	a.document_path.clear()
	editor_append(mut a.document_path, path)
	a.document_has_save = true
	a.saved_revision = a.revision
	a.modified = false
	a.save_as_open = false
	a.focus = .document
	a.set_file_status('editor.status.saved')
	record_recent_item('vinix-editor', path)
	a.complete_editor_action()
	return true
}
