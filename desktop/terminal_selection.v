// SPDX-License-Identifier: GPL-2.0-or-later
// Selections use the same one-code-point cells as the bounded VT display.
module main

import ui2
import encoding.utf8

const terminal_action_copy = 'term.selection.copy'
const terminal_selection_status_height = 22
const terminal_key_cmd_copy = '\x1b[99;9u'
const terminal_key_cmd_copy_caps = '\x1b[67;9u'
const terminal_selection_click_interval_ms = u64(500)
const terminal_selection_click_slop = 5

enum TerminalSelectionUnit {
	character
	word
	line
}

// Click recognition and drag origins contain only values; no view or text is
// retained across output, scrollback eviction or a change of terminal screen.
struct TerminalSelectionClick {
	count int
	x int
	y int
	row int = -1
	at_ms u64
}

struct TerminalSelectionPoint {
	row int = -1
	column int
}

fn terminal_point_before(left TerminalSelectionPoint, right TerminalSelectionPoint) bool {
	return left.row < right.row || (left.row == right.row && left.column < right.column)
}

fn (a &TerminalApp) has_selection() bool {
	return a.selection_anchor.row >= 0 && a.selection_head.row >= 0
		&& (a.selection_anchor.row != a.selection_head.row || a.selection_anchor.column != a.selection_head.column)
}

fn (a &TerminalApp) selection_bounds() (TerminalSelectionPoint, TerminalSelectionPoint) {
	if terminal_point_before(a.selection_head, a.selection_anchor) { return a.selection_head, a.selection_anchor }
	return a.selection_anchor, a.selection_head
}

fn (mut a TerminalApp) clear_selection() {
	a.selection_anchor = TerminalSelectionPoint{}
	a.selection_head = TerminalSelectionPoint{}
	a.selection_dragging = false
	a.selection_unit = .character
	a.selection_origin_start = TerminalSelectionPoint{}
	a.selection_origin_end = TerminalSelectionPoint{}
	a.selection_click = TerminalSelectionClick{}
}

fn terminal_selection_click_near(previous TerminalSelectionClick, x int, y int) bool {
	return x >= previous.x - terminal_selection_click_slop && x <= previous.x + terminal_selection_click_slop
		&& y >= previous.y - terminal_selection_click_slop && y <= previous.y + terminal_selection_click_slop
}

fn terminal_selection_click_count(previous TerminalSelectionClick, point TerminalSelectionPoint, x int, y int, now u64) int {
	if previous.count == 0 || previous.count == 3 || previous.row != point.row
		|| now == ~u64(0) || previous.at_ms == ~u64(0) || now < previous.at_ms
		|| now - previous.at_ms > terminal_selection_click_interval_ms
		|| !terminal_selection_click_near(previous, x, y) { return 1 }
	return previous.count + 1
}

// Treat Unicode letters/numbers and underscore as words. Marks follow the
// surrounding letters in the common combining-mark blocks; every cell still
// represents one code point, as it does in the terminal display.
fn terminal_selection_word_class(ch rune) int {
	if utf8.is_space(ch) { return 0 }
	if ch == `_` || utf8.is_letter(ch) || utf8.is_number(ch)
		|| (ch >= 0x0300 && ch <= 0x036f) || (ch >= 0x1ab0 && ch <= 0x1aff)
		|| (ch >= 0x1dc0 && ch <= 0x1dff) || (ch >= 0x20d0 && ch <= 0x20ff)
		|| (ch >= 0xfe20 && ch <= 0xfe2f) { return 1 }
	return 2
}

fn (a &TerminalApp) selection_line_bounds(row int) (TerminalSelectionPoint, TerminalSelectionPoint) {
	first := TerminalSelectionPoint{row: row}
	row_count := if a.alternate_screen { a.rows } else { a.lines.len + a.rows }
	last := if row + 1 < row_count { TerminalSelectionPoint{row: row + 1} }
		else { TerminalSelectionPoint{row: row, column: a.selection_row_cells(row)} }
	return first, last
}

