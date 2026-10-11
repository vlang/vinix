// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os

fn test_editor_recovery_versions_and_external_edits_keep_user_data() {
	root := os.real_path(os.temp_dir()) + '/vinix-editor-documents-${os.getpid()}'
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	path := root + '/document.txt'
	os.write_file(path, 'first')!
	mut app := TextEditorApp{}
	defer { app.close_app() }
	app.set_path(path)
	assert app.perform_open_document()
	app.key_input(' draft')
	assert app.poll_document_service(3000)
	assert os.read_file(path)! == 'first'
	mut recovered := TextEditorApp{}
	defer { recovered.close_app() }
	recovered.set_path(path)
	assert recovered.perform_open_document() && recovered.documents.recovery_available
	recovered.handle('editor.recovery.restore')!
	assert editor_bytes_text(recovered.text) == 'first draft'
	assert recovered.save_document()
	assert recovered.documents.versions.len == 1
	recovered.handle('editor.versions.previous')!
	assert editor_bytes_text(recovered.text) == 'first' && recovered.modified
	os.write_file(path, 'external edit')!
	assert !recovered.save_document()
	assert os.read_file(path)! == 'external edit'
	assert editor_bytes_text(recovered.text) == 'first'
}
