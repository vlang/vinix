// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

// editor_utf8_cursor_x builds a frame and reports where the cursor bar is
// drawn inside the page, or -1 when no row carries it.
fn editor_utf8_cursor_x(mut editor TextEditorApp) int {
	begin_frame_elements()
	tree := editor.build(ui2.rect(0, 0, 640, 400)) or { panic(err) }
	for child in tree.children {
		if child.id != editor_action_document {
			continue
		}
		for element in child.children {
			if element.kind == .view && element.frame.width == 2 {
				return int(element.frame.x)
			}
		}
	}
	return -1
}

fn test_editor_types_cyrillic_and_accents_as_whole_characters() {
	mut editor := TextEditorApp{
		visible_rows: 4
	}
	// Twelve bytes of Cyrillic, then ASCII, a two-byte é, a three-byte € and a
	// two-byte §: 26 bytes in all.
	editor.key_input('Привет, café € §')
	assert editor_bytes_text(editor.text) == 'Привет, café € §'
	assert editor.text.len == 26
	assert editor.cursor == 26
	assert editor.modified

	// Left steps over one character whatever its length.
	editor.key_input('\x1b[D')
	assert editor.cursor == 24
	editor.key_input('\x1b[D\x1b[D')
	assert editor.cursor == 20
	editor.key_input('й')
	assert editor_bytes_text(editor.text) == 'Привет, café й€ §'
	assert editor.cursor == 22

	// Right does the same, and stops at the end.
	editor.key_input('\x1b[C')
	assert editor.cursor == 25
	editor.key_input('\x1b[C\x1b[C')
	assert editor.cursor == 28
	editor.key_input('\x1b[C')
	assert editor.cursor == 28

	// Backspace and Delete remove one whole character.
	editor.key_input('\x7f')
	assert editor_bytes_text(editor.text) == 'Привет, café й€ '
	assert editor.cursor == 26
	editor.key_input('\x1b[D\x1b[D\x1b[D\x1b[3~')
	assert editor_bytes_text(editor.text) == 'Привет, café € '
	assert editor.cursor == 20
	editor.key_input('\x1b[D\x08')
	assert editor_bytes_text(editor.text) == 'Привет, caf € '
	assert editor.cursor == 17

	// Home, End and their console forms land on the line's ends.
	editor.key_input('\x1b[H\x1b[3~')
	assert editor_bytes_text(editor.text) == 'ривет, caf € '
	assert editor.cursor == 0
	editor.key_input('\x1b[C\x1b[F')
	assert editor.cursor == editor.text.len
	editor.key_input('\x1b[1~')
	assert editor.cursor == 0
	editor.key_input('\x1b[4~')
	assert editor.cursor == editor.text.len
	assert editor_bytes_text(editor.text) == 'ривет, caf € '

	// Four-byte characters are single characters as well.
	editor.key_input('😀\x1b[D')
	assert editor.cursor == editor.text.len - 4
	editor.key_input('\x1b[3~')
	assert editor_bytes_text(editor.text) == 'ривет, caf € '
}

fn test_editor_keeps_a_character_split_across_two_reads() {
	mut editor := TextEditorApp{
		visible_rows: 4
	}
	editor.key_input('\xd0')
	assert editor.text.len == 0
	assert !editor.modified
	editor.key_input('\xb9')
	assert editor_bytes_text(editor.text) == 'й'
	editor.key_input('\xe2')
	editor.key_input('\x82\xac')
	editor.key_input('\xf0\x9f')
	editor.key_input('\x98\x80')
	assert editor_bytes_text(editor.text) == 'й€😀'

	// A partial character followed by anything else is dropped, and that next
	// byte still does its own job.
	editor.key_input('\xd0')
	editor.key_input('a')
	assert editor_bytes_text(editor.text) == 'й€😀a'
	editor.key_input('\xe2\x82')
	editor.key_input('\x7f')
	assert editor_bytes_text(editor.text) == 'й€😀'
	editor.key_input('\xd0')
	editor.key_input('\x1b[D')
	assert editor.cursor == editor.text.len - 4
	editor.key_input('\xd0')
	editor.key_input('\xd0\xb9')
	assert editor_bytes_text(editor.text) == 'й€й😀'

	// A click between the two reads abandons the character.
	editor.key_input('\xd0')
	editor.handle(editor_action_document) or { panic(err) }
	editor.key_input('\xb9')
	assert editor_bytes_text(editor.text) == 'й€й😀'
}