fn (a &TerminalApp) selection_word_bounds(point TerminalSelectionPoint) (TerminalSelectionPoint, TerminalSelectionPoint) {
	cells := a.selection_row_cells(point.row)
	if cells == 0 { return a.selection_line_bounds(point.row) }
	if point.column >= cells { return point, point }
	history := !a.alternate_screen && point.row >= 0 && point.row < a.lines.len
	text := if history { a.lines[point.row] } else { '' }
	screen_row := if a.alternate_screen { point.row } else { point.row - a.lines.len }
	mut byte_offset := 0
	mut first := 0
	mut previous_class := -1
	mut target_class := -1
	mut last := cells
	// Scan a UTF-8 history row once, rather than repeatedly finding byte
	// offsets while walking backwards through a long word.
	for column in 0 .. cells {
		ch := if history { utf8.get_rune(text, byte_offset) } else { a.screen[screen_row * a.columns + column] }
		if history {
			length := editor_utf8_length(text[byte_offset])
			byte_offset += if length > 0 && byte_offset + length <= text.len { length } else { 1 }
		}
		class := terminal_selection_word_class(ch)
		if column <= point.column {
			if class != previous_class || class == 2 { first = column }
			previous_class = class
			if column == point.column {
				target_class = class
				if class == 2 { last = column + 1; break }
			}
		} else if class != target_class { last = column; break }
	}
	return TerminalSelectionPoint{row: point.row, column: first}, TerminalSelectionPoint{row: point.row, column: last}
}

fn terminal_text_cell_offset(text string, column int) int {
	mut at := 0
	mut cell := 0
	for at < text.len && cell < column {
		length := editor_utf8_length(text[at])
		at += if length > 0 && at + length <= text.len { length } else { 1 }
		cell++
	}
	return at
}

fn (a &TerminalApp) selection_row_cells(row int) int {
	if !a.alternate_screen && row >= 0 && row < a.lines.len {
		text := a.lines[row]
		mut at := 0
		mut cells := 0
		for at < text.len {
			length := editor_utf8_length(text[at])
			at += if length > 0 && at + length <= text.len { length } else { 1 }
			cells++
		}
		return cells
	}
	index := if a.alternate_screen { row } else { row - a.lines.len }
	if index < 0 || index >= a.rows { return 0 }
	start := index * a.columns
	mut end := start + a.columns
	for end > start && a.screen[end - 1] == ` ` { end-- }
	return end - start
}

fn (a &TerminalApp) pointer_selection_point(x int, y int) TerminalSelectionPoint {
	visible := terminal_clamp((y - terminal_toolbar_height - terminal_padding) / terminal_row_height, 0, a.visible_rows - 1)
	row := if a.alternate_screen { visible } else { a.lines.len - a.scroll + visible }
	column := if x > terminal_padding { (x - terminal_padding + terminal_column_width / 2) / terminal_column_width } else { 0 }
	return TerminalSelectionPoint{row: row, column: terminal_clamp(column, 0, a.selection_row_cells(row))}
}

fn (a &TerminalApp) pointer_selection_cell(x int, y int) TerminalSelectionPoint {
	point := a.pointer_selection_point(x, y)
	column := if x > terminal_padding { (x - terminal_padding) / terminal_column_width } else { 0 }
	return TerminalSelectionPoint{row: point.row, column: terminal_clamp(column, 0, a.selection_row_cells(point.row))}
}

fn (mut a TerminalApp) expand_selection_to(x int, y int) {
	if a.selection_unit == .character {
		a.selection_head = a.pointer_selection_point(x, y)
		return
	}
	point := a.pointer_selection_cell(x, y)
	first, last := if a.selection_unit == .line { a.selection_line_bounds(point.row) } else { a.selection_word_bounds(point) }
	if terminal_point_before(first, a.selection_origin_start) {
		a.selection_anchor = a.selection_origin_end
		a.selection_head = first
	} else {
		a.selection_anchor = a.selection_origin_start
		a.selection_head = if terminal_point_before(last, a.selection_origin_end) { a.selection_origin_end } else { last }
	}
}

fn (a &TerminalApp) pointer_input_enabled() bool { return true }
fn (a &TerminalApp) pointer_moves_matter() bool { return a.selection_dragging }

fn (mut a TerminalApp) pointer_event(phase AppPointerPhase, button AppPointerButton, scroll int, x int, y int, width int, height int) {
	a.selection_pointer_event_at(phase, button, scroll, x, y, width, height, desktop_monotonic_ms())
}

