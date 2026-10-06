// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn editor_features_find(element ui2.Element, id string) ?ui2.Element {
	if element.id == id { return element }
	for child in element.children {
		if found := editor_features_find(child, id) { return found }
	}
	return none
}

fn test_editor_undo_redo_groups_typing_tabs_and_utf8_characters() {
	mut editor := TextEditorApp{}
	editor.key_input('Привет\tworld')
	assert editor.undo_history.len == 1
	assert editor_bytes_text(editor.text) == 'Привет    world'
	editor.key_input('\x1a')
	assert editor.text.len == 0
	assert editor.cursor == 0
	assert !editor.modified
	editor.key_input('\x19')
	assert editor_bytes_text(editor.text) == 'Привет    world'
	assert editor.cursor == editor.text.len
	assert editor.modified

	// A split UTF-8 character still needs exactly one reversible edit.
	editor.key_input('\xd0')
	assert editor.undo_history.len == 1
	editor.key_input('\xb9')
	assert editor.undo_history.len == 2
	editor.undo_edit()
	assert editor_bytes_text(editor.text) == 'Привет    world'
	editor.redo_edit()
	assert editor_bytes_text(editor.text) == 'Привет    worldй'
}

fn test_editor_history_preserves_delete_cursor_and_invalidates_redo_after_edit() {
	mut editor := TextEditorApp{}
	editor.key_input('aй€b')
	editor.key_input('\x1b[H\x1b[C\x1b[3~')
	assert editor_bytes_text(editor.text) == 'a€b'
	assert editor.cursor == 1
	editor.undo_edit()
	assert editor_bytes_text(editor.text) == 'aй€b'
	assert editor.cursor == 1
	editor.redo_edit()
	assert editor_bytes_text(editor.text) == 'a€b'
	editor.undo_edit()
	editor.key_input('!')
	assert editor.redo_history.len == 0
	editor.redo_edit()
	assert editor_bytes_text(editor.text) == 'a!й€b'

	// Navigation inside one read splits its two typing runs.
	editor.new_document()
	editor.handle(editor_action_discard)!
	editor.handle(editor_action_confirm_discard)!
	editor.key_input('one\x1b[Htwo')
	assert editor.undo_history.len == 2
	editor.undo_edit()
	assert editor_bytes_text(editor.text) == 'one'
	assert editor.cursor == 0
	editor.undo_edit()
	assert editor.text.len == 0
}

fn test_editor_paste_is_one_edit_and_document_limits_do_not_create_history() {
	mut editor := TextEditorApp{}
	editor.paste_input('one\ntwo\nтри')
	assert editor.undo_history.len == 1
	editor.undo_edit()
	assert editor.text.len == 0
	editor.redo_edit()
	assert editor_bytes_text(editor.text) == 'one\ntwo\nтри'
	editor.new_document()
	editor.handle(editor_action_discard)!
	editor.handle(editor_action_confirm_discard)!
	editor.text = []u8{len: editor_max_file_size, init: `a`}
	editor.cursor = editor.text.len
	editor.key_input('bй')
	editor.paste_input('x')
	assert editor.undo_history.len == 0
	assert editor.text.len == editor_max_file_size
}

fn test_editor_history_is_bounded_across_undo_and_redo() {
	mut editor := TextEditorApp{}
	for _ in 0 .. editor_history_limit + 10 { editor.key_input('a') }
	assert editor.undo_history.len == editor_history_limit
	for _ in 0 .. editor_history_limit { editor.undo_edit() }
	assert editor.text.len == 10
	assert editor.undo_history.len == 0
	assert editor.redo_history.len == editor_history_limit
	editor.undo_edit()
	assert editor.text.len == 10
	for _ in 0 .. editor_history_limit { editor.redo_edit() }
	assert editor.text.len == editor_history_limit + 10
	assert editor.undo_history.len + editor.redo_history.len == editor_history_limit
	editor.key_input('b')
	assert editor.undo_history.len == editor_history_limit
}

