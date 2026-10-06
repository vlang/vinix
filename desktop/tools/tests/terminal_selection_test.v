// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2
import encoding.utf8

fn terminal_selection_output(mut app TerminalApp, text string) {
	app.ingest_output(unsafe { text.str.vbytes(text.len) })
}

fn terminal_selection_fixture(mut app TerminalApp, output string, rows int, columns int) {
	app.exited = true
	app.set_geometry(rows, columns)
	app.visible_rows = rows
	terminal_selection_output(mut app, output)
}

fn terminal_selection_drag(mut app TerminalApp, from_x int, from_y int, to_x int, to_y int, width int, height int) {
	app.pointer_event(.down, .left, 0, from_x, from_y, width, height)
	app.pointer_event(.move, .no_button, 0, to_x, to_y, width, height)
	app.pointer_event(.up, .left, 0, to_x, to_y, width, height)
}

fn terminal_selection_click_at(mut app TerminalApp, x int, y int, now u64, width int, height int) {
	app.selection_pointer_event_at(.down, .left, 0, x, y, width, height, now)
	app.selection_pointer_event_at(.up, .left, 0, x, y, width, height, now + 20)
}

fn terminal_selection_expect(app &TerminalApp, expected string) {
	bytes := app.selected_bytes()
	defer { if bytes.cap > 0 { unsafe { bytes.free() } } }
	assert editor_bytes_text(bytes) == expected
	assert utf8.validate_str(editor_bytes_text(bytes))
}

fn terminal_selection_tree_count(tree &ui2.Element, id string) int {
	mut count := if tree.id == id { 1 } else { 0 }
	for child in tree.children { count += terminal_selection_tree_count(unsafe { &child }, id) }
	return count
}

fn test_terminal_selection_drag_uses_unicode_cells_and_copies_under_cursor_text() {
	mut app := TerminalApp{}
	defer { app.close_app() }
	terminal_selection_fixture(mut app, 'aй😀\r\nnext é', 3, 12)
	terminal_selection_drag(mut app, 16, 42, 32, 42, 112, 118)
	assert app.has_selection() && !app.selection_dragging
	terminal_selection_expect(unsafe { &app }, 'й😀')
	terminal_selection_drag(mut app, 24, 58, 16, 42, 112, 118)
	terminal_selection_expect(unsafe { &app }, 'й😀\nne')
	app.move_cursor(0, 1)
	assert !app.has_selection()
	terminal_selection_drag(mut app, 16, 42, 24, 42, 112, 118)
	assert app.rendered_row(0) == 'a_😀'
	terminal_selection_expect(unsafe { &app }, 'й')
}

fn test_terminal_selection_scroll_drag_reaches_history_and_respects_empty_row_newlines() {
	mut app := TerminalApp{}
	defer { app.close_app() }
	terminal_selection_fixture(mut app, 'old й\r\n\r\nthird\r\nlast', 2, 12)
	assert app.lines.len == 2
	app.pointer_event(.scroll, .no_button, -1, 8, 42, 112, 102)
	assert app.scroll == 2
	terminal_selection_drag(mut app, 40, 42, 8, 58, 112, 102)
	terminal_selection_expect(unsafe { &app }, 'й\n')
	app.pointer_event(.down, .left, 0, 8, 42, 112, 102)
	app.pointer_event(.move, .no_button, 0, 40, 79, 112, 102)
	assert app.scroll == 1 && app.selection_dragging
	app.pointer_event(.move, .no_button, 0, 40, 79, 112, 102)
	assert app.scroll == 0
	app.pointer_event(.up, .left, 0, 40, 79, 112, 102)
	terminal_selection_expect(unsafe { &app }, 'old й\n\nthird\nlast')
}

