// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

const terminal_toolbar_height = 30
const terminal_action_find = 'term.find'
const terminal_action_find_previous = 'term.find.previous'
const terminal_action_find_next = 'term.find.next'
const terminal_action_clear_history = 'term.history.clear'
const terminal_search_limit = 128

fn (mut a TerminalApp) clear_scrollback() {
	for line in a.lines { if line.len > 0 { unsafe { line.free() } } }
	a.lines.clear()
	a.scroll = 0
	a.search_match = -1
}

// Search physical output rows, including the current screen. Use plain row
// text rather than the rendered cursor, which can cover a matching letter.
fn (mut a TerminalApp) find_output(direction int) bool {
	a.ensure_screen()
	count := if a.alternate_screen { a.rows } else { a.lines.len + a.rows }
	if a.search_query.len == 0 || count <= 0 { a.search_match = -1; return false }
	query := editor_bytes_text(a.search_query)
	start := if a.search_match >= 0 && a.search_match < count { a.search_match } else if direction < 0 { 0 } else { count - 1 }
	for step in 1 .. count + 1 {
		index := ((start + direction * step) % count + count) % count
		history := !a.alternate_screen && index < a.lines.len
		text := if history { a.lines[index] } else { a.row_string(if a.alternate_screen { index } else { index - a.lines.len }) }
		found := text.contains(query)
		if !history && text.len > 0 { unsafe { text.free() } }
		if found {
			a.search_match = index
			a.scroll = if !a.alternate_screen && index < a.lines.len { a.lines.len - index } else { 0 }
			return true
		}
	}
	a.search_match = -1
	return false
}

// Commit an entire UTF-8 character, including when input arrives in chunks.
// A character that would exceed the query limit is discarded as a whole.
fn (mut a TerminalApp) append_search_byte(byte u8) {
	unsafe { a.search_query.flags |= .noslices }
	if a.search_pending_len > 0 {
		if editor_utf8_follows(a.search_pending[0], a.search_pending_len, byte) {
			a.search_pending[a.search_pending_len] = byte
			a.search_pending_len++
			if a.search_pending_len == editor_utf8_length(a.search_pending[0]) {
				if a.search_query.len + a.search_pending_len <= terminal_search_limit {
					for index in 0 .. a.search_pending_len { a.search_query << a.search_pending[index] }
				}
				a.search_pending_len = 0
			}
			return
		}
		a.search_pending_len = 0
	}
	length := editor_utf8_length(byte)
	if length > 1 {
		a.search_pending[0] = byte
		a.search_pending_len = 1
	} else if byte >= 32 && byte < 127 && a.search_query.len < terminal_search_limit {
		a.search_query << byte
	}
}

fn (mut a TerminalApp) search_input(text string) {
	if text in ['\r', '\n'] { a.find_output(1); return }
	if text == '\x1b' { a.search_open = false; a.search_pending_len = 0; a.search_escape_state = 0; return }
	for byte in text {
		if a.search_escape_state > 0 {
			if a.search_escape_state == 1 {
				a.search_escape_state = if byte == `[` { 2 } else if byte == `O` { 3 } else { 0 }
			} else if byte >= 0x40 && byte <= 0x7e {
				a.search_escape_state = 0
			}
			continue
		}
		if byte == 0x1b { a.search_escape_state = 1; a.search_pending_len = 0; continue }
		if byte == 8 || byte == 127 {
			if a.search_pending_len > 0 { a.search_pending_len = 0 } else if a.search_query.len > 0 {
				a.search_query.trim(editor_char_before(a.search_query, a.search_query.len))
			}
		} else {
			a.append_search_byte(byte)
		}
	}
	a.search_match = -1
	a.find_output(1)
}

fn (mut a TerminalApp) paste_search(text string) {
	a.search_pending_len = 0
	for byte in text { a.append_search_byte(byte) }
	a.search_pending_len = 0
	a.search_match = -1
	a.find_output(1)
}

fn (mut a TerminalApp) handle_search(action string) bool {
	match action {
		terminal_action_find { a.search_open = !a.search_open }
		'term.find.field' { a.search_open = true }
		terminal_action_find_previous { a.find_output(-1) }
		terminal_action_find_next { a.find_output(1) }
		terminal_action_clear_history { a.clear_scrollback() }
		else { return false }
	}
	return true
}

fn (a &TerminalApp) build_search_toolbar(mut children []ui2.Element, width int) {
	children << ui2.button(terminal_action_find, tr('terminal.find'), ui2.rect(8, 3, 60, 24),
		ui2.BoxStyle{ bg: terminal_button, radius: 4 }, ui2.TextStyle{ color: terminal_text, size: 11, align: .center })
	if !a.search_open {
		children << ui2.button(terminal_action_clear_history, tr('terminal.history.clear'), ui2.rect(76, 3, 148, 24),
			ui2.BoxStyle{ bg: terminal_button, radius: 4 }, ui2.TextStyle{ color: terminal_text, size: 11, align: .center })
		return
	}
	field_width := if width > 164 { width - 164 } else { 1 }
	children << ui2.Element{
		...ui2.text_field('term.find.field', tr('terminal.find.placeholder'), editor_bytes_text(a.search_query),
			ui2.rect(76, 3, f64(field_width), 24), ui2.BoxStyle{ bg: terminal_button, radius: 4 },
			ui2.TextStyle{ color: terminal_text, size: 11 }, 0)
		focused: true
	}
	children << ui2.Element{
		...ui2.button(terminal_action_find_previous, '<', ui2.rect(f64(width - 80), 3, 32, 24),
			ui2.BoxStyle{ bg: terminal_button, radius: 4 }, ui2.TextStyle{ color: terminal_text, size: 12, align: .center })
		tooltip: tr('terminal.find.previous')
	}
	children << ui2.Element{
		...ui2.button(terminal_action_find_next, '>', ui2.rect(f64(width - 42), 3, 32, 24),
			ui2.BoxStyle{ bg: terminal_button, radius: 4 }, ui2.TextStyle{ color: terminal_text, size: 12, align: .center })
		tooltip: if a.search_query.len > 0 && a.search_match < 0 { tr('terminal.find.no_match') } else { tr('terminal.find.next') }
	}
}
