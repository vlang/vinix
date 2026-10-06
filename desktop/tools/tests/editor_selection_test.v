// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn editor_selection_find(element ui2.Element, id string) ?ui2.Element {
	if element.id == id { return element }
	for child in element.children { if found := editor_selection_find(child, id) { return found } }
	return none
}

fn editor_selection_ack(mut app TextEditorApp, success bool) {
	request := app.take_clipboard_copy_request()
	assert request.len > text_copy_header_size
	reply := text_copy_reply(app.copy_sequence, success)
	app.receive_clipboard_copy_reply(editor_bytes_text(reply))
	unsafe { request.free() reply.free() }
}

fn test_editor_selection_select_all_and_replace_are_one_undoable_utf8_edit() {
	mut app := TextEditorApp{}
	defer { app.close_app() }
	app.paste_input('日本😀\nПривет')
	app.selection_marking = true
	app.selection_dragging = true
	app.key_input('\x01')
	assert app.has_selection() && app.cursor == app.text.len && app.selection_anchor == 0
	assert !app.selection_marking && !app.selection_dragging
	app.key_input('\x1b[C')
	assert app.cursor == app.text.len && !app.has_selection()
	app.key_input('\x01')
	app.key_input('€')
	assert editor_bytes_text(app.text) == '€' && !app.has_selection()
	app.undo_edit()
	assert editor_bytes_text(app.text) == '日本😀\nПривет' && app.has_selection()
	app.redo_edit()
	assert editor_bytes_text(app.text) == '€' && !app.has_selection()
}

fn test_editor_selection_shift_navigation_and_native_mark_use_character_boundaries() {
	mut app := TextEditorApp{}
	defer { app.close_app() }
	app.paste_input('aй€😀')
	app.key_input('\x1b[1;2D\x1b[1;2D')
	start, end := app.selection_bounds()
	assert start == 3 && end == app.text.len
	app.key_input('\x1b[D')
	assert app.cursor == start && !app.has_selection()
	app.key_input('\x02\x1b[D\x1b[D')
	marked_start, marked_end := app.selection_bounds()
	assert marked_start == 0 && marked_end == 3 && app.selection_marking
	app.key_input('Z')
	assert editor_bytes_text(app.text) == 'Z€😀' && !app.selection_marking
}

fn test_editor_selection_delete_backspace_tabs_and_paste_replace_the_range() {
	for input in ['\x7f', '\x1b[3~', '\t']! {
		mut app := TextEditorApp{}
		app.paste_input('first\nsecond')
		app.select_document()
		app.key_input(input)
		assert editor_bytes_text(app.text) == if input == '\t' { '    ' } else { '' }
		app.undo_edit()
		assert editor_bytes_text(app.text) == 'first\nsecond' && app.has_selection()
		app.paste_input('replacement')
		assert editor_bytes_text(app.text) == 'replacement'
		app.close_app()
	}
}

fn test_editor_selection_limits_preserve_document_selection_and_history() {
	mut app := TextEditorApp{text: []u8{len: editor_max_file_size, init: `x`}, cursor: editor_max_file_size, selection_anchor: editor_max_file_size - 1}
	defer { app.close_app() }
	app.key_input('€')
	assert app.text.len == editor_max_file_size && app.has_selection() && app.undo_history.len == 0
	app.key_input('\t')
	assert app.text.len == editor_max_file_size && app.has_selection() && app.undo_history.len == 0
	app.paste_input('ab')
	assert app.text.len == editor_max_file_size && app.has_selection() && app.undo_history.len == 0
	app.key_input('z')
	assert app.text.len == editor_max_file_size && app.text[app.text.len - 1] == `z`
	assert app.undo_history.len == 1 && !app.has_selection()
}

fn test_editor_selection_pointer_drag_multiline_highlight_and_scroll_stay_visible() {
	mut app := TextEditorApp{}
	defer { app.close_app() }
	app.paste_input('aй😀\nsecond\nthird\nfourth\nfifth')
	app.scroll = 0
	begin_frame_elements()
	free_tree(app.build(ui2.rect(0, 0, 700, 180))!)
	app.pointer_event(.down, .left, 0, 18, 90, 700, 180)
	assert app.cursor == 1 && app.selection_dragging
	app.pointer_event(.move, .no_button, 0, 26, 108, 700, 180)
	assert app.cursor == 10 && app.has_selection()
	app.pointer_event(.up, .left, 0, 26, 108, 700, 180)
	assert !app.selection_dragging && !app.pointer_moves_matter()
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 700, 180))!
	assert editor_selection_find(tree, 'editor.selection.highlight') != none
	free_tree(tree)
	app.pointer_event(.scroll, .no_button, -1, 26, 108, 700, 180)
	scrolled := app.scroll
	assert scrolled > 0
	begin_frame_elements()
	free_tree(app.build(ui2.rect(0, 0, 700, 180))!)
	assert app.scroll == scrolled
}