fn (mut a TerminalApp) selection_pointer_event_at(phase AppPointerPhase, button AppPointerButton, scroll int, x int, y int, width int, height int, now u64) {
	if width <= 0 || height <= 0 || a.rows <= 0 || a.columns <= 0 { return }
	bottom := height - terminal_selection_status_height
	max_scroll := if a.alternate_screen { 0 } else { a.lines.len }
	if phase == .scroll && y >= terminal_toolbar_height && y < bottom {
		a.selection_click = TerminalSelectionClick{}
		a.scroll = terminal_clamp(a.scroll - scroll * 3, 0, max_scroll)
		return
	}
	if phase == .down && button == .left && y >= terminal_toolbar_height && y < bottom {
		a.copy_client.clear_status()
		a.search_open = false
		a.search_pending_len = 0
		a.search_escape_state = 0
		point := a.pointer_selection_point(x, y)
		count := terminal_selection_click_count(a.selection_click, point, x, y, now)
		a.selection_click = TerminalSelectionClick{count: count, x: x, y: y, row: point.row, at_ms: now}
		a.selection_unit = if count == 2 { TerminalSelectionUnit.word } else if count == 3 { TerminalSelectionUnit.line } else { TerminalSelectionUnit.character }
		first, last := if count == 3 { a.selection_line_bounds(point.row) }
			else if count == 2 { a.selection_word_bounds(a.pointer_selection_cell(x, y)) } else { point, point }
		a.selection_origin_start = first
		a.selection_origin_end = last
		a.selection_anchor = first
		a.selection_head = last
		a.selection_dragging = true
	} else if a.selection_dragging && (phase == .move || phase == .up) {
		if !terminal_selection_click_near(a.selection_click, x, y) { a.selection_click = TerminalSelectionClick{} }
		if y < terminal_toolbar_height + terminal_padding { a.scroll = terminal_clamp(a.scroll + 1, 0, max_scroll) }
		else if y >= bottom - terminal_padding { a.scroll = terminal_clamp(a.scroll - 1, 0, max_scroll) }
		a.expand_selection_to(x, y)
		if phase == .up { a.selection_dragging = false }
	} else if phase == .down || phase == .scroll {
		a.selection_click = TerminalSelectionClick{}
	}
}

fn (a &TerminalApp) selected_bytes() []u8 {
	if !a.has_selection() { return []u8{} }
	first, last := a.selection_bounds()
	mut length := 0
	for row in first.row .. last.row + 1 {
		cells := a.selection_row_cells(row)
		start := terminal_clamp(if row == first.row { first.column } else { 0 }, 0, cells)
		end := terminal_clamp(if row == last.row { last.column } else { cells }, start, cells)
		if !a.alternate_screen && row < a.lines.len {
			text := a.lines[row]
			length += terminal_text_cell_offset(text, end) - terminal_text_cell_offset(text, start)
		} else {
			screen_row := if a.alternate_screen { row } else { row - a.lines.len }
			for column in start .. end { length += terminal_utf8_len(a.screen[screen_row * a.columns + column]) }
		}
		if row < last.row { length++ }
		// Never allocate unbounded output, and never publish a truncated copy.
		if length > clipboard_max_bytes { return []u8{len: clipboard_max_bytes + 1} }
	}
	mut output := []u8{cap: length}
	for row in first.row .. last.row + 1 {
		cells := a.selection_row_cells(row)
		start := terminal_clamp(if row == first.row { first.column } else { 0 }, 0, cells)
		end := terminal_clamp(if row == last.row { last.column } else { cells }, start, cells)
		if !a.alternate_screen && row < a.lines.len {
			text := a.lines[row]
			from := terminal_text_cell_offset(text, start)
			to := terminal_text_cell_offset(text, end)
			for index in from .. to { output << text[index] }
		} else {
			screen_row := if a.alternate_screen { row } else { row - a.lines.len }
			for column in start .. end { terminal_append_utf8(mut output, a.screen[screen_row * a.columns + column]) }
		}
		if row < last.row { output << u8(`\n`) }
	}
	return output
}

fn (mut a TerminalApp) copy_selection() {
	if !a.has_selection() { return }
	bytes := a.selected_bytes()
	a.copy_client.queue(editor_bytes_text(bytes))
	if bytes.cap > 0 { unsafe { bytes.free() } }
}

