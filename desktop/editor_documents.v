// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os
import ui2
import desktop.workflowcore

struct EditorDocuments {
mut:
	document workflowcore.Document
	message string
	recovery_available bool
	versions []string
	version_index int = -1
	autosaved_revision u64
	autosaved_at u64
}

fn editor_document_home(path string) string {
	$if workflow_test ? { return os.dir(path) }
	return if desktop_user_home.len > 0 { desktop_user_home } else { desktop_home }
}

fn workflow_editor_open(path string) !workflowcore.Document {
	canonical := workflowcore.canonical(path)!
	defer { unsafe { canonical.free() } }
	id := workflowcore.identify(canonical)!
	if !id.regular() { return error('Not an ordinary document file') }
	return workflowcore.new_document(editor_document_home(path), path)!
}

fn (mut a TextEditorApp) document_error(message string) {
	unsafe { a.documents.message.free() }
	a.documents.message = message.clone()
}

fn (mut a TextEditorApp) initialize_document_service(path string) bool {
	a.documents.document.close()
	a.documents.document = workflowcore.new_document(editor_document_home(path), path) or { a.document_error(err.msg()); return false }
	a.documents.recovery_available = false
	if recovery := a.documents.document.recovery() {
		a.documents.recovery_available = true
		unsafe { recovery.path.free(); recovery.bytes.free() }
		a.document_error('A recovery draft is available. Recover it or discard the draft.')
	}
	unsafe { a.documents.versions.free() }
	a.documents.versions = a.documents.document.versions() or { []string{} }
	a.documents.version_index = a.documents.versions.len
	return true
}

fn (mut a TextEditorApp) save_through_document_service(path string, create_only bool) bool {
	if create_only && desktop_lstat(path) != none { a.set_status('editor.workflow.exists'); a.document_error('Destination exists; choose a new name.'); return false }
	canonical := workflowcore.canonical(path) or { a.document_error(err.msg()); a.set_status('editor.status.cannot_save'); return false }
	defer { unsafe { canonical.free() } }
	mut new_path := false
	if a.documents.document.path != canonical {
		new_path = true
		if !a.initialize_document_service(path) { a.set_status('editor.status.cannot_save'); return false }
	}
	a.documents.document.save(a.text, create_only || new_path || a.documents.document.expected == none) or {
		a.document_error(err.msg())
		a.set_status('editor.status.cannot_save')
		return false
	}
	a.documents.recovery_available = false
	a.documents.autosaved_revision = a.revision
	unsafe { a.documents.versions.free() }
	a.documents.versions = a.documents.document.versions() or { []string{} }
	a.documents.version_index = a.documents.versions.len
	a.document_error('Saved atomically. Previous contents are in Versions.')
	return true
}

fn (mut a TextEditorApp) poll_document_service(now u64) bool {
	if !a.modified || a.documents.recovery_available || now == ~u64(0) || (now >= a.documents.autosaved_at && now - a.documents.autosaved_at < 2000) { return false }
	a.documents.autosaved_at = now
	if a.documents.document.path.len == 0 {
		path := if a.document_path.len > 0 { editor_bytes_text(a.document_path) } else { editor_bytes_text(a.path) }
		if !a.initialize_document_service(path) || a.documents.recovery_available { return true }
	}
	if a.documents.autosaved_revision == a.revision { return false }
	a.documents.document.autosave(a.text) or { a.document_error('Recovery save failed: ' + err.msg()); return true }
	a.documents.autosaved_revision = a.revision
	a.document_error('Recovery draft saved.')
	return true
}

fn (mut a TextEditorApp) document_service_action(action string) bool {
	if action !in ['editor.recovery.restore', 'editor.recovery.discard', 'editor.versions.previous'] { return false }
	mut bytes := []u8{}
	if action == 'editor.recovery.discard' {
		a.documents.document.discard_recovery() or { a.document_error(err.msg()); return true }
		a.documents.recovery_available = false
		a.document_error('Recovery draft discarded.')
		return true
	}
	if action == 'editor.recovery.restore' {
		recovery := a.documents.document.recovery() or { a.document_error(err.msg()); return true }
		if recovery.bytes.len > editor_max_file_size { a.document_error('Recovery exceeds document size limit.'); return true }
		bytes = recovery.bytes
		a.documents.document.expected = recovery.base
		unsafe { recovery.path.free() }
		a.documents.recovery_available = false
	} else {
		if a.documents.versions.len == 0 { a.document_error('No saved versions.'); return true }
		a.documents.version_index = (a.documents.version_index + a.documents.versions.len - 1) % a.documents.versions.len
		bytes = a.documents.document.version(a.documents.versions[a.documents.version_index], editor_max_file_size) or { a.document_error(err.msg()); return true }
	}
	a.edit_recorded = false
	a.record_edit()
	unsafe { a.text.free() }
	a.text = bytes
	a.cursor = bytes.len
	a.modified = true
	a.follow_cursor()
	a.set_status('editor.status.unsaved')
	a.document_error('Restored into the editor. Save or Save As to keep this revision.')
	return true
}

fn (a &TextEditorApp) build_document_services(mut children []ui2.Element, width int, top int) {
	for i, pair in [['editor.recovery.restore', 'Recover draft']!, ['editor.recovery.discard', 'Discard draft']!, ['editor.versions.previous', 'Previous version']!]! {
		children << ui2.Element{...ui2.button(pair[0], pair[1], ui2.rect(f64(8 + i * 126), f64(top), 120, 26), ui2.BoxStyle{bg: body_panel}, ui2.TextStyle{color: body_text, size: 11}), enabled: if i < 2 { a.documents.recovery_available } else { a.documents.versions.len > 0 }}
	}
	children << ui2.label('', a.documents.message, ui2.rect(8, f64(top + 28), f64(width - 16), 22), ui2.TextStyle{color: body_muted, size: 11})
}

fn (mut a TextEditorApp) close_document_service() {
	if a.modified && !a.discard_close { a.poll_document_service(~u64(0) - 1) }
	a.documents.document.close()
	unsafe { a.documents.message.free(); a.documents.versions.free() }
	a.documents = EditorDocuments{}
}
