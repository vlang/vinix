// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

#include "@VMODROOT/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn terminal_selection_memory_output(mut app TerminalApp, text string) {
	app.ingest_output(unsafe { text.str.vbytes(text.len) })
}

fn terminal_selection_memory_frames(mut app TerminalApp) {
	for language in [DesktopLanguage.en, .es, .ru]! {
		desktop_language = language
		for size in [ui2.rect(0, 0, 560, 340), ui2.rect(0, 0, 640, 380)]! {
			begin_frame_elements()
			free_tree(app.build(size) or { panic(err) })
			app.pointer_event(.down, .left, 0, 8, 42, int(size.width), int(size.height))
			app.pointer_event(.move, .no_button, 0, 72, 58, int(size.width), int(size.height))
			app.pointer_event(.up, .left, 0, 72, 58, int(size.width), int(size.height))
			begin_frame_elements()
			free_tree(app.build(size) or { panic(err) })
		}
	}
}

fn test_terminal_selection_repeated_models_history_eviction_resize_alternate_render_and_close_retain_zero_bytes() {
	language := desktop_language
	defer { desktop_language = language }
	mut warm := TerminalApp{exited: true}
	terminal_selection_memory_frames(mut warm)
	warm.close_app()
	C.vinix_heap_begin()
	for _ in 0 .. 50 {
		mut app := TerminalApp{exited: true, read_buf: []u8{len: terminal_read_chunk}}
		app.set_geometry(2, 40)
		for _ in 0 .. terminal_scrollback + 8 { terminal_selection_memory_output(mut app, 'history й😀\r\n') }
		assert app.lines.len == terminal_scrollback
		terminal_selection_memory_frames(mut app)
		app.enter_alternate_screen()
		terminal_selection_memory_output(mut app, 'alternate é😀')
		terminal_selection_memory_frames(mut app)
		app.leave_alternate_screen()
		app.clear_scrollback()
		app.close_app()
		app.close_app()
	}
	assert C.vinix_heap_end() == 0
}

fn test_terminal_selection_native_pointer_and_copy_dispatch_transfer_and_release_every_snapshot() {
	features := app_compositor_features
	defer { app_compositor_features = features }
	app_compositor_features |= app_feature_text_copy
	mut desktop := Desktop{}
	defer { unsafe { desktop.native_asset_icons.free() } }
	mut clipboard := HostClipboard{configured: true}
	C.vinix_heap_begin()
	for _ in 0 .. 200 {
		mut native := open_terminal(mut desktop) or { panic(err) }
		mut app := unsafe { &TerminalApp(native) }
		app.exited = true
		app.set_geometry(2, 20)
		app.visible_rows = 2
		terminal_selection_memory_output(mut app, 'copy й😀')
		app.pointer_event(.down, .left, 0, 8, 42, 176, 102)
		app.pointer_event(.up, .left, 0, 64, 42, 176, 102)
		app.handle(terminal_action_copy) or { panic(err) }
		request := native_app_text_copy_request(mut native)
		sequence := text_copy_into_session(mut clipboard, editor_bytes_text(request)) or { panic('copy refused') }
		assert clipboard.local_length == 'copy й😀'.len
		ack := text_copy_reply(sequence, true)
		native_app_receive_desktop_service(mut native, editor_bytes_text(ack))
		assert app.copy_client.status_key() == 'clipboard.copy.copied'
		unsafe { request.free() ack.free() }
		app.close_app()
		unsafe { free(app) }
	}
	assert C.vinix_heap_end() == 0
}

fn test_terminal_selection_large_copies_overflow_rejection_and_replaced_requests_retain_zero_bytes() {
	features := app_compositor_features
	defer { app_compositor_features = features }
	app_compositor_features |= app_feature_text_copy
	large := 'é'.repeat(clipboard_max_bytes / 2)
	defer { unsafe { large.free() } }
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut app := TerminalApp{exited: true}
		app.set_geometry(2, 20)
		app.lines << large.clone()
		app.selection_anchor = TerminalSelectionPoint{row: 0}
		app.selection_head = TerminalSelectionPoint{row: 0, column: clipboard_max_bytes / 2}
		app.copy_selection()
		old := app.take_clipboard_copy_request()
		assert old.len == text_copy_header_size + clipboard_max_bytes
		ack := text_copy_reply(app.copy_client.sequence, true)
		app.selection_head = TerminalSelectionPoint{row: 1}
		app.copy_selection()
		app.receive_clipboard_copy_reply(editor_bytes_text(ack))
		assert app.copy_client.status_key() == 'clipboard.copy.too_large'
		app.selection_head = TerminalSelectionPoint{row: 0, column: 2}
		app.copy_selection()
		app.copy_selection() // replace a still client-owned packet
		new_request := app.take_clipboard_copy_request()
		app.receive_clipboard_copy_reply(editor_bytes_text(ack))
		assert app.copy_client.status_key() == 'clipboard.copy.pending'
		failed := text_copy_reply(app.copy_client.sequence, false)
		app.receive_clipboard_copy_reply(editor_bytes_text(failed))
		assert app.copy_client.status_key() == 'clipboard.copy.failed'
		unsafe { old.free() new_request.free() ack.free() failed.free() }
		app.close_app()
	}
	assert C.vinix_heap_end() == 0
}

fn test_terminal_selection_fragmented_copy_keys_literal_paste_and_escape_expiry_retain_zero_bytes() {
	features := app_compositor_features
	defer { app_compositor_features = features }
	app_compositor_features |= app_feature_text_copy
	mut pipe := [2]i32{}
	assert C.pipe(&pipe[0]) == 0
	mut app := TerminalApp{terminal: int(pipe[1]), started: true}
	defer { app.close_app(); desktop_close(pipe[0]) }
	app.set_geometry(2, 20)
	app.visible_rows = 2
	terminal_selection_memory_output(mut app, 'copy й😀')
	app.pointer_event(.down, .left, 0, 8, 42, 176, 102)
	app.pointer_event(.up, .left, 0, 64, 42, 176, 102)
	C.vinix_heap_begin()
	for _ in 0 .. 200 {
		for byte in terminal_key_cmd_copy {
			one := [byte]!
			app.key_input(unsafe { tos(&one[0], 1) })
		}
		request := app.take_clipboard_copy_request()
		assert request.len == text_copy_header_size + 'copy й😀'.len
		unsafe { request.free() }
		app.key_input('\x03\x1b[D\x1b[99;6u')
		app.key_input('\x1b\x1b[99;9u')
		nested := app.take_clipboard_copy_request()
		assert nested.len == text_copy_header_size + 'copy й😀'.len
		unsafe { nested.free() }
		app.paste_input(terminal_key_cmd_copy)
		app.key_input('\x1b[')
		assert app.expire_copy_key(app.copy_key_ms + 100)
		mut buffer := [64]u8{}
		got := desktop_read(pipe[0], &buffer[0], u64(buffer.len))
		assert unsafe { tos(&buffer[0], int(got)) } == '\x03\x1b[D\x1b[99;6u\x1b\x1b[99;9u\x1b['
	}
	assert C.vinix_heap_end() == 0
}
