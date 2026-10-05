// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn test_clipboard_keeps_unicode_tabs_and_normalizes_line_endings() {
	assert clipboard_text('Привет\t😀\r\ncafé\rnext\n') == 'Привет\t😀\ncafé\nnext\n'
	assert clipboard_text('a\x00\x03\x11\x13\x1b\x7fb') == 'ab'
}

fn test_paste_in_editor_inserts_text_at_cursor_and_preserves_tabs() {
	mut editor := TextEditorApp{visible_rows: 4}
	editor.key_input('beforeafter')
	editor.cursor = 6
	editor.paste_input('Привет\t😀\nsecond line')
	assert editor_bytes_text(editor.text) == 'beforeПривет\t😀\nsecond lineafter'
	assert editor.cursor == 'beforeПривет\t😀\nsecond line'.len
	assert editor.modified
	editor.key_input('\x1b[D')
	assert editor.cursor == 'beforeПривет\t😀\nsecond lin'.len
}

fn test_editor_rejects_paste_that_exceeds_path_limit() {
	mut editor := TextEditorApp{focus: .path}
	editor.path = 'a'.repeat(editor_max_path - 1).bytes()
	editor.paste_input('é')
	assert editor.path.len == editor_max_path - 1
}

fn test_paste_shortcuts_preserve_ordinary_keys_and_allow_split_cmd_v() {
	mut d := Desktop{clipboard: HostClipboard{configured: true, url: 'http://unused'}}
	assert d.take_paste_keys('hello') == 'hello'
	assert d.take_paste_keys('\x16') == ''
	assert d.take_paste_keys(key_ctrl_shift_v) == ''
	assert d.take_paste_keys(key_shift_insert) == ''
	assert d.take_paste_keys('\x1b[118;') == ''
	assert d.take_paste_keys('9u') == ''
	assert d.take_paste_keys('\x1b[D') == '\x1b[D'
	d.clipboard.url = ''
	assert d.take_paste_keys('\x16') == '\x16'
}

fn test_terminal_paste_follows_bracketed_paste_mode() {
	mut pipe := [2]i32{}
	assert C.pipe(&pipe[0]) == 0
	defer {
		desktop_close(pipe[0])
		desktop_close(pipe[1])
	}
	mut terminal := TerminalApp{terminal: pipe[1]}
	terminal.set_geometry(2, 20)
	terminal.ingest_output('\x1b[?2004h'.bytes())
	assert terminal.bracketed_paste
	terminal.paste_input('Привет\nworld')
	mut output := [128]u8{}
	n := desktop_read(pipe[0], &output[0], 128)
	assert unsafe { tos(&output[0], int(n)) } == '\x1b[200~Привет\nworld\x1b[201~'
	terminal.ingest_output('\x1b[?2004l'.bytes())
	assert !terminal.bracketed_paste
	terminal.paste_input('plain')
	next := desktop_read(pipe[0], &output[0], 128)
	assert unsafe { tos(&output[0], int(next)) } == 'plain'
}

fn test_paste_crosses_the_native_application_protocol() {
	mut pipe := [2]i32{}
	assert C.pipe(&pipe[0]) == 0
	defer {
		desktop_close(pipe[0])
		desktop_close(pipe[1])
	}
	text := 'Привет\t😀\nsecond line'
	assert send_app_request(pipe[1], .paste_input, 0, 0, AppWireState{}, text)
	command, _, _, _, payload := receive_app_request(pipe[0]) or { panic(err) }
	assert command == .paste_input
	assert payload == text
	free_app_payload(payload)
}

fn test_host_paste_fetches_text_asynchronously_and_preserves_focus() {
	url := os.getenv('VINIX_CLIPBOARD_TEST_URL')
	if url.len == 0 { return }
	mut editor := &TextEditorApp{visible_rows: 4}
	mut d := Desktop{
		focus: 1
		clipboard: HostClipboard{configured: true, url: url}
	}
	d.apps << editor
	d.windows << Window{id: 1, app_index: 0}
	d.request_host_paste()
	assert d.clipboard.pid > 0
	for _ in 0 .. 400 {
		d.poll_host_paste()
		if d.clipboard.pid <= 0 { break }
		desktop_sleep_ms(10)
	}
	assert d.clipboard.pid == -1
	assert editor_bytes_text(editor.text) == 'Привет\t😀\nsecond line'
	assert d.clipboard.fd == -1
	d.request_host_paste()
	d.focus = 2
	for _ in 0 .. 400 {
		d.poll_host_paste()
		if d.clipboard.pid <= 0 { break }
		desktop_sleep_ms(10)
	}
	assert editor_bytes_text(editor.text) == 'Привет\t😀\nsecond line'
}
