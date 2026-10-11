// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn document_apps_home() string {
	path := os.real_path(os.temp_dir()) + '/vinix-document-apps-${C.getpid()}'
	os.mkdir_all(path) or { panic(err) }
	return path
}

fn test_notes_use_shared_recovery_and_versions_without_overwriting_external_edits() {
	home := document_apps_home()
	defer { os.rmdir_all(home) or {} }
	mut app := new_notes_app(home)
	defer { app.discard_allowed = true; app.close_app() }
	app.new_note()
	app.title.clear(); editor_append(mut app.title, 'Document')
	app.body.clear(); editor_append(mut app.body, 'First revision')
	app.mark_dirty()
	assert app.save()
	app.body.clear(); editor_append(mut app.body, 'Second revision')
	app.mark_dirty()
	assert app.save()
	assert app.document.versions()!.len == 1
	assert app.document_action('notes.versions')
	assert editor_bytes_text(app.body) == 'First revision' && app.dirty
	assert app.save()
	app.body.clear(); editor_append(mut app.body, 'Recovery draft')
	app.mark_dirty()
	draft := app.encode(-1)
	defer { unsafe { draft.free() } }
	app.document.autosave(draft.bytes())!
	mut recovered := new_notes_app(home)
	defer { recovered.discard_allowed = true; recovered.close_app() }
	assert recovered.recovery_available
	assert recovered.document_action('notes.recovery')
	assert editor_bytes_text(recovered.body) == 'Recovery draft'
	app.body.clear(); editor_append(mut app.body, 'External revision')
	assert app.save()
	assert !recovered.save() && recovered.status == 'notes.conflict'
	assert os.read_file(home + '/.vinix-notes')!.contains('External revision')
}

fn test_grapher_keyboard_edits_autosave_and_versions_preserve_external_changes() {
	home := document_apps_home()
	defer { os.rmdir_all(home) or {} }
	path := home + '/graph.vgraph'
	mut app := GrapherApp{}
	app.initialize()
	defer { app.close_app() }
	app.set_field(6, path)
	app.save_graph_document()
	assert app.document_status == 'grapher.document_saved'
	app.focus = 0; app.selected = true
	app.input_text('x^3')
	assert app.document_changed
	app.poll_graph_document(5000)
	assert app.document.recovery()!.bytes.bytestr().contains('expression=x^3')
	assert app.graph_document_action('grapher.document.save')
	assert app.document_status == 'grapher.document_saved'
	assert app.graph_document_action('grapher.document.version')
	assert app.field_text(0) != 'x^3'
	os.write_file(path, 'external')!
	assert app.graph_document_action('grapher.document.save')
	assert app.document_status == 'grapher.document_save_failed'
	assert os.read_file(path)! == 'external'
}