fn test_terminal_selection_resets_for_output_geometry_alternate_and_history_changes() {
	mut app := TerminalApp{}
	defer { app.close_app() }
	terminal_selection_fixture(mut app, 'old\r\nnew', 2, 12)
	terminal_selection_drag(mut app, 8, 42, 24, 42, 112, 102)
	terminal_selection_output(mut app, '\x07')
	assert app.has_selection() // a bell does not mutate displayed cells
	terminal_selection_output(mut app, '!')
	assert !app.has_selection()
	terminal_selection_drag(mut app, 8, 42, 24, 42, 112, 102)
	app.set_geometry(2, 12)
	assert app.has_selection()
	app.set_geometry(3, 12)
	assert !app.has_selection()
	app.visible_rows = 3
	terminal_selection_drag(mut app, 8, 42, 24, 42, 112, 118)
	app.enter_alternate_screen()
	assert !app.has_selection() && app.scroll == 0
	terminal_selection_output(mut app, 'vim')
	terminal_selection_drag(mut app, 8, 42, 32, 42, 112, 118)
	terminal_selection_expect(unsafe { &app }, 'vim')
	app.leave_alternate_screen()
	assert !app.has_selection()
	terminal_selection_drag(mut app, 8, 42, 24, 42, 112, 118)
	app.clear_scrollback()
	assert !app.has_selection()
}

fn test_terminal_selection_build_draws_blank_rows_and_resets_on_pixel_resize() {
	mut app := TerminalApp{exited: true}
	defer { app.close_app() }
	size := ui2.rect(0, 0, 176, 116)
	begin_frame_elements()
	free_tree(app.build(size)!)
	terminal_selection_output(mut app, 'one\r\n\r\nthree')
	terminal_selection_drag(mut app, 8, 42, 32, 74, 176, 116)
	begin_frame_elements()
	tree := app.build(size)!
	assert terminal_selection_tree_count(unsafe { &tree }, 'term.selection.highlight') == 3
	assert terminal_selection_tree_count(unsafe { &tree }, terminal_action_copy) == 1
	assert terminal_selection_tree_count(unsafe { &tree }, 'term.selection.status') == 1
	assert app.has_selection()
	free_tree(tree)
	begin_frame_elements()
	free_tree(app.build(ui2.rect(0, 0, 177, 116))!)
	assert !app.has_selection() // grid remains the same, pixel geometry changed
}

fn test_terminal_selection_toolbar_copy_is_acknowledged_and_snapshot_survives_output() {
	features := app_compositor_features
	defer { app_compositor_features = features }
	app_compositor_features |= app_feature_text_copy
	mut app := TerminalApp{}
	defer { app.close_app() }
	terminal_selection_fixture(mut app, 'aй😀', 2, 12)
	terminal_selection_drag(mut app, 8, 42, 32, 42, 112, 102)
	app.handle(terminal_action_copy)!
	assert app.copy_client.status_key() == 'clipboard.copy.pending'
	terminal_selection_output(mut app, 'new')
	assert !app.has_selection()
	request := app.take_clipboard_copy_request()
	defer { unsafe { request.free() } }
	mut clipboard := HostClipboard{configured: true}
	sequence := text_copy_into_session(mut clipboard, editor_bytes_text(request)) or { panic('copy refused') }
	assert clipboard.local_length == 'aй😀'.len
	assert unsafe { tos(&clipboard.local_bytes[0], clipboard.local_length) } == 'aй😀'
	wrong := text_copy_reply(sequence + 1, true)
	app.receive_clipboard_copy_reply(editor_bytes_text(wrong))
	unsafe { wrong.free() }
	assert app.copy_client.status_key() == 'clipboard.copy.pending'
	ack := text_copy_reply(sequence, true)
	app.receive_clipboard_copy_reply(editor_bytes_text(ack))
	unsafe { ack.free() }
	assert app.copy_client.status_key() == 'clipboard.copy.copied'
	terminal_selection_output(mut app, 'still running')
	assert app.copy_client.status_key() == 'clipboard.copy.copied'
	assert app.take_clipboard_copy_request().len == 0
}