fn (mut a TerminalApp) take_clipboard_copy_request() []u8 { return a.copy_client.take_request() }
fn (mut a TerminalApp) receive_clipboard_copy_reply(payload string) { a.copy_client.receive_reply(payload) }

fn (a &TerminalApp) build_selection_highlight(mut children []ui2.Element, row int, y int, width int) {
	if !a.has_selection() { return }
	first, last := a.selection_bounds()
	if row < first.row || row > last.row { return }
	cells := a.selection_row_cells(row)
	start := if row == first.row { first.column } else { 0 }
	end := (if row == last.row { last.column } else { cells }) + if row < last.row { 1 } else { 0 }
	x := terminal_padding + start * terminal_column_width
	w := terminal_clamp((end - start) * terminal_column_width, 0, if width - terminal_padding > x { width - terminal_padding - x } else { 0 })
	if w > 0 {
		children << ui2.view('term.selection.highlight', ui2.rect(f64(x), f64(y), f64(w), terminal_row_height), ui2.BoxStyle{bg: u32(0x465a7c)}, [])
	}
}

fn (a &TerminalApp) build_selection_status(mut children []ui2.Element, width int, height int) {
	key := a.copy_client.status_key()
	children << ui2.label('term.selection.status', tr(if key.len > 0 { key } else { 'terminal.selection.hint' }),
		ui2.rect(8, f64(height - terminal_selection_status_height), f64(if width > 16 { width - 16 } else { 1 }), terminal_selection_status_height),
		ui2.TextStyle{color: terminal_text, size: 10})
}

fn (mut a TerminalApp) flush_copy_key() {
	if a.copy_key_len > 0 && a.terminal >= 0 && !a.exited {
		desktop_write_all(a.terminal, &a.copy_key_pending[0], u64(a.copy_key_len))
	}
	a.copy_key_len = 0
}

fn (mut a TerminalApp) expire_copy_key(now u64) bool {
	if a.copy_key_len == 0 || (now != ~u64(0) && now >= a.copy_key_ms && now - a.copy_key_ms < 100) { return false }
	a.flush_copy_key()
	return true
}

fn (mut a TerminalApp) selection_key_input(text string) {
	if text.len == 0 { return }
	a.expire_copy_key(desktop_monotonic_ms())
	mut output := []u8{cap: text.len + a.copy_key_pending.len}
	for byte in text {
		if a.copy_key_len == 0 && byte != 0x1b {
			output << if byte == 8 { u8(0x7f) } else { byte }
			continue
		}
		if a.copy_key_len == 0 { a.copy_key_ms = desktop_monotonic_ms() }
		a.copy_key_pending[a.copy_key_len] = byte
		a.copy_key_len++
		mut matches := false
		mut complete := false
		for chord in [terminal_key_cmd_copy, terminal_key_cmd_copy_caps]! {
			if a.copy_key_len > chord.len { continue }
			mut prefix := true
			for index in 0 .. a.copy_key_len { if a.copy_key_pending[index] != chord[index] { prefix = false; break } }
			if prefix { matches = true; complete = a.copy_key_len == chord.len; break }
		}
		if complete {
			// Preserve typing order when a chord follows ordinary shell input.
			if output.len > 0 && a.terminal >= 0 && !a.exited { desktop_write_all(a.terminal, output.data, u64(output.len)) }
			output.clear()
			a.copy_key_len = 0
			a.copy_selection()
		} else if !matches {
			// A new Escape can begin a chord after an unmatched older prefix.
			// Forward every older byte and retain only that new prefix.
			keep_escape := byte == 0x1b && a.copy_key_len > 1
			forwarded := a.copy_key_len - if keep_escape { 1 } else { 0 }
			for index in 0 .. forwarded { output << a.copy_key_pending[index] }
			a.copy_key_len = if keep_escape { 1 } else { 0 }
			if keep_escape { a.copy_key_pending[0] = byte; a.copy_key_ms = desktop_monotonic_ms() }
		}
	}
	if output.len > 0 && a.terminal >= 0 && !a.exited { desktop_write_all(a.terminal, output.data, u64(output.len)) }
	unsafe { output.free() }
}
