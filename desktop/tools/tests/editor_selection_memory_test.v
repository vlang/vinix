// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

#include "@VMODROOT/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn editor_selection_heap_frames(mut app TextEditorApp) {
	for language in [DesktopLanguage.en, .es, .ru]! {
		desktop_language = language
		for size in [ui2.rect(0, 0, 700, 500), ui2.rect(0, 0, 900, 600)]! {
			begin_frame_elements()
			free_tree(app.build(size) or { panic(err) })
		}
	}
}

fn test_editor_selection_typing_navigation_drag_highlight_and_history_release_owned_memory() {
	language := desktop_language
	defer { desktop_language = language }
	mut warm := TextEditorApp{}
	warm.paste_input('aй😀\nsecond\nthird')
	warm.select_document()
	editor_selection_heap_frames(mut warm)
	warm.close_app()
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut app := TextEditorApp{}
		app.paste_input('aй😀\nsecond\nthird')
		app.key_input('\x01')
		editor_selection_heap_frames(mut app)
		app.key_input('€')
		app.undo_edit()
		app.redo_edit()
		app.key_input('\x02\x1b[D')
		app.paste_input('replacement')
		app.pointer_event(.down, .left, 0, 10, 90, 700, 500)
		app.pointer_event(.move, .no_button, 0, 42, 90, 700, 500)
		app.pointer_event(.up, .left, 0, 42, 90, 700, 500)
		editor_selection_heap_frames(mut app)
		app.close_app()
		app.close_app()
	}
	assert C.vinix_heap_end() == 0
}

fn test_editor_selection_large_clipboard_replacement_and_successful_cut_keep_zero_bytes() {
	full := 'x'.repeat(clipboard_max_bytes)
	defer { unsafe { full.free() } }
	mut clipboard := HostClipboard{configured: true}
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut app := TextEditorApp{}
		app.paste_input(full)
		app.select_document()
		app.copy_selection(true)
		bytes := app.take_clipboard_copy_request()
		sequence := text_copy_into_session(mut clipboard, editor_bytes_text(bytes)) or { panic('copy refused') }
		assert clipboard.local_length == clipboard_max_bytes
		ack := text_copy_reply(sequence, true)
		app.receive_clipboard_copy_reply(editor_bytes_text(ack))
		assert app.text.len == 0
		app.undo_edit()
		assert app.text.len == clipboard_max_bytes && app.has_selection()
		app.paste_input('small')
		app.select_document()
		app.copy_selection(false)
		small := app.take_clipboard_copy_request()
		assert text_copy_into_session(mut clipboard, editor_bytes_text(small)) != none
		assert clipboard.local_length == 5
		unsafe { bytes.free() ack.free() small.free() }
		app.close_app()
	}
	assert C.vinix_heap_end() == 0
}

fn test_editor_selection_native_copy_interfaces_and_acknowledgements_free_wrappers() {
	mut desktop := Desktop{}
	defer { unsafe { desktop.native_asset_icons.free() } }
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut native := open_editor(mut desktop) or { panic(err) }
		mut app := unsafe { &TextEditorApp(native) }
		app.paste_input('copy 日本😀')
		app.select_document()
		app.copy_selection(true)
		bytes := native_app_text_copy_request(mut native)
		assert bytes.len > text_copy_header_size
		assert native_app_text_copy_request(mut native).len == 0
		ack := text_copy_reply(app.copy_sequence, true)
		native_app_receive_desktop_service(mut native, editor_bytes_text(ack))
		assert app.text.len == 0
		unsafe { bytes.free() ack.free() }
		app.close_app()
		unsafe { free(app) }
	}
	assert C.vinix_heap_end() == 0
}

fn test_editor_selection_failed_stale_cut_and_history_eviction_release_owned_bytes() {
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut app := TextEditorApp{}
		for _ in 0 .. 40 {
			app.key_input('draft 日本😀')
			app.select_document()
			app.copy_selection(true)
			bytes := app.take_clipboard_copy_request()
			bad := text_copy_reply(app.copy_sequence, false)
			app.receive_clipboard_copy_reply(editor_bytes_text(bad))
			assert app.text.len > 0 && app.has_selection()
			app.key_input('replacement')
			stale := text_copy_reply(app.copy_sequence, true)
			app.receive_clipboard_copy_reply(editor_bytes_text(stale))
			assert editor_bytes_text(app.text) == 'replacement'
			unsafe { bytes.free() bad.free() stale.free() }
		}
		app.close_app()
	}
	assert C.vinix_heap_end() == 0
}

fn test_editor_selection_clipboard_menu_paste_releases_query_storage() {
	C.vinix_heap_begin()
	for _ in 0 .. 200 {
		mut desktop := Desktop{start_menu_open: true}
		desktop.paste_start_menu_text('calc\n\x1b\x08\x00Привет\t😀')
		assert desktop.start_menu_open && desktop.apps.len == 0
		assert editor_bytes_text(desktop.start_menu_query) == 'calc Привет 😀'
		desktop.paste_start_menu_text(' second\nquery')
		unsafe {
			desktop.start_menu_query.free()
			desktop.native_asset_icons.free()
		}
	}
	assert C.vinix_heap_end() == 0
}