fn test_terminal_selection_bounded_copy_refuses_overflow_without_replacing_clipboard() {
	features := app_compositor_features
	defer { app_compositor_features = features }
	app_compositor_features |= app_feature_text_copy
	mut app := TerminalApp{exited: true}
	defer { app.close_app() }
	app.set_geometry(2, 12)
	app.lines << 'é'.repeat(clipboard_max_bytes / 2)
	app.selection_anchor = TerminalSelectionPoint{row: 0}
	app.selection_head = TerminalSelectionPoint{row: 0, column: clipboard_max_bytes / 2}
	app.copy_selection()
	request := app.take_clipboard_copy_request()
	defer { unsafe { request.free() } }
	mut clipboard := HostClipboard{configured: true}
	sequence := text_copy_into_session(mut clipboard, editor_bytes_text(request)) or { panic('copy refused') }
	assert clipboard.local_length == clipboard_max_bytes
	ack := text_copy_reply(sequence, true)
	app.receive_clipboard_copy_reply(editor_bytes_text(ack))
	unsafe { ack.free() }
	app.selection_head = TerminalSelectionPoint{row: 1}
	app.copy_selection()
	assert app.copy_client.status_key() == 'clipboard.copy.too_large'
	assert app.take_clipboard_copy_request().len == 0
	assert clipboard.local_length == clipboard_max_bytes
	app_compositor_features &= ~app_feature_text_copy
	app.copy_selection()
	assert app.copy_client.status_key() == 'clipboard.copy.unavailable'
	assert app.take_clipboard_copy_request().len == 0
}

fn test_terminal_selection_cmd_copy_fragments_preserve_ctrl_c_and_unknown_shell_keys() {
	features := app_compositor_features
	defer { app_compositor_features = features }
	app_compositor_features |= app_feature_text_copy
	mut pipe := [2]i32{}
	assert C.pipe(&pipe[0]) == 0
	mut app := TerminalApp{terminal: int(pipe[1]), started: true}
	defer { app.close_app(); desktop_close(pipe[0]) }
	app.set_geometry(2, 12)
	app.visible_rows = 2
	terminal_selection_output(mut app, 'copy')
	terminal_selection_drag(mut app, 8, 42, 40, 42, 112, 102)
	for split in 1 .. terminal_key_cmd_copy.len {
		app.key_input(unsafe { tos(terminal_key_cmd_copy.str, split) })
		assert app.next_poll_ms() == 100
		app.key_input(unsafe { tos(&terminal_key_cmd_copy.str[split], terminal_key_cmd_copy.len - split) })
		assert app.copy_key_len == 0
		request := app.take_clipboard_copy_request()
		assert request.len == text_copy_header_size + 4
		unsafe { request.free() }
	}
	app.key_input('before\x03\x1b[99;6u\x1b[D\bafter')
	mut buffer := [128]u8{}
	got := desktop_read(pipe[0], &buffer[0], u64(buffer.len))
	assert unsafe { tos(&buffer[0], int(got)) } == 'before\x03\x1b[99;6u\x1b[D\x7fafter'
	assert app.has_selection()
	app.key_input(terminal_key_cmd_copy_caps)
	caps_request := app.take_clipboard_copy_request()
	assert caps_request.len == text_copy_header_size + 4
	unsafe { caps_request.free() }
	app.key_input('\x1b\x1b[99;9u')
	nested_request := app.take_clipboard_copy_request()
	assert nested_request.len == text_copy_header_size + 4
	unsafe { nested_request.free() }
	bare := desktop_read(pipe[0], &buffer[0], u64(buffer.len))
	assert unsafe { tos(&buffer[0], int(bare)) } == '\x1b'
	app.key_input('\x1b[')
	assert app.copy_key_len == 2
	assert !app.expire_copy_key(app.copy_key_ms + 99)
	assert app.expire_copy_key(app.copy_key_ms + 100)
	got_escape := desktop_read(pipe[0], &buffer[0], u64(buffer.len))
	assert unsafe { tos(&buffer[0], int(got_escape)) } == '\x1b['
}

fn test_terminal_selection_paste_shortcut_bytes_stay_literal_and_find_receives_typing() {
	mut pipe := [2]i32{}
	assert C.pipe(&pipe[0]) == 0
	mut app := TerminalApp{terminal: int(pipe[1]), started: true, bracketed_paste: true}
	defer { app.close_app(); desktop_close(pipe[0]) }
	app.set_geometry(2, 12)
	app.key_input('\x1b[')
	app.paste_input(terminal_key_cmd_copy)
	mut buffer := [128]u8{}
	got := desktop_read(pipe[0], &buffer[0], u64(buffer.len))
	assert unsafe { tos(&buffer[0], int(got)) } == '\x1b[\x1b[200~\x1b[99;9u\x1b[201~'
	assert app.copy_client.status_key() == '' && app.copy_key_len == 0
	app.handle(terminal_action_find)!
	app.key_input('café')
	assert editor_bytes_text(app.search_query) == 'café'
	app.paste_input('\x1b[99;9u')
	assert app.copy_client.status_key() == ''
	assert editor_bytes_text(app.search_query) == 'café[99;9u'
}

