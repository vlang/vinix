// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

#include "@VMODROOT/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn editor_workflow_heap_home(name string) string {
	base := os.real_path(os.temp_dir())
	pid := os.getpid().str()
	home := '${base}/vinix-editor-workflow-heap-${pid}-${name}'
	unsafe { base.free() pid.free() }
	os.rmdir_all(home) or {}
	os.mkdir(home) or { panic(err) }
	return home
}

fn editor_workflow_heap_frames(mut app TextEditorApp) {
	for mode in 0 .. 4 {
		app.find_open = mode > 0
		app.save_as_open = mode > 1
		app.pending_action = if mode > 2 { EditorPendingAction.close } else { EditorPendingAction.none_ }
		app.discard_pending = mode > 2
		begin_frame_elements()
		tree := app.build(ui2.rect(0, 0, 700, 500)) or { panic(err) }
		free_tree(tree)
	}
}

fn test_editor_workflow_repeated_dirty_close_discard_edit_undo_new_and_cleanup_keep_zero_bytes() {
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut app := TextEditorApp{}
		app.set_path('/missing-vinix-editor/draft.txt')
		app.key_input('Draft 日本😀')
		assert !app.prepare_close()
		app.handle(editor_action_discard)!
		app.handle(editor_action_confirm_discard)!
		assert app.prepare_close()
		app.paste_input(' revised')
		assert !app.discard_close && !app.prepare_close()
		app.undo_edit()
		app.redo_edit()
		assert !app.prepare_close()
		app.new_document()
		app.handle(editor_action_discard)!
		app.handle(editor_action_confirm_discard)!
		assert app.text.len == 0 && !app.modified
		app.close_app()
		app.close_app()
	}
	assert C.vinix_heap_end() == 0
}

fn test_editor_workflow_repeated_save_as_save_open_and_failure_release_owned_buffers() {
	home := editor_workflow_heap_home('io')
	path := join_path(home, 'document.txt')
	defer { os.rmdir_all(home) or {} unsafe { home.free() path.free() } }
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut app := TextEditorApp{}
		app.set_path(path)
		app.key_input('日本😀 document')
		app.begin_save_as()
		assert app.create_save_as() && !app.modified
		app.key_input(' change')
		assert app.save_document()
		app.key_input(' discard')
		app.open_document()
		app.handle(editor_action_discard)!
		app.handle(editor_action_confirm_discard)!
		assert !app.modified && editor_bytes_text(app.text) == '日本😀 document change'
		app.key_input(' unsaved')
		app.begin_save_as()
		assert !app.create_save_as() && app.modified
		app.key_input('\x01')
		assert !app.create_save_as() && app.modified
		app.close_app()
		os.rm(path)!
	}
	assert C.vinix_heap_end() == 0
}

fn test_editor_workflow_all_panels_reuse_frame_storage_without_retained_text_clones() {
	mut warm := TextEditorApp{}
	warm.set_path('/tmp/editor-frame.txt')
	warm.key_input('one\ntwo 日本😀\nthree')
	editor_append(mut warm.query, 'two')
	editor_append(mut warm.replacement, 'replacement')
	warm.begin_save_as()
	editor_workflow_heap_frames(mut warm)
	warm.close_app()
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut app := TextEditorApp{}
		app.set_path('/tmp/editor-frame.txt')
		app.key_input('one\ntwo 日本😀\nthree')
		editor_append(mut app.query, 'two')
		editor_append(mut app.replacement, 'replacement')
		app.begin_save_as()
		editor_workflow_heap_frames(mut app)
		app.close_app()
	}
	assert C.vinix_heap_end() == 0
}

fn test_editor_workflow_native_guard_factory_home_lifetimes_release_zero_bytes() {
	home := editor_workflow_heap_home('factory')
	previous := desktop_user_home
	desktop_user_home = home
	defer { desktop_user_home = previous os.rmdir_all(home) or {} unsafe { home.free() } }
	mut desktop := Desktop{}
	defer { unsafe { desktop.native_asset_icons.free() } }
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut native := open_editor(mut desktop)!
		mut app := unsafe { &TextEditorApp(native) }
		app.key_input('protected')
		assert !native_app_prepare_close(mut native)
		app.handle(editor_action_discard)!
		app.handle(editor_action_confirm_discard)!
		assert native_app_prepare_close(mut native)
		app.close_app()
		unsafe { free(app) }
	}
	assert C.vinix_heap_end() == 0
}
