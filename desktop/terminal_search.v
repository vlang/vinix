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
	a.clear_selection()
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
		terminal_action_find { a.flush_copy_key(); a.selection_dragging = false; a.search_open = !a.search_open }
		'term.find.field' { a.flush_copy_key(); a.selection_dragging = false; a.search_open = true }
		terminal_action_find_previous { a.find_output(-1) }
		terminal_action_find_next { a.find_output(1) }
		terminal_action_clear_history { a.clear_scrollback() }
		else { return false }
	}
	return true
}

fn (a &TerminalApp) build_search_toolbar(mut children []ui2.Element, width int) {
	left := if width > 16 { 8 } else { 0 }
	available := if width > 16 { width - 16 } else if width > 0 { width } else { 1 }
	gap := if available >= 48 { 8 } else if available >= 24 { 4 } else { 0 }
	group_width := if a.search_open && available >= 32 { available / 2 - gap } else { available }
	unit := if group_width >= 3 + 2 * gap { (group_width - 2 * gap) / 3 } else { 1 }
	find_width := if unit < 60 { unit } else { 60 }
	copy_width := find_width
	mode_left := left + find_width + copy_width + 2 * gap
	mode_width := terminal_clamp(group_width - find_width - copy_width - 2 * gap, 1, 64)
	if available >= 3 {
		children << ui2.button(terminal_action_find, tr('terminal.find'), ui2.rect(f64(left), 3, f64(find_width), 24),
			ui2.BoxStyle{ bg: terminal_button, radius: 4 }, ui2.TextStyle{ color: terminal_text, size: 11, align: .center })
		children << ui2.Element{
			...ui2.button(terminal_action_copy, tr('terminal.selection.copy'), ui2.rect(f64(left + find_width + gap), 3, f64(copy_width), 24),
				ui2.BoxStyle{ bg: terminal_button, radius: 4 }, ui2.TextStyle{ color: terminal_text, size: 11, align: .center })
			enabled: a.has_selection()
			tooltip: tr(a.selection_hint_key())
		}
	}
	children << ui2.Element{
		...ui2.button(terminal_action_selection_mode, tr(if a.selection_block { 'terminal.selection.block' } else { 'terminal.selection.text' }),
			ui2.rect(f64(if available >= 3 { mode_left } else { left }), 3, f64(if available >= 3 { mode_width } else { available }), 24),
			ui2.BoxStyle{ bg: terminal_button, radius: 4 }, ui2.TextStyle{ color: terminal_text, size: 11, align: .center })
		checked: a.selection_block
		tooltip: tr('terminal.selection.mode.help')
	}
	right := left + available
	next_left := mode_left + mode_width + gap
	if !a.search_open {
		if right - next_left >= 32 {
			children << ui2.button(terminal_action_clear_history, tr('terminal.history.clear'), ui2.rect(f64(next_left), 3, f64(terminal_clamp(right - next_left, 1, 148)), 24),
				ui2.BoxStyle{ bg: terminal_button, radius: 4 }, ui2.TextStyle{ color: terminal_text, size: 11, align: .center })
		}
		return
	}
	remaining := right - next_left
	if remaining < 3 { return }
	navigation_width := terminal_clamp((remaining - 2 * gap) / 4, 1, 32)
	field_width := remaining - 2 * navigation_width - 2 * gap
	children << ui2.Element{
		...ui2.text_field('term.find.field', tr('terminal.find.placeholder'), editor_bytes_text(a.search_query),
			ui2.rect(f64(next_left), 3, f64(field_width), 24), ui2.BoxStyle{ bg: terminal_button, radius: 4 },
			ui2.TextStyle{ color: terminal_text, size: 11 }, 0)
		focused: true
	}
	children << ui2.Element{
		...ui2.button(terminal_action_find_previous, '<', ui2.rect(f64(next_left + field_width + gap), 3, f64(navigation_width), 24),
			ui2.BoxStyle{ bg: terminal_button, radius: 4 }, ui2.TextStyle{ color: terminal_text, size: 12, align: .center })
		tooltip: tr('terminal.find.previous')
	}
	children << ui2.Element{
		...ui2.button(terminal_action_find_next, '>', ui2.rect(f64(right - navigation_width), 3, f64(navigation_width), 24),
			ui2.BoxStyle{ bg: terminal_button, radius: 4 }, ui2.TextStyle{ color: terminal_text, size: 12, align: .center })
		tooltip: if a.search_query.len > 0 && a.search_match < 0 { tr('terminal.find.no_match') } else { tr('terminal.find.next') }
	}
}