fn test_terminal_selection_double_click_uses_cell_under_pointer_and_unicode_word_boundaries() {
	mut app := TerminalApp{}
	defer { app.close_app() }
	terminal_selection_fixture(mut app, 'café_42-й😀  fin', 3, 24)
	terminal_selection_click_at(mut app, 22, 42, 1000, 208, 118)
	assert !app.has_selection()
	terminal_selection_click_at(mut app, 23, 42, 1200, 208, 118)
	assert app.selection_unit == .word && !app.selection_dragging
	terminal_selection_expect(unsafe { &app }, 'café_42')
	terminal_selection_click_at(mut app, 66, 42, 2000, 208, 118)
	terminal_selection_click_at(mut app, 66, 42, 2100, 208, 118)
	terminal_selection_expect(unsafe { &app }, '-')
	terminal_selection_click_at(mut app, 74, 42, 3000, 208, 118)
	terminal_selection_click_at(mut app, 74, 42, 3100, 208, 118)
	terminal_selection_expect(unsafe { &app }, 'й')
	terminal_selection_click_at(mut app, 82, 42, 4000, 208, 118)
	terminal_selection_click_at(mut app, 82, 42, 4100, 208, 118)
	terminal_selection_expect(unsafe { &app }, '😀')
	terminal_selection_click_at(mut app, 94, 42, 5000, 208, 118)
	terminal_selection_click_at(mut app, 94, 42, 5100, 208, 118)
	terminal_selection_expect(unsafe { &app }, '  ')
	terminal_selection_click_at(mut app, 160, 42, 6000, 208, 118)
	terminal_selection_click_at(mut app, 160, 42, 6100, 208, 118)
	assert !app.has_selection() // trailing grid padding is not text
}

fn test_terminal_selection_word_drag_expands_and_reverses_whole_unicode_words() {
	mut app := TerminalApp{}
	defer { app.close_app() }
	terminal_selection_fixture(mut app, 'one café_42 last\r\nй next', 3, 24)
	terminal_selection_click_at(mut app, 50, 42, 1000, 208, 118)
	app.selection_pointer_event_at(.down, .left, 0, 50, 42, 208, 118, 1200)
	terminal_selection_expect(unsafe { &app }, 'café_42')
	app.selection_pointer_event_at(.move, .no_button, 0, 114, 42, 208, 118, 1300)
	terminal_selection_expect(unsafe { &app }, 'café_42 last')
	app.selection_pointer_event_at(.move, .no_button, 0, 10, 42, 208, 118, 1400)
	terminal_selection_expect(unsafe { &app }, 'one café_42')
	app.selection_pointer_event_at(.move, .no_button, 0, 58, 42, 208, 118, 1500)
	terminal_selection_expect(unsafe { &app }, 'café_42')
	app.selection_pointer_event_at(.up, .left, 0, 26, 58, 208, 118, 1600)
	terminal_selection_expect(unsafe { &app }, 'café_42 last\nй next')
	assert !app.selection_dragging && app.selection_click.count == 0
}

fn test_terminal_selection_triple_click_includes_physical_line_newline_and_blank_lines() {
	mut app := TerminalApp{}
	defer { app.close_app() }
	terminal_selection_fixture(mut app, 'first\r\n\r\nlast', 3, 16)
	for time in [u64(1000), 1100, 1200]! { terminal_selection_click_at(mut app, 18, 42, time, 144, 118) }
	assert app.selection_unit == .line
	terminal_selection_expect(unsafe { &app }, 'first\n')
	terminal_selection_click_at(mut app, 18, 42, 1300, 144, 118)
	assert app.selection_unit == .character && !app.has_selection() // fourth starts a new sequence
	for time in [u64(2000), 2100, 2200]! { terminal_selection_click_at(mut app, 18, 58, time, 144, 118) }
	terminal_selection_expect(unsafe { &app }, '\n')
	for time in [u64(3000), 3100, 3200]! { terminal_selection_click_at(mut app, 18, 74, time, 144, 118) }
	terminal_selection_expect(unsafe { &app }, 'last')
	app.move_cursor(2, 0)
	terminal_selection_output(mut app, '\x1b[2K')
	for time in [u64(4000), 4100, 4200]! { terminal_selection_click_at(mut app, 18, 74, time, 144, 118) }
	assert !app.has_selection() // final empty row has no trailing newline
}

