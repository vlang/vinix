// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn (mut a NotesApp) document_action(action string) bool {
	if action !in ['notes.recovery', 'notes.versions'] { return false }
	if a.dirty { a.status = 'notes.unsaved'; return true }
	mut bytes := []u8{}
	if action == 'notes.recovery' {
		draft := a.document.recovery() or { a.status = 'notes.read_failed'; return true }
		bytes = draft.bytes
		a.document.expected = draft.base
		unsafe { draft.path.free() }
	} else {
		versions := a.document.versions() or { a.status = 'notes.read_failed'; return true }
		defer { unsafe { versions.free() } }
		if versions.len == 0 { a.status = 'notes.ready'; return true }
		bytes = a.document.version(versions.last(), notes_record_limit) or { a.status = 'notes.read_failed'; return true }
	}
	defer { unsafe { bytes.free() } }
	text := bytes.bytestr()
	defer { unsafe { text.free() } }
	if !a.decode(text) { a.status = 'notes.corrupt'; return true }
	a.selected = -1
	if a.count > 0 { a.load_selected(0) }
	a.refilter()
	a.recovery_available = false
	a.mark_dirty()
	a.status = 'notes.unsaved'
	return true
}

fn (a &NotesApp) document_buttons(mut children []ui2.Element, width int, height int) {
	children << ui2.Element{...ui2.button('notes.recovery', 'Recover draft', ui2.rect(12, f64(height - 32), 140, 24), ui2.BoxStyle{bg: body_panel}, ui2.TextStyle{color: body_text, size: 11}), enabled: a.recovery_available && !a.dirty}
	children << ui2.button('notes.versions', 'Previous saved version', ui2.rect(160, f64(height - 32), f64(if width > 400 { 190 } else { width - 172 }), 24), ui2.BoxStyle{bg: body_panel}, ui2.TextStyle{color: body_text, size: 11})
}