fn test_editor_selection_pointer_uses_find_save_and_guard_document_offset() {
	mut app := TextEditorApp{}
	defer { app.close_app() }
	app.paste_input('ab😀cd')
	app.find_open = true
	app.save_as_open = true
	app.pending_action = .close
	begin_frame_elements()
	free_tree(app.build(ui2.rect(0, 0, 700, 500))!)
	top := app.document_top()
	app.pointer_event(.down, .left, 0, 26, top + 10, 700, 500)
	assert app.cursor == 2 && app.focus == .document
	app.pointer_event(.up, .left, 0, 34, top + 10, 700, 500)
	assert app.cursor == 6
	before := app.cursor
	app.pointer_event(.down, .left, 0, 26, 50, 700, 500)
	assert app.cursor == before
}

fn test_editor_selection_csi_stream_fragments_and_unknown_sequences_do_not_type_tails() {
	mut app := TextEditorApp{}
	defer { app.close_app() }
	app.paste_input('abc😀')
	app.key_input('\x1b')
	assert app.key_csi_active && app.key_csi_len == -1 && app.next_poll_ms() == 100
	assert !app.expire_key_escape(app.key_csi_ms + 99)
	app.key_input('[')
	app.key_input('1;')
	app.key_input('2D')
	assert app.cursor == 3 && app.selection_anchor == 7
	assert !app.key_csi_active && app.next_poll_ms() == 2000
	app.key_input('\x1b[123456789012345678901234567890~')
	assert editor_bytes_text(app.text) == 'abc😀'
	app.key_input('\x1b[99;8C')
	assert app.cursor == 3 && app.has_selection()
	app.key_input('\x1b[12\x1b')
	app.key_input('[1;2D')
	assert app.cursor == 2 && app.selection_anchor == 7
	assert editor_bytes_text(app.text) == 'abc😀'
	app.find_open = true
	app.key_input('\x1b')
	assert app.find_open && app.has_selection()
	assert app.expire_key_escape(app.key_csi_ms + 100)
	assert !app.find_open && !app.has_selection() && !app.key_csi_active
	assert !app.expire_key_escape(app.key_csi_ms + 100)
	app.key_input('\x1b[999')
	assert app.expire_key_escape(app.key_csi_ms + 100)
	assert editor_bytes_text(app.text) == 'abc😀'
	app.focus = .query
	app.key_input('\x1b[1;2D')
	assert app.query.len == 0 && app.cursor == 2
	app.pointer_event(.down, .left, 0, 10, 90, 0, 180)
	assert app.cursor == 2 && app.focus == .query
}

fn test_editor_selection_copy_preserves_raw_bytes_and_document_revision() {
	mut app := TextEditorApp{}
	defer { app.close_app() }
	app.paste_input('a\xff日本\n\t\x00')
	app.select_document()
	app.copy_selection(false)
	request := app.take_clipboard_copy_request()
	defer { unsafe { request.free() } }
	assert request.len == text_copy_header_size + app.text.len
	mut clipboard := HostClipboard{}
	sequence := text_copy_into_session(mut clipboard, editor_bytes_text(request)) or { panic('copy refused') }
	assert sequence == app.copy_sequence
	assert unsafe { tos(&clipboard.local_bytes[0], clipboard.local_length) } == editor_bytes_text(app.text)
	revision := app.revision
	ack := text_copy_reply(sequence, true)
	app.receive_clipboard_copy_reply(editor_bytes_text(ack))
	unsafe { ack.free() }
	assert app.revision == revision && app.has_selection() && app.copy_text.len == 0
}

fn test_editor_selection_cut_requires_matching_success_and_undo_restores_selection() {
	mut app := TextEditorApp{}
	defer { app.close_app() }
	app.paste_input('draft 日本😀')
	app.select_document()
	app.copy_selection(true)
	assert app.text.len > 0
	editor_selection_ack(mut app, false)
	assert editor_bytes_text(app.text) == 'draft 日本😀' && app.has_selection()
	app.copy_selection(true)
	request := app.take_clipboard_copy_request()
	wrong := text_copy_reply(app.copy_sequence + 1, true)
	app.receive_clipboard_copy_reply(editor_bytes_text(wrong))
	assert app.text.len > 0 && app.copy_waiting
	ack := text_copy_reply(app.copy_sequence, true)
	app.receive_clipboard_copy_reply(editor_bytes_text(ack))
	unsafe { request.free() wrong.free() ack.free() }
	assert app.text.len == 0 && app.modified && !app.has_selection()
	app.undo_edit()
	assert editor_bytes_text(app.text) == 'draft 日本😀' && app.has_selection()
}