fn test_terminal_selection_line_drag_expands_whole_rows_in_both_directions() {
	mut app := TerminalApp{}
	defer { app.close_app() }
	terminal_selection_fixture(mut app, 'first\r\nmiddle\r\nlast', 3, 16)
	terminal_selection_click_at(mut app, 26, 58, 1000, 144, 118)
	terminal_selection_click_at(mut app, 26, 58, 1100, 144, 118)
	app.selection_pointer_event_at(.down, .left, 0, 26, 58, 144, 118, 1200)
	terminal_selection_expect(unsafe { &app }, 'middle\n')
	app.selection_pointer_event_at(.move, .no_button, 0, 10, 42, 144, 118, 1300)
	terminal_selection_expect(unsafe { &app }, 'first\nmiddle\n')
	app.selection_pointer_event_at(.move, .no_button, 0, 106, 74, 144, 118, 1400)
	terminal_selection_expect(unsafe { &app }, 'middle\nlast')
	app.selection_pointer_event_at(.up, .left, 0, 18, 58, 144, 118, 1500)
	terminal_selection_expect(unsafe { &app }, 'middle\n')
}

fn test_terminal_selection_multiclick_time_slop_other_buttons_scroll_and_drag_limits() {
	mut app := TerminalApp{}
	defer { app.close_app() }
	terminal_selection_fixture(mut app, 'words\r\nnext', 2, 16)
	terminal_selection_click_at(mut app, 18, 42, 1000, 144, 102)
	terminal_selection_click_at(mut app, 23, 42, 1500, 144, 102)
	assert app.selection_unit == .word
	terminal_selection_expect(unsafe { &app }, 'words')
	terminal_selection_click_at(mut app, 23, 42, 2001, 144, 102)
	assert app.selection_unit == .character
	terminal_selection_click_at(mut app, 29, 42, 2100, 144, 102)
	assert app.selection_unit == .character // six-pixel jump
	terminal_selection_click_at(mut app, 29, 42, 2000, 144, 102)
	assert app.selection_unit == .character // clock moved backwards
	terminal_selection_click_at(mut app, 29, 42, ~u64(0), 144, 102)
	assert app.selection_unit == .character
	app.selection_pointer_event_at(.down, .right, 0, 29, 42, 144, 102, 2200)
	terminal_selection_click_at(mut app, 29, 42, 2300, 144, 102)
	assert app.selection_unit == .character
	app.selection_pointer_event_at(.scroll, .no_button, 1, 29, 42, 144, 102, 2400)
	terminal_selection_click_at(mut app, 29, 42, 2500, 144, 102)
	assert app.selection_unit == .character
	app.selection_pointer_event_at(.down, .left, 0, 29, 42, 144, 102, 2600)
	app.selection_pointer_event_at(.move, .no_button, 0, 45, 42, 144, 102, 2700)
	app.selection_pointer_event_at(.up, .left, 0, 29, 42, 144, 102, 2800)
	terminal_selection_click_at(mut app, 29, 42, 2900, 144, 102)
	assert app.selection_unit == .character // returning after a drag does not count as another click
	app.selection_pointer_event_at(.down, .left, 0, 29, 8, 144, 102, 3000)
	terminal_selection_click_at(mut app, 29, 42, 3100, 144, 102)
	assert app.selection_unit == .character
}

