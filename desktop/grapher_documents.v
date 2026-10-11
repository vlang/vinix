// SPDX-License-Identifier: GPL-2.0-or-later
module main
import ui2
import desktop.workflowcore

fn (mut app GrapherApp) prepare_graph_service() bool {
	path := app.field_text(6)
	if !grapher_document_path_valid(path) { return false }
	parent, leaf := archive_parent(path)
	if parent < 0 { return false }
	desktop_close(parent)
	unsafe { leaf.free() }
	if app.document.path == path { return true }
	app.document.close()
	app.document = workflowcore.new_document(editor_document_home(path), path) or { return false }
	return true
}

fn (mut app GrapherApp) poll_graph_document(now u64) bool {
	if !app.document_changed || !app.initialized || now == ~u64(0) || (now >= app.document_autosave_at && now - app.document_autosave_at < 2000) { return false }
	app.document_autosave_at = now
	if !app.prepare_graph_service() { return false }
	fields := app.graph_document_values()
	if !grapher_document_values_valid(fields) { return false }
	bytes := grapher_document_bytes(fields)
	defer { unsafe { bytes.free() } }
	app.document.autosave(bytes) or { app.document_status = 'grapher.document_save_failed'; return true }
	app.document_changed = false
	return false
}

fn (mut app GrapherApp) poll() bool { return app.poll_graph_document(desktop_monotonic_ms()) }
fn (app &GrapherApp) next_poll_ms() u64 { return 2000 }

fn (mut app GrapherApp) graph_document_action(action string) bool {
	if action !in ['grapher.document.save', 'grapher.document.recover', 'grapher.document.version'] { return false }
	if !app.prepare_graph_service() { app.document_status = 'grapher.document_save_failed'; return true }
	if action == 'grapher.document.save' {
		fields := app.graph_document_values()
		if !grapher_document_values_valid(fields) { app.document_status = 'grapher.document_invalid'; return true }
		bytes := grapher_document_bytes(fields)
		defer { unsafe { bytes.free() } }
		app.document.save(bytes, app.document.expected == none) or { app.document_status = 'grapher.document_save_failed'; return true }
		app.document_changed = false
		app.document_status = 'grapher.document_saved'
		return true
	}
	mut bytes := []u8{}
	if action == 'grapher.document.recover' {
		draft := app.document.recovery() or { app.document_status = 'grapher.document_open_failed'; return true }
		bytes = draft.bytes
		app.document.expected = draft.base
		unsafe { draft.path.free() }
	} else {
		versions := app.document.versions() or { app.document_status = 'grapher.document_open_failed'; return true }
		defer { unsafe { versions.free() } }
		if versions.len == 0 { return true }
		bytes = app.document.version(versions.last(), grapher_document_limit) or { app.document_status = 'grapher.document_open_failed'; return true }
	}
	defer { unsafe { bytes.free() } }
	text := bytes.bytestr()
	defer { unsafe { text.free() } }
	document := grapher_document_parse(text) or { app.document_status = 'grapher.document_invalid'; return true }
	for i, value in document.fields { app.set_field(i, value) }
	app.plot()
	return true
}

fn (app &GrapherApp) graph_document_buttons(mut children []ui2.Element, width int, y int) {
	button_width := (width - 32) / 3
	for i, pair in [['grapher.document.save', 'Save']!, ['grapher.document.recover', 'Recover draft']!, ['grapher.document.version', 'Previous version']!]! {
		children << ui2.button(pair[0], pair[1], ui2.rect(f64(12 + i * (button_width + 4)), f64(y), f64(button_width), 24), ui2.BoxStyle{bg: body_panel}, ui2.TextStyle{color: body_text, size: 11})
	}
}