fn test_editor_history_tracks_saved_state_and_open_new_clear_old_history() {
	path := os.join_path(os.temp_dir(), 'vinix-editor-history-features.txt')
	defer { os.rm(path) or {} }
	mut editor := TextEditorApp{}
	editor.set_path(path)
	editor.key_input('saved')
	editor.save_document()
	assert !editor.modified
	editor.key_input(' edit')
	assert editor.modified
	editor.undo_edit()
	assert editor_bytes_text(editor.text) == 'saved'
	assert !editor.modified
	editor.redo_edit()
	assert editor.modified
	editor.save_document()
	editor.undo_edit()
	assert editor.modified
	editor.redo_edit()
	assert !editor.modified
	editor.open_document()
	assert editor.undo_history.len == 0 && editor.redo_history.len == 0
	editor.undo_edit()
	assert editor_bytes_text(editor.text) == 'saved edit'
	editor.key_input('!')
	editor.new_document()
	editor.handle(editor_action_discard)!
	editor.handle(editor_action_confirm_discard)!
	assert editor.undo_history.len == 0 && editor.redo_history.len == 0
	assert !editor.modified
}

fn test_editor_shortened_path_opens_and_saves_only_the_displayed_file() {
	root := os.join_path(os.temp_dir(), 'vinix-editor-short-path-${os.getpid()}')
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {}; unsafe { root.free() } }
	short_path := join_path(root, 'note.txt')
	long_path := '${short_path}.long'
	defer { unsafe { short_path.free(); long_path.free() } }
	os.write_file(long_path, 'long document')!
	os.write_file(short_path, 'short document')!
	mut editor := TextEditorApp{}
	defer { editor.close_app() }
	editor.set_path(long_path)
	editor.open_document()
	assert editor_bytes_text(editor.text) == 'long document'
	editor.set_path(short_path)
	editor.open_document()
	assert editor_bytes_text(editor.text) == 'short document'
	editor.key_input('!')
	editor.save_document()
	assert os.read_file(short_path)! == 'short document!'
	assert os.read_file(long_path)! == 'long document'
}

fn test_editor_find_wraps_forward_backward_and_respects_utf8_boundaries() {
	mut editor := TextEditorApp{}
	editor.key_input('йй abc йй\nend')
	editor.query = 'йй'.bytes()
	editor.find_match(false)
	assert editor.match_start == 0 && editor.match_end == 4
	editor.find_match(false)
	assert editor.match_start == 9
	editor.find_match(false)
	assert editor.match_start == 0
	editor.find_match(true)
	assert editor.match_start == 9
	editor.find_match(true)
	assert editor.match_start == 0
	editor.query = [u8(0xb9)]
	editor.clear_match()
	editor.find_match(false)
	assert editor.match_start == -1
	assert !editor_match_at('й'.bytes(), [u8(0xd0)], 0)
	assert editor_match_at([u8(0xb9)], [u8(0xb9)], 0)
	editor.query.clear()
	editor.find_match(false)
	assert editor.match_start == -1
}

fn test_editor_find_fields_take_utf8_and_escape_without_editing_document() {
	mut editor := TextEditorApp{}
	editor.key_input('hello café hello')
	editor.key_input('\x06café\n')
	assert editor.find_open && editor.focus == .query
	assert editor_bytes_text(editor.query) == 'café'
	assert editor.match_start == 6
	editor.key_input('\x1b[D')
	assert editor_bytes_text(editor.query) == 'café'
	editor.key_input('\x7f')
	assert editor_bytes_text(editor.query) == 'caf'
	assert editor.match_start == -1
	editor.key_input('\t')
	editor.paste_input('замена')
	assert editor.focus == .replacement
	assert editor_bytes_text(editor.replacement) == 'замена'
	assert editor.undo_history.len == 1
	editor.key_input('\x1b')
	assert editor.find_open
	assert editor.expire_key_escape(editor.key_csi_ms + 100)
	assert !editor.find_open && editor.focus == .document
	assert editor_bytes_text(editor.text) == 'hello café hello'
}