fn test_editor_rejects_invalid_utf8_input() {
	mut editor := TextEditorApp{
		visible_rows: 4
	}
	// A stray continuation, overlong forms (C0, C1, E0 80, F0 8F), a surrogate
	// (ED A0), a code point past U+10FFFF (F4 90), and F5 and FF leads.
	editor.key_input('a\xb9b\xc0\xafc\xc1\xbfd\xe0\x80\xafe\xed\xa0\x80f\xf0\x8f\xbf\xbfg\xf4\x90\x80\x80h\xf5\x80\x80\x80i\xff')
	assert editor_bytes_text(editor.text) == 'abcdefghi'
	assert editor.pending_len == 0

	// The edges of each valid range still get through: U+0080, U+07FF,
	// U+0800, U+D7FF, U+E000, U+10000 and U+10FFFF.
	edges := '\xc2\x80\xdf\xbf\xe0\xa0\x80\xed\x9f\xbf\xee\x80\x80\xf0\x90\x80\x80\xf4\x8f\xbf\xbf'
	editor.key_input(edges)
	assert editor.text.len == 9 + edges.len
	assert editor_bytes_text(editor.text).ends_with(edges)
	for _ in 0 .. 7 {
		editor.key_input('\x1b[D')
	}
	assert editor.cursor == 9
}

fn test_editor_up_and_down_keep_the_column_in_characters() {
	mut editor := TextEditorApp{
		visible_rows: 4
	}
	editor.key_input('abcd\nжжжж\nёжик\nxy')
	// Line starts are at bytes 0, 5, 14 and 23.
	editor.key_input('\x1b[A\x1b[A\x1b[A')
	assert editor.cursor == 2

	// Column 3 of the ASCII line is column 3 of the Cyrillic one, not byte 3.
	editor.key_input('\x1b[C\x1b[B')
	assert editor.cursor == 5 + 6
	editor.key_input('\x1b[B')
	assert editor.cursor == 14 + 6
	editor.key_input('!')
	assert editor_bytes_text(editor.text) == 'abcd\nжжжж\nёжи!к\nxy'
	editor.key_input('\x7f\x1b[A')
	assert editor.cursor == 5 + 6

	// A shorter line clamps to its end, and Up keeps the clamped column.
	editor.key_input('\x1b[C\x1b[B\x1b[B')
	assert editor.cursor == editor.text.len
	editor.key_input('\x1b[A\x1b[A')
	assert editor.cursor == 5 + 4
	editor.key_input('\x1b[A')
	assert editor.cursor == 2
}

fn test_editor_draws_the_cursor_by_character_column() {
	mut editor := TextEditorApp{
		visible_rows: 4
	}
	editor.key_input('жжжж\x1b[D\x1b[D')
	assert editor.cursor == 4
	assert editor_utf8_cursor_x(mut editor) == editor_padding + 2 * editor_character_width
	editor.key_input('\x1b[F')
	assert editor_utf8_cursor_x(mut editor) == editor_padding + 4 * editor_character_width
	editor.key_input('\nab€')
	assert editor_utf8_cursor_x(mut editor) == editor_padding + 3 * editor_character_width
}

fn test_editor_path_field_takes_utf8() {
	mut editor := TextEditorApp{
		visible_rows: 4
	}
	editor.set_path('/tmp/')
	editor.handle(editor_action_path) or { panic(err) }
	assert editor.focus == .path
	editor.key_input('заметки-é.txt')
	assert editor_bytes_text(editor.path) == '/tmp/заметки-é.txt'

	// Backspace removes a whole character, including the two-byte é.
	editor.key_input('\x7f\x7f\x7f\x7f\x7f')
	assert editor_bytes_text(editor.path) == '/tmp/заметки-'
	editor.key_input('\xd0')
	editor.key_input('\xb9\xc0\xaf\xb9')
	assert editor_bytes_text(editor.path) == '/tmp/заметки-й'
	assert editor.text.len == 0

	// A character that would overflow the field is refused whole.
	editor.path.clear()
	for editor.path.len < editor_max_path - 1 {
		editor.path << `a`
	}
	editor.key_input('й')
	assert editor.path.len == editor_max_path - 1
	editor.key_input('b')
	assert editor.path.len == editor_max_path
	assert editor.path.last() == `b`
}