fn test_editor_selection_changed_document_and_old_compositor_do_not_cut() {
	mut app := TextEditorApp{}
	defer { app.close_app() }
	app.paste_input('keep')
	app.select_document()
	app.copy_selection(true)
	request := app.take_clipboard_copy_request()
	app.key_input('new')
	ack := text_copy_reply(app.copy_sequence, true)
	app.receive_clipboard_copy_reply(editor_bytes_text(ack))
	unsafe { request.free() ack.free() }
	assert editor_bytes_text(app.text) == 'new'
	app.select_document()
	features := app_compositor_features
	app_compositor_features &= ~app_feature_text_copy
	defer { app_compositor_features = features }
	app.copy_selection(true)
	assert !app.copy_queued && editor_bytes_text(app.text) == 'new'
	assert app.status_key == 'editor.selection.unavailable'
}

fn test_editor_selection_clipboard_bounds_and_malformed_packets_preserve_last_copy() {
	full := 'x'.repeat(clipboard_max_bytes)
	oversize := full + 'x'
	defer { unsafe { full.free() oversize.free() } }
	mut clipboard := HostClipboard{}
	assert clipboard.set_local_text(full)
	assert !clipboard.set_local_text(oversize) && clipboard.local_length == clipboard_max_bytes
	assert text_copy_request(0, 'bad').len == 0
	assert text_copy_request(1, oversize).len == 0
	mut bytes := text_copy_request(17, 'new text')
	defer { unsafe { bytes.free() } }
	bytes[8]++
	assert text_copy_into_session(mut clipboard, editor_bytes_text(bytes)) == none
	assert clipboard.local_length == clipboard_max_bytes
	bytes[8]--
	bytes[0]++
	assert text_copy_into_session(mut clipboard, editor_bytes_text(bytes)) == none
	assert clipboard.local_length == clipboard_max_bytes
	bytes[0]--
	sequence := text_copy_into_session(mut clipboard, editor_bytes_text(bytes)) or { panic('valid copy refused') }
	assert sequence == 17
	assert unsafe { tos(&clipboard.local_bytes[0], clipboard.local_length) } == 'new text'
}

fn test_editor_selection_service_capabilities_do_not_grant_screen_or_external_access() {
	mut desktop := Desktop{}
	defer { unsafe { desktop.native_asset_icons.free() } }
	assert desktop.clipboard.set_local_text('preserved')
	bytes := text_copy_request(1, 'other')
	defer { unsafe { bytes.free() } }
	mut untrusted := RemoteApp{desktop: &desktop, peer_features: app_features}
	assert !untrusted.handle_native_operation(editor_bytes_text(bytes))
	untrusted.clipboard_copy = true
	untrusted.standalone = true
	assert !untrusted.handle_native_operation(editor_bytes_text(bytes))
	untrusted.standalone = false
	untrusted.peer_features &= ~app_feature_text_copy
	assert !untrusted.handle_native_operation(editor_bytes_text(bytes))
	assert unsafe { tos(&desktop.clipboard.local_bytes[0], desktop.clipboard.local_length) } == 'preserved'
	factory := app_factory_named('vinix-editor') or { panic('missing Editor') }
	assert factory.pointer && factory.clipboard_copy && !factory.desktop_services
}

fn test_editor_selection_clipboard_menu_paste_never_executes_copied_control_keys() {
	mut desktop := Desktop{start_menu_open: true, start_menu_all_apps: true}
	defer { desktop.free_start_menu_query() unsafe { desktop.native_asset_icons.free() } }
	assert desktop.clipboard.set_local_text('calc\n\x1b\x08\x00Привет\t😀')
	desktop.request_paste(false)
	assert desktop.start_menu_open && desktop.windows.len == 0 && desktop.apps.len == 0
	assert desktop.start_menu_query_text() == 'calc Привет 😀'
	assert desktop.start_menu_page == 0 && !desktop.start_menu_all_apps && desktop.dirty
	long := 'x'.repeat(start_menu_max_query - 1)
	defer { unsafe { long.free() } }
	desktop.start_menu_query.clear()
	desktop.paste_start_menu_text(long)
	desktop.paste_start_menu_text('😀')
	assert desktop.start_menu_query.len == start_menu_max_query - 1
}