fn test_editor_replace_one_and_all_are_atomic_undoable_edits() {
	mut editor := TextEditorApp{}
	editor.key_input('cat cat\ncat')
	editor.query = 'cat'.bytes()
	editor.replacement = 'кот'.bytes()
	editor.replace_match()
	assert editor_bytes_text(editor.text) == 'кот cat\ncat'
	assert editor.match_start == 7
	assert editor.undo_history.len == 2
	editor.undo_edit()
	assert editor_bytes_text(editor.text) == 'cat cat\ncat'
	editor.redo_edit()
	editor.replace_all()
	assert editor_bytes_text(editor.text) == 'кот кот\nкот'
	assert editor.undo_history.len == 3
	editor.undo_edit()
	assert editor_bytes_text(editor.text) == 'кот cat\ncat'
	editor.redo_edit()
	editor.query = 'кот'.bytes()
	editor.replacement.clear()
	editor.replace_all()
	assert editor_bytes_text(editor.text) == ' \n'
	editor.undo_edit()
	assert editor_bytes_text(editor.text) == 'кот кот\nкот'
}

fn test_editor_replace_all_is_non_overlapping_and_preserves_raw_bytes() {
	mut editor := TextEditorApp{}
	editor.paste_input('aaaa й\xff')
	editor.query = 'aa'.bytes()
	editor.replacement = 'x'.bytes()
	editor.replace_all()
	assert editor_bytes_text(editor.text) == 'xx й\xff'
	editor.undo_edit()
	assert editor_bytes_text(editor.text) == 'aaaa й\xff'
	editor.query = [u8(0xb9)]
	editor.replace_all()
	assert editor_bytes_text(editor.text) == 'aaaa й\xff'
}

fn test_editor_replace_refuses_over_limit_without_changing_document_or_history() {
	mut editor := TextEditorApp{}
	editor.text = []u8{len: editor_max_file_size, init: `a`}
	editor.query = 'a'.bytes()
	editor.replacement = 'aa'.bytes()
	editor.find_match(false)
	editor.replace_match()
	assert editor.text.len == editor_max_file_size
	assert editor.match_start == 0
	assert editor.undo_history.len == 0
	editor.replace_all()
	assert editor.text.len == editor_max_file_size
	assert editor.undo_history.len == 0
	assert !editor.modified
}

fn test_editor_toolbar_exposes_history_find_and_whole_character_highlight() {
	mut editor := TextEditorApp{}
	begin_frame_elements()
	initial := editor.build(ui2.rect(0, 0, 700, 500))!
	initial_undo := editor_features_find(initial, editor_action_undo) or { panic('missing Undo') }
	assert !initial_undo.enabled
	initial_redo := editor_features_find(initial, editor_action_redo) or { panic('missing Redo') }
	assert !initial_redo.enabled
	assert editor_features_find(initial, editor_action_find) != none
	editor.key_input('й€ test')
	editor.handle(editor_action_find)!
	editor.key_input('й€\n')
	begin_frame_elements()
	tree := editor.build(ui2.rect(0, 0, 700, 500))!
	undo := editor_features_find(tree, editor_action_undo) or { panic('missing Undo') }
	assert undo.enabled
	assert editor_features_find(tree, editor_action_query) != none
	assert editor_features_find(tree, editor_action_replace_all) != none
	highlight := editor_features_find(tree, 'editor.find.highlight') or { panic('missing highlight') }
	assert int(highlight.frame.width) == 2 * editor_character_width
	assert int(highlight.frame.x) == editor_padding
	editor.handle(editor_action_undo)!
	assert editor.text.len == 0
	editor.handle(editor_action_redo)!
	assert editor_bytes_text(editor.text) == 'й€ test'
	editor.handle(editor_action_find_close)!
	assert !editor.find_open
}

fn test_editor_close_releases_document_fields_and_both_history_stacks() {
	mut editor := TextEditorApp{}
	editor.set_path('/tmp/history.txt')
	editor.key_input('first')
	editor.key_input(' second')
	editor.undo_edit()
	editor.query = 'first'.bytes()
	editor.replacement = 'new'.bytes()
	editor.close_app()
	assert editor.text.len == 0 && editor.path.len == 0 && editor.status.len == 0
	assert editor.undo_history.len == 0 && editor.redo_history.len == 0
	assert editor.query.len == 0 && editor.replacement.len == 0
	editor.close_app()
}