fn test_editor_refuses_a_character_past_the_document_limit_whole() {
	mut editor := TextEditorApp{
		visible_rows: 4
	}
	editor.text = []u8{len: editor_max_file_size - 1, init: `a`}
	editor.cursor = editor.text.len
	editor.key_input('й')
	assert editor.text.len == editor_max_file_size - 1
	assert editor_bytes_text(editor.status) == 'Document limit is 64 KB'
	editor.key_input('b')
	assert editor.text.len == editor_max_file_size
	assert editor.text.last() == `b`
}

fn test_editor_cursor_stays_on_a_boundary_in_malformed_text() {
	mut editor := TextEditorApp{
		visible_rows: 4
	}
	// Each stray byte counts as one character and survives moves and edits.
	editor.text = [u8(`x`), 0xd0, `a`, 0xb9, `y`]
	editor.cursor = 3
	editor.key_input('\x1b[D')
	assert editor.cursor == 2
	editor.key_input('\x1b[D')
	assert editor.cursor == 1
	editor.key_input('\x1b[C\x1b[C')
	assert editor.cursor == 3

	// Removing the `a` joins D0 B9 into й, so the cursor settles before it.
	editor.key_input('\x7f')
	assert editor_bytes_text(editor.text) == 'xйy'
	assert editor.cursor == 1
	editor.key_input('\x1b[C')
	assert editor.cursor == 3
}

fn test_editor_opens_edits_and_saves_utf8_files_unchanged() {
	path := os.join_path(os.temp_dir(), 'vinix-desktop-editor-utf8-test.txt')
	defer {
		os.rm(path) or {}
	}
	// The \xff is not UTF-8. It is kept, not repaired or dropped.
	original := 'Grüße\nПривет мир\n€ and § \xff raw\n'
	os.write_file(path, original) or { panic(err) }

	mut editor := TextEditorApp{
		visible_rows: 4
	}
	editor.set_path(path)
	editor.open_document()
	assert editor_bytes_text(editor.text) == original
	assert editor.cursor == editor.text.len
	assert !editor.modified
	editor.save_document()
	saved := os.read_bytes(path) or { panic(err) }
	assert saved == original.bytes()

	// From the empty last line, Up three times reaches `Grüße`. Three Rights
	// pass `Grü`, then ß is replaced by ss.
	editor.key_input('\x1b[A\x1b[A\x1b[A\x1b[C\x1b[C\x1b[C\x1b[3~ss')
	assert editor_bytes_text(editor.text).starts_with('Grüsse\n')

	// Nine Rights on the third line pass `€ and § ` and the stray byte.
	editor.key_input('\x1b[H\x1b[B\x1b[B')
	for _ in 0 .. 9 {
		editor.key_input('\x1b[C')
	}
	editor.key_input('\x7fÿ')
	expected := 'Grüsse\nПривет мир\n€ and § ÿ raw\n'
	assert editor_bytes_text(editor.text) == expected
	editor.save_document()
	assert !editor.modified
	edited := os.read_bytes(path) or { panic(err) }
	assert edited == expected.bytes()

	mut reader := TextEditorApp{
		visible_rows: 4
	}
	reader.set_path(path)
	reader.open_document()
	assert editor_bytes_text(reader.text) == expected
}

fn test_editor_ascii_editing_is_unchanged() {
	mut editor := TextEditorApp{
		visible_rows: 4
	}
	editor.key_input('hello\nworld\tx')
	assert editor_bytes_text(editor.text) == 'hello\nworld    x'
	editor.key_input('\x1b[A!')
	assert editor_bytes_text(editor.text) == 'hello!\nworld    x'
	assert editor.cursor == 6
	editor.key_input('\x1b[H\x1b[C\x1b[3~\x1b[B\x7f')
	assert editor_bytes_text(editor.text) == 'hllo!\norld    x'
	assert editor.cursor == 6
	assert editor_utf8_cursor_x(mut editor) == editor_padding
}
