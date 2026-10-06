// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

#include "@VMODROOT/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32
fn C.vinix_heap_size_at(u32) u64

fn terminal_selection_memory_output(mut app TerminalApp, text string) {
	app.ingest_output(unsafe { text.str.vbytes(text.len) })
}

fn terminal_selection_memory_frames(mut app TerminalApp) {
	for language in desktop_languages {
		desktop_language = language
		for size in [ui2.rect(0, 0, 272, 118), ui2.rect(0, 0, 560, 340), ui2.rect(0, 0, 640, 380)]! {
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

fn test_terminal_selection_word_line_click_drag_copy_history_mutation_and_render_retain_zero_bytes() {
	features := app_compositor_features
	language := desktop_language
	defer { app_compositor_features = features; desktop_language = language }
	app_compositor_features |= app_feature_text_copy
	// Warm the shared translation/frame arenas before measuring app ownership.
	mut warm := TerminalApp{exited: true}
	terminal_selection_memory_frames(mut warm)
	warm.close_app()
	C.vinix_heap_begin()
	for iteration in 0 .. 100 {
		mut app := TerminalApp{exited: true}
		app.set_geometry(3, 32)
		app.visible_rows = 3
		terminal_selection_memory_output(mut app, 'old cafe\u0301 й😀\r\n\r\nthird\r\nlast')
		app.scroll = app.lines.len
		for count in 0 .. 3 {
			app.selection_pointer_event_at(.down, .left, 0, 50, 42, 272, 118, u64(1000 + count * 100))
			app.selection_pointer_event_at(.up, .left, 0, 50, 42, 272, 118, u64(1020 + count * 100))
			if count > 0 {
				app.copy_selection()
				request := app.take_clipboard_copy_request()
				assert request.len > text_copy_header_size
				unsafe { request.free() }
			}
		}
		app.selection_pointer_event_at(.down, .left, 0, 50, 58, 272, 118, 2000)
		app.selection_pointer_event_at(.up, .left, 0, 50, 58, 272, 118, 2020)
		app.selection_pointer_event_at(.down, .left, 0, 50, 58, 272, 118, 2100)
		app.selection_pointer_event_at(.move, .no_button, 0, 10, 42, 272, 118, 2200)
		app.selection_pointer_event_at(.move, .no_button, 0, 50, 95, 272, 118, 2300)
		app.selection_pointer_event_at(.up, .left, 0, 50, 95, 272, 118, 2400)
		app.copy_selection()
		app.copy_selection()
		request := app.take_clipboard_copy_request()
		assert request.len > text_copy_header_size
		unsafe { request.free() }
		for lang in desktop_languages {
			desktop_language = lang
			begin_frame_elements()
			free_tree(app.build(ui2.rect(0, 0, 272, 118)) or { panic(err) })
		}
		terminal_selection_memory_output(mut app, 'changed')
		assert app.selection_click.count == 0 && !app.has_selection()
		app.enter_alternate_screen()
		terminal_selection_memory_output(mut app, 'alternate й\r\nrow')
		for count in 0 .. 3 {
			app.selection_pointer_event_at(.down, .left, 0, 18, 42, 272, 118, u64(3000 + count * 100))
			app.selection_pointer_event_at(.up, .left, 0, 18, 42, 272, 118, u64(3020 + count * 100))
		}
		app.copy_selection()
		alternate_request := app.take_clipboard_copy_request()
		assert alternate_request.len > text_copy_header_size
		unsafe { alternate_request.free() }
		app.leave_alternate_screen()
		if iteration % 2 == 0 { app.set_geometry(2, 24) } else { app.clear_scrollback() }
		assert app.selection_click.count == 0
		app.close_app()
	}
	retained := C.vinix_heap_end()
	if retained > 0 {
		count := C.vinix_heap_count()
		for index in u32(0) .. if count < 16 { count } else { 16 } {
			eprintln('Terminal retained allocation: ${C.vinix_heap_size_at(index)} bytes')
		}
	}
	assert retained == 0
}

fn terminal_block_memory_frames(mut app TerminalApp) {
	for language in desktop_languages {
		desktop_language = language
		for size in [ui2.rect(0, 0, 112, 118), ui2.rect(0, 0, 272, 118), ui2.rect(0, 0, 560, 340)]! {
			for search in [false, true]! {
				for block in [false, true]! {
					app.search_open = search
					app.selection_block = block
					begin_frame_elements()
					free_tree(app.build(size) or { panic(err) })
				}
			}
		}
	}
}

fn test_terminal_block_selection_native_dispatch_padding_toggle_history_alternate_and_render_retain_zero_bytes() {
	features := app_compositor_features
	language := desktop_language
	defer { app_compositor_features = features; desktop_language = language }
	app_compositor_features |= app_feature_text_copy
	mut warm := TerminalApp{exited: true}
	terminal_block_memory_frames(mut warm)
	warm.close_app()
	mut desktop := Desktop{}
	defer { unsafe { desktop.native_asset_icons.free() } }
	mut clipboard := HostClipboard{configured: true}
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut native := open_terminal(mut desktop) or { panic(err) }
		mut app := unsafe { &TerminalApp(native) }
		app.exited = true
		app.set_geometry(3, 12)
		app.visible_rows = 3
		terminal_selection_memory_output(mut app, 'aй😀 d\r\nxy\r\n')
		app.handle(terminal_action_selection_mode) or { panic(err) }
		app.pointer_event(.down, .left, 0, 16, 42, 112, 118)
		app.pointer_event(.move, .no_button, 0, 48, 74, 112, 118)
		app.pointer_event(.up, .left, 0, 48, 74, 112, 118)
		app.key_input(terminal_key_cmd_copy)
		request := native_app_text_copy_request(mut native)
		sequence := text_copy_into_session(mut clipboard, editor_bytes_text(request)) or { panic('block copy refused') }
		assert clipboard.local_length == 'й😀 d\ny   \n    '.len
		assert unsafe { tos(&clipboard.local_bytes[0], clipboard.local_length) } == 'й😀 d\ny   \n    '
		ack := text_copy_reply(sequence, true)
		app.handle(terminal_action_selection_mode) or { panic(err) }
		native_app_receive_desktop_service(mut native, editor_bytes_text(ack))
		assert app.copy_client.status_key() == '' && !app.selection_block
		unsafe { request.free(); ack.free() }
		app.handle(terminal_action_selection_mode) or { panic(err) }
		app.pointer_event(.down, .left, 0, 16, 42, 112, 118)
		app.pointer_event(.up, .left, 0, 48, 74, 112, 118)
		app.copy_selection()
		app.copy_selection()
		app.handle(terminal_action_selection_mode) or { panic(err) }
		assert app.take_clipboard_copy_request().len == 0
		terminal_block_memory_frames(mut app)
		for _ in 0 .. terminal_scrollback + 2 { terminal_selection_memory_output(mut app, 'history é\r\n') }
		app.enter_alternate_screen()
		terminal_selection_memory_output(mut app, 'alternate й\r\nrow')
		terminal_block_memory_frames(mut app)
		app.leave_alternate_screen()
		app.clear_scrollback()
		app.close_app()
		app.close_app()
		unsafe { free(app) }
	}
	assert C.vinix_heap_end() == 0
}

fn test_terminal_block_selection_exact_limit_overflow_and_snapshot_replacement_retain_zero_bytes() {
	features := app_compositor_features
	defer { app_compositor_features = features }
	app_compositor_features |= app_feature_text_copy
	plain := 'x'.repeat(255)
	suffix := 'x'.repeat(254)
	unicode := 'é' + suffix
	defer { unsafe { plain.free(); suffix.free(); unicode.free() } }
	C.vinix_heap_begin()
	for _ in 0 .. 50 {
		mut app := TerminalApp{exited: true}
		app.set_geometry(1, 255)
		app.lines = []string{cap: 256}
		for row in 0 .. 256 { app.lines << if row == 0 { unicode.clone() } else { plain.clone() } }
		app.toggle_selection_mode()
		app.selection_anchor = TerminalSelectionPoint{row: 0}
		app.selection_head = TerminalSelectionPoint{row: 255, column: 255}
		app.copy_selection()
		request := app.take_clipboard_copy_request()
		assert request.len == text_copy_header_size + clipboard_max_bytes
		unsafe { app.lines[1].free() }
		app.lines[1] = unicode.clone()
		app.copy_selection()
		assert app.copy_client.status_key() == 'clipboard.copy.too_large'
		assert app.take_clipboard_copy_request().len == 0
		app.selection_head = TerminalSelectionPoint{row: 1, column: 4}
		app.copy_selection()
		app.copy_selection()
		new_request := app.take_clipboard_copy_request()
		assert new_request.len == text_copy_header_size + 'éxxx\néxxx'.len
		app.toggle_selection_mode()
		assert app.copy_client.status_key() == ''
		unsafe { request.free(); new_request.free() }
		app.close_app()
	}
	assert C.vinix_heap_end() == 0
}
