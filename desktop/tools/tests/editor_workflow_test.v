// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn editor_workflow_home(name string) string {
	base := os.real_path(os.temp_dir())
	pid := os.getpid().str()
	home := '${base}/vinix-editor-workflow-${pid}-${name}'
	unsafe { base.free() pid.free() }
	os.rmdir_all(home) or {}
	os.mkdir(home) or { panic(err) }
	return home
}

fn editor_workflow_read(path string) string { return os.read_file(path) or { panic(err) } }

fn editor_workflow_choose_save_as(mut app TextEditorApp, path string) {
	app.begin_save_as()
	app.key_input('\x01')
	app.paste_input(path)
}

fn editor_workflow_find(element ui2.Element, id string) ?ui2.Element {
	if element.id == id { return element }
	for child in element.children { if found := editor_workflow_find(child, id) { return found } }
	return none
}

fn test_editor_workflow_close_requires_save_or_confirmed_discard_and_new_edits_revoke_it() {
	home := editor_workflow_home('close')
	path := join_path(home, 'document.txt')
	defer { os.rmdir_all(home) or {} unsafe { home.free() path.free() } }
	mut app := TextEditorApp{}
	defer { app.close_app() }
	app.set_path(path)
	assert app.prepare_close()
	app.key_input('Draft 日本😀')
	assert !app.prepare_close() && app.modified && app.pending_action == .close
	assert !os.exists(path)
	app.handle(editor_action_guard_save)!
	assert app.save_as_open && app.modified
	assert app.create_save_as() && app.prepare_close()
	stored := editor_workflow_read(path)
	assert stored == 'Draft 日本😀'
	unsafe { stored.free() }
	app.key_input(' changed')
	assert !app.prepare_close()
	app.handle(editor_action_confirm_discard)!
	assert !app.discard_close
	app.handle(editor_action_discard)!
	assert app.discard_pending && !app.prepare_close() && !app.discard_pending
	app.handle(editor_action_discard)!
	app.handle(editor_action_confirm_discard)!
	assert app.prepare_close() && app.modified
	app.focus = .query
	app.key_input('x')
	assert !app.discard_close && !app.prepare_close()
	app.handle(editor_action_keep_editing)!
	assert app.modified && app.pending_action == .none_
	app.focus = .document
	app.handle(editor_action_guard_save)!
	assert app.modified
	assert !app.prepare_close()
	app.handle(editor_action_guard_save)!
	assert !app.modified && app.prepare_close()
}

fn test_editor_workflow_open_saves_original_before_loading_latched_target() {
	home := editor_workflow_home('open-save')
	first := join_path(home, 'first.txt')
	second := join_path(home, 'second.txt')
	defer { os.rmdir_all(home) or {} unsafe { home.free() first.free() second.free() } }
	os.write_file(first, 'first')!
	os.write_file(second, 'second')!
	mut app := TextEditorApp{}
	defer { app.close_app() }
	app.set_path(first)
	app.open_document()
	app.key_input(' edited')
	app.set_path(second)
	app.key_input('\x0f')
	assert app.pending_action == .open_document && editor_bytes_text(app.text) == 'first edited'
	assert editor_bytes_text(app.pending_path) == second && editor_bytes_text(app.path) == first
	app.open_document()
	assert editor_bytes_text(app.pending_path) == second
	app.handle(editor_action_guard_save)!
	assert editor_bytes_text(app.text) == 'second' && !app.modified
	assert app.undo_history.len == 0 && app.pending_action == .none_
	stored_first := editor_workflow_read(first)
	stored_second := editor_workflow_read(second)
	assert stored_first == 'first edited' && stored_second == 'second'
	unsafe { stored_first.free() stored_second.free() }
}

fn test_editor_workflow_new_keep_editing_and_failed_open_preserve_draft_and_history() {
	home := editor_workflow_home('replace')
	missing := join_path(home, 'missing.txt')
	defer { os.rmdir_all(home) or {} unsafe { home.free() missing.free() } }
	mut app := TextEditorApp{}
	defer { app.close_app() }
	app.key_input('keep me')
	app.key_input('\x0e')
	assert app.pending_action == .new_document && editor_bytes_text(app.text) == 'keep me'
	app.handle(editor_action_keep_editing)!
	assert app.undo_history.len == 1 && app.modified
	app.set_path(missing)
	app.open_document()
	app.handle(editor_action_discard)!
	app.handle(editor_action_confirm_discard)!
	assert app.modified && editor_bytes_text(app.text) == 'keep me'
	assert app.pending_action == .open_document && app.status_key == 'editor.status.cannot_open'
	app.new_document()
	app.handle(editor_action_discard)!
	app.handle(editor_action_confirm_discard)!
	assert app.text.len == 0 && !app.modified && app.undo_history.len == 0
}

