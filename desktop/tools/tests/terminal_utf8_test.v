// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.utf8

fn test_terminal_gives_each_cyrillic_letter_one_cell() {
	mut terminal := TerminalApp{}
	terminal.set_geometry(3, 10)
	terminal.ingest_output('привет'.bytes())
	assert terminal.cursor_column == 6
	assert terminal.screen[0] == `п`
	assert terminal.screen[5] == `т`
	assert terminal.screen[6] == ` `
	assert terminal.row_string(0) == 'привет'

	// Autowrap counts letters, not bytes.
	terminal.ingest_output('\r\nабвгдежзийкл'.bytes())
	assert terminal.row_string(1) == 'абвгдежзий'
	assert terminal.row_string(2) == 'кл'
	assert terminal.cursor_row == 2
	assert terminal.cursor_column == 2
}

fn test_terminal_resumes_a_sequence_split_across_reads() {
	mut terminal := TerminalApp{}
	terminal.set_geometry(2, 20)
	// й, € and an emoji, split after every byte of the longer sequences.
	terminal.ingest_output([u8(0xd0)])
	assert terminal.cursor_column == 0
	terminal.ingest_output([u8(0xb9), 0xe2])
	terminal.ingest_output([u8(0x82)])
	terminal.ingest_output([u8(0xac), 0xf0, 0x9f])
	terminal.ingest_output([u8(0x98), 0x80])
	terminal.ingest_output('!'.bytes())
	assert terminal.row_string(0) == 'й€😀!'
	assert terminal.cursor_column == 4
}

fn test_terminal_edits_multibyte_text_by_cell() {
	mut terminal := TerminalApp{}
	terminal.set_geometry(2, 20)
	terminal.ingest_output('при\b\x1b[K'.bytes())
	assert terminal.row_string(0) == 'пр'
	assert terminal.cursor_column == 2

	// Canonical erase echo over a two-byte letter.
	terminal.ingest_output('и\b \b'.bytes())
	assert terminal.row_string(0) == 'пр'
	assert terminal.cursor_column == 2

	terminal.ingest_output('ивет\x1b[3DX'.bytes())
	assert terminal.row_string(0) == 'приXет'
	assert terminal.cursor_column == 4
	terminal.ingest_output('\x1b[1P'.bytes())
	assert terminal.row_string(0) == 'приXт'
	terminal.ingest_output('\x1b[2@'.bytes())
	assert terminal.row_string(0) == 'приX  т'
	terminal.ingest_output('\x1b[4h€\x1b[4l'.bytes())
	assert terminal.row_string(0) == 'приX€  т'
	assert terminal.cursor_column == 5
}

fn test_terminal_replaces_malformed_utf8_without_swallowing_text() {
	r := terminal_replacement_char
	mut terminal := TerminalApp{}
	terminal.set_geometry(2, 40)
	// A stray continuation byte, a byte that can never lead, and a lead cut
	// short by ASCII: each costs one cell and the following byte survives.
	terminal.ingest_output([u8(0x80), `a`, 0xff, `b`, 0xd0, `c`])
	assert terminal.screen[..6] == [r, `a`, r, `b`, r, `c`]
	assert terminal.cursor_column == 6

	// Overlong, surrogate and past-U+10FFFF forms are rejected at the byte
	// that breaks them, each remaining byte then replaced on its own.
	terminal.ingest_output('\r\x1b[K'.bytes())
	terminal.ingest_output([u8(0xc0), 0xaf, 0xe0, 0x80, 0xaf, `x`])
	assert terminal.screen[..6] == [r, r, r, r, r, `x`]
	terminal.ingest_output('\r\x1b[K'.bytes())
	terminal.ingest_output([u8(0xed), 0xa0, 0x80, 0xf4, 0x90, 0x80, 0x80, `y`])
	assert terminal.screen[..8] == [r, r, r, r, r, r, r, `y`]

	// A sequence interrupted by an escape is replaced, and the escape still runs.
	terminal.ingest_output('\r\x1b[K'.bytes())
	terminal.ingest_output([u8(0xe2), 0x82, 0x1b, `[`, `C`, `z`])
	assert terminal.screen[..3] == [r, ` `, `z`]
	assert terminal.escape_state == 0
	assert terminal.utf8_needed == 0

	// Encoded C1 controls have no glyph and take no cell.
	terminal.ingest_output('\r\x1b[K'.bytes())
	terminal.ingest_output([u8(`a`), 0xc2, 0x85, `b`])
	assert terminal.row_string(0) == 'ab'
	assert utf8.validate_str(terminal.row_string(0))
}

fn test_terminal_repeats_a_multibyte_character() {
	mut terminal := TerminalApp{}
	terminal.set_geometry(2, 20)
	terminal.ingest_output('ж\x1b[3b'.bytes())
	assert terminal.row_string(0) == 'жжжж'
	assert terminal.cursor_column == 4
	// REP defaults to one repeat, and may straddle two reads.
	terminal.ingest_output('€\x1b['.bytes())
	terminal.ingest_output('b'.bytes())
	assert terminal.row_string(0) == 'жжжж€€'
	assert terminal.last_printed == `€`
}

fn test_terminal_renders_multibyte_rows_as_valid_utf8() {
	mut terminal := TerminalApp{}
	terminal.set_geometry(3, 12)
	terminal.ingest_output('§ é € й'.bytes())
	terminal.ingest_output([u8(0xd0)])
	rendered := terminal.rendered_row(0)
	assert utf8.validate_str(rendered)
	assert rendered == '§ é € й_'
	assert rendered.runes().len == 8

	// The cursor replaces the letter under it, not one of its bytes.
	terminal.ingest_output([u8(0xb9)])
	terminal.ingest_output('\x1b[4D'.bytes())
	cursor_row := terminal.rendered_row(0)
	assert utf8.validate_str(cursor_row)
	assert cursor_row == '§ é _ йй'
}

fn test_terminal_keeps_multibyte_text_in_history_and_rebuild_snapshot() {
	mut terminal := TerminalApp{}
	terminal.set_geometry(2, 8)
	terminal.ingest_output('привет\r\nмир\r\n\$ ñ'.bytes())
	assert terminal.lines.len == 1
	assert terminal.lines[0] == 'привет'
	assert utf8.validate_str(terminal.lines[0])
	snapshot := terminal.rebuild_snapshot()
	assert snapshot == 'привет\r\nмир\r\n\$ ñ\r\n'

	// The replacement Terminal parses the snapshot back into the same cells.
	mut replacement := TerminalApp{}
	replacement.set_geometry(4, 8)
	replacement.ingest_output(snapshot.bytes())
	assert replacement.row_string(0) == 'привет'
	assert replacement.row_string(2) == '\$ ñ'

	// Resizing and the alternate screen keep code points intact.
	terminal.set_geometry(3, 4)
	assert terminal.row_string(0) == 'мир'
	terminal.ingest_output('\x1b[?1049hвим'.bytes())
	assert terminal.row_string(0) == 'вим'
	terminal.ingest_output('\x1b[?1049l'.bytes())
	assert terminal.row_string(0) == 'мир'
	assert terminal.row_string(1) == '\$ ñ'
}