fn test_terminal_selection_multiclick_history_utf8_autoscroll_and_alternate_screen() {
	mut app := TerminalApp{}
	defer { app.close_app() }
	terminal_selection_fixture(mut app, 'old café\r\n\r\nthird\r\nlast', 2, 16)
	assert app.lines.len == 2
	app.pointer_event(.scroll, .no_button, -1, 8, 42, 144, 102)
	terminal_selection_click_at(mut app, 50, 42, 1000, 144, 102)
	app.selection_pointer_event_at(.down, .left, 0, 50, 42, 144, 102, 1100)
	terminal_selection_expect(unsafe { &app }, 'café')
	app.selection_pointer_event_at(.move, .no_button, 0, 26, 79, 144, 102, 1200)
	assert app.scroll == 1
	app.selection_pointer_event_at(.up, .left, 0, 26, 79, 144, 102, 1300)
	assert app.scroll == 0
	terminal_selection_expect(unsafe { &app }, 'café\n\nthird\nlast')
	app.enter_alternate_screen()
	assert app.selection_click.count == 0 && !app.has_selection()
	terminal_selection_output(mut app, 'alt й\r\nrow')
	for time in [u64(2000), 2100, 2200]! { terminal_selection_click_at(mut app, 18, 42, time, 144, 102) }
	terminal_selection_expect(unsafe { &app }, 'alt й\n')
	app.leave_alternate_screen()
	assert app.selection_click.count == 0 && !app.has_selection()
	terminal_selection_click_at(mut app, 18, 42, 2300, 144, 102)
	assert app.selection_unit == .character
}

fn test_terminal_selection_word_click_combining_marks_and_unicode_space_in_history() {
	mut app := TerminalApp{}
	defer { app.close_app() }
	terminal_selection_fixture(mut app, 'cafe\u0301\u00a0\u00a0й\r\nnext\r\nlast', 2, 16)
	app.pointer_event(.scroll, .no_button, -1, 8, 42, 144, 102)
	terminal_selection_click_at(mut app, 42, 42, 1000, 144, 102)
	terminal_selection_click_at(mut app, 42, 42, 1100, 144, 102)
	terminal_selection_expect(unsafe { &app }, 'cafe\u0301')
	terminal_selection_click_at(mut app, 54, 42, 2000, 144, 102)
	terminal_selection_click_at(mut app, 54, 42, 2100, 144, 102)
	terminal_selection_expect(unsafe { &app }, '\u00a0\u00a0')
}

fn test_terminal_selection_multiclick_copy_still_refuses_large_words_and_physical_line_newline_overflow() {
	features := app_compositor_features
	defer { app_compositor_features = features }
	app_compositor_features |= app_feature_text_copy
	mut app := TerminalApp{exited: true}
	defer { app.close_app() }
	app.set_geometry(2, 16)
	app.visible_rows = 2
	app.lines << 'é'.repeat(clipboard_max_bytes / 2)
	app.scroll = 1
	terminal_selection_click_at(mut app, 18, 42, 1000, 144, 102)
	terminal_selection_click_at(mut app, 18, 42, 1100, 144, 102)
	app.copy_selection()
	request := app.take_clipboard_copy_request()
	assert request.len == text_copy_header_size + clipboard_max_bytes
	unsafe { request.free() }
	terminal_selection_click_at(mut app, 18, 42, 1200, 144, 102)
	app.copy_selection()
	assert app.copy_client.status_key() == 'clipboard.copy.too_large'
	assert app.take_clipboard_copy_request().len == 0
	app.lines << 'é'.repeat(clipboard_max_bytes / 2 + 1)
	app.clear_selection()
	app.scroll = 1
	terminal_selection_click_at(mut app, 18, 42, 2000, 144, 102)
	terminal_selection_click_at(mut app, 18, 42, 2100, 144, 102)
	app.copy_selection()
	assert app.copy_client.status_key() == 'clipboard.copy.too_large'
	assert app.take_clipboard_copy_request().len == 0
}

fn test_terminal_selection_words_and_lines_stop_at_physical_autowrap_rows() {
	mut app := TerminalApp{}
	defer { app.close_app() }
	terminal_selection_fixture(mut app, 'abcdefghi', 3, 6)
	terminal_selection_click_at(mut app, 26, 42, 1000, 64, 118)
	terminal_selection_click_at(mut app, 26, 42, 1100, 64, 118)
	terminal_selection_expect(unsafe { &app }, 'abcdef')
	terminal_selection_click_at(mut app, 26, 42, 1200, 64, 118)
	terminal_selection_expect(unsafe { &app }, 'abcdef\n')
	terminal_selection_click_at(mut app, 18, 58, 2000, 64, 118)
	terminal_selection_click_at(mut app, 18, 58, 2100, 64, 118)
	terminal_selection_expect(unsafe { &app }, 'ghi')
}