fn test_editor_workflow_save_as_preserves_existing_files_symlinks_and_original_identity() {
	home := editor_workflow_home('save-as')
	original := join_path(home, 'original.txt')
	existing := join_path(home, 'existing.txt')
	link := join_path(home, 'link.txt')
	created := join_path(home, 'created.txt')
	defer { os.rmdir_all(home) or {} unsafe { home.free() original.free() existing.free() link.free() created.free() } }
	os.write_file(original, 'original')!
	os.write_file(existing, 'preserve')!
	assert C.symlink(&char(existing.str), &char(link.str)) == 0
	mut app := TextEditorApp{}
	defer { app.close_app() }
	app.set_path(original)
	app.open_document()
	app.key_input(' 😀')
	for path in [existing, link]! {
		editor_workflow_choose_save_as(mut app, path)
		assert !app.create_save_as() && app.status_key == 'editor.workflow.exists'
		assert app.modified && editor_bytes_text(app.path) == original
	}
	editor_workflow_choose_save_as(mut app, '')
	assert !app.create_save_as() && app.status_key == 'editor.workflow.invalid_path'
	editor_workflow_choose_save_as(mut app, home)
	assert !app.create_save_as() && app.modified
	oversize := 'x'.repeat(editor_max_path + 1)
	editor_workflow_choose_save_as(mut app, oversize)
	assert app.save_as_path.len == 0 && !app.create_save_as() && app.modified
	unsafe { oversize.free() }
	editor_workflow_choose_save_as(mut app, created)
	assert app.create_save_as() && !app.modified && editor_bytes_text(app.document_path) == created
	app.key_input(' saved again')
	assert app.save_document()
	original_text := editor_workflow_read(original)
	existing_text := editor_workflow_read(existing)
	created_text := editor_workflow_read(created)
	assert original_text == 'original' && existing_text == 'preserve'
	assert created_text == 'original 😀 saved again'
	unsafe { original_text.free() existing_text.free() created_text.free() }
}

fn test_editor_workflow_failed_open_restores_original_path_before_any_later_save() {
	home := editor_workflow_home('failed-target')
	original := join_path(home, 'original.txt')
	missing := join_path(home, 'missing.txt')
	defer { os.rmdir_all(home) or {} unsafe { home.free() original.free() missing.free() } }
	os.write_file(original, 'original')!
	mut app := TextEditorApp{}
	defer { app.close_app() }
	app.set_path(original)
	app.open_document()
	app.key_input(' draft')
	app.set_path(missing)
	app.open_document()
	app.handle(editor_action_discard)!
	app.handle(editor_action_confirm_discard)!
	assert app.modified && editor_bytes_text(app.text) == 'original draft'
	assert editor_bytes_text(app.path) == original && editor_bytes_text(app.pending_path) == missing
	assert app.save_document() && !os.exists(missing)
	assert editor_bytes_text(app.path) == original && app.status_key == 'editor.status.cannot_open'
	stored := editor_workflow_read(original)
	assert stored == 'original draft'
	unsafe { stored.free() }
	assert app.prepare_close()
	app.key_input(' another')
	app.set_path(missing)
	app.open_document()
	app.handle(editor_action_guard_save)!
	assert !app.modified && editor_bytes_text(app.text) == 'original draft another'
	assert editor_bytes_text(app.path) == original && !os.exists(missing)
}

fn test_editor_workflow_save_as_can_complete_pending_new_and_preserve_empty_or_raw_text() {
	home := editor_workflow_home('new-save-as')
	path := join_path(home, 'saved.txt')
	empty_path := join_path(home, 'empty.txt')
	defer { os.rmdir_all(home) or {} unsafe { home.free() path.free() empty_path.free() } }
	mut app := TextEditorApp{}
	defer { app.close_app() }
	app.key_input('draft')
	app.new_document()
	app.handle(editor_action_guard_save)!
	assert app.save_as_open && app.pending_action == .new_document
	app.key_input('\x01')
	app.paste_input(path)
	assert app.create_save_as() && app.text.len == 0 && app.pending_action == .none_
	editor_workflow_choose_save_as(mut app, empty_path)
	assert app.create_save_as() && os.file_size(empty_path) == 0
	app.text << u8(0xff)
	app.modified = true
	assert app.save_document()
	bytes := os.read_bytes(empty_path)!
	assert bytes == [u8(0xff)]
	unsafe { bytes.free() }
}

fn test_editor_workflow_save_failure_keeps_close_denied_and_all_panel_actions_reachable() {
	mut app := TextEditorApp{}
	defer { app.close_app() }
	app.set_path('/missing-vinix-editor-directory/doc.txt')
	app.document_has_save = true
	editor_append(mut app.document_path, editor_bytes_text(app.path))
	app.key_input('draft')
	assert !app.prepare_close()
	app.handle(editor_action_guard_save)!
	assert app.modified && app.pending_action == .close && app.status_key == 'editor.status.cannot_save'
	app.find_open = true
	app.begin_save_as()
	app.handle(editor_action_discard)!
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 700, 500))!
	for id in [editor_action_save_as, editor_action_save_as_create, editor_action_save_as_cancel,
		editor_action_guard_save, editor_action_keep_editing, editor_action_discard, editor_action_confirm_discard]! {
		control := editor_workflow_find(tree, id) or { panic('missing editor workflow action') }
		assert control.enabled && control.frame.width > 0 && control.frame.height > 0
		assert control.frame.x >= 0 && control.frame.y >= 0 && control.frame.x + control.frame.width <= 700
	}
	assert app.visible_rows >= 1
	free_tree(tree)
	app.key_input('\x1b')
	assert !app.save_as_open && app.pending_action == .none_ && app.modified
}

fn test_editor_workflow_factory_and_new_use_active_user_home() {
	home := editor_workflow_home('home')
	previous := desktop_user_home
	desktop_user_home = home
	defer { desktop_user_home = previous os.rmdir_all(home) or {} unsafe { home.free() } }
	mut desktop := Desktop{}
	defer { unsafe { desktop.native_asset_icons.free() } }
	mut native := open_editor(mut desktop)!
	mut app := unsafe { &TextEditorApp(native) }
	defer { app.close_app() unsafe { free(app) } }
	expected := join_path(home, 'notes.txt')
	defer { unsafe { expected.free() } }
	assert native is TextEditorApp
	assert editor_bytes_text(app.path) == expected
	app.set_path('/other.txt')
	app.new_document()
	assert editor_bytes_text(app.path) == expected
}
