// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// A terminal, built into the desktop.
//
// It runs the shell on a Unix98 pseudo-terminal. The kernel line discipline
// owns echo, canonical editing and terminal-generated signals; this process is
// the display and keyboard side of the PTY master. The display implements the
// bounded VT surface advertised by TERM=linux, including the cursor-addressed
// operations used by full-screen programs such as Vim.
module main

import ui2

// KeyboardApp is an application that takes typed input. The desktop routes
// keystrokes to the focused window's application when it is one of these, and
// otherwise treats them as its own shortcuts.
interface KeyboardApp {
mut:
	key_input(text string)
}

// PollingApp is an application with something happening that the user did not
// cause — output arriving from a child process, say. The desktop asks every
// one of them each frame whether anything changed.
interface PollingApp {
mut:
	poll() bool
}

enum AppPointerPhase {
	move
	down
	up
	scroll
}

enum AppPointerButton {
	no_button
	left
	middle
	right
}

interface PointerApp {
mut:
	pointer_input_enabled() bool
	pointer_event(phase AppPointerPhase, button AppPointerButton, scroll int, x int, y int, width int, height int)
}

interface ClosingApp {
mut:
	close_app()
}

// Both userlands bundle Zsh and a ready-to-use Oh My Zsh configuration.
const terminal_shell = '/bin/zsh'
const terminal_scrollback = 400
const terminal_read_chunk = 4096
const terminal_reads_per_frame = 8
const terminal_csi_parameter_limit = 16
const terminal_default_rows = 24
const terminal_default_columns = 80

const terminal_action_scroll_up = 'term.scroll.up'
const terminal_action_scroll_down = 'term.scroll.down'

const terminal_row_height = 16
const terminal_column_width = 8
const terminal_padding = 8

struct TerminalApp {
mut:
	// The visible terminal is a fixed grid of bytes. Keeping it flat makes
	// scrolling and erasing deterministic and avoids one allocation per cell.
	screen         []u8
	rendered_rows  []string
	dirty_rows     []bool
	rows           int
	columns        int
	cursor_row     int
	cursor_column  int
	cursor_visible bool = true
	autowrap       bool = true
	wrap_pending   bool
	insert_mode    bool
	last_printed   u8 = ` `

	scroll_top          int
	scroll_bottom       int
	saved_cursor_row    int
	saved_cursor_column int

	// Vim uses the alternate screen. Preserve the shell's main screen so leaving
	// Vim reveals the command that launched it and its prompt again.
	alternate_screen   bool
	main_screen        []u8
	main_rows          int
	main_columns       int
	main_cursor_row    int
	main_cursor_column int

	// Completed rows pushed off the top of the main screen.
	lines  []string
	scroll int

	// Escape parser state survives non-blocking reads. CSI parameters use a
	// fixed array so a noisy child cannot allocate without bound.
	escape_state            u8
	escape_string_remaining int
	csi_params              [terminal_csi_parameter_limit]int
	csi_count               int
	csi_private             u8
	csi_has_digits          bool

	read_buf []u8

	pid      int = -1
	terminal int = -1
	started  bool
	exited   bool
	error    string

	terminal_rows    int
	terminal_columns int
	visible_rows     int = 1
}

fn open_terminal(mut _ Desktop) !NativeApp {
	return &TerminalApp{
		read_buf: []u8{len: terminal_read_chunk}
	}
}

fn terminal_clamp(value int, low int, high int) int {
	if value < low {
		return low
	}
	if value > high {
		return high
	}
	return value
}

fn terminal_blank_screen(rows int, columns int) []u8 {
	return []u8{len: rows * columns, init: ` `}
}

fn terminal_resize_cells(cells []u8, old_rows int, old_columns int, rows int, columns int) []u8 {
	mut resized := terminal_blank_screen(rows, columns)
	copy_rows := if old_rows < rows { old_rows } else { rows }
	copy_columns := if old_columns < columns { old_columns } else { columns }
	if old_columns <= 0 || cells.len < old_rows * old_columns {
		return resized
	}
	for row in 0 .. copy_rows {
		for column in 0 .. copy_columns {
			resized[row * columns + column] = cells[row * old_columns + column]
		}
	}
	return resized
}

fn (mut a TerminalApp) release_rendered_rows() {
	for text in a.rendered_rows {
		if text.len > 0 {
			unsafe { text.free() }
		}
	}
	if a.rendered_rows.cap > 0 {
		unsafe { a.rendered_rows.free() }
	}
	if a.dirty_rows.cap > 0 {
		unsafe { a.dirty_rows.free() }
	}
	a.rendered_rows = []string{}
	a.dirty_rows = []bool{}
}

fn (mut a TerminalApp) reset_row_cache() {
	a.release_rendered_rows()
	a.rendered_rows = []string{len: a.rows}
	a.dirty_rows = []bool{len: a.rows, init: true}
}

fn (mut a TerminalApp) set_geometry(rows int, columns int) {
	next_rows := if rows > 0 { rows } else { 1 }
	next_columns := if columns > 0 { columns } else { 1 }
	if a.rows == next_rows && a.columns == next_columns && a.screen.len == next_rows * next_columns {
		return
	}

	old_screen := a.screen
	a.screen = terminal_resize_cells(old_screen, a.rows, a.columns, next_rows, next_columns)
	if old_screen.cap > 0 {
		unsafe { old_screen.free() }
	}
	if a.alternate_screen && a.main_screen.len > 0 {
		old_main := a.main_screen
		a.main_screen = terminal_resize_cells(old_main, a.main_rows, a.main_columns, next_rows, next_columns)
		if old_main.cap > 0 {
			unsafe { old_main.free() }
		}
		a.main_rows = next_rows
		a.main_columns = next_columns
		a.main_cursor_row = terminal_clamp(a.main_cursor_row, 0, next_rows - 1)
		a.main_cursor_column = terminal_clamp(a.main_cursor_column, 0, next_columns - 1)
	}
	a.rows = next_rows
	a.columns = next_columns
	a.cursor_row = terminal_clamp(a.cursor_row, 0, a.rows - 1)
	a.cursor_column = terminal_clamp(a.cursor_column, 0, a.columns - 1)
	a.scroll_top = 0
	a.scroll_bottom = a.rows
	a.wrap_pending = false
	a.reset_row_cache()
}

fn (mut a TerminalApp) ensure_screen() {
	if a.rows <= 0 || a.columns <= 0 || a.screen.len == 0 {
		a.set_geometry(terminal_default_rows, terminal_default_columns)
	}
}

fn (mut a TerminalApp) mark_row_dirty(row int) {
	if row >= 0 && row < a.dirty_rows.len {
		a.dirty_rows[row] = true
	}
}

fn (mut a TerminalApp) mark_all_rows_dirty() {
	for row in 0 .. a.dirty_rows.len {
		a.dirty_rows[row] = true
	}
}

fn (mut a TerminalApp) move_cursor(row int, column int) {
	a.mark_row_dirty(a.cursor_row)
	a.cursor_row = terminal_clamp(row, 0, a.rows - 1)
	a.cursor_column = terminal_clamp(column, 0, a.columns - 1)
	a.wrap_pending = false
	a.mark_row_dirty(a.cursor_row)
}

fn (mut a TerminalApp) clear_cells(first int, after_last int) {
	start := terminal_clamp(first, 0, a.screen.len)
	end := terminal_clamp(after_last, start, a.screen.len)
	for index in start .. end {
		a.screen[index] = ` `
	}
	if a.columns > 0 && end > start {
		first_row := start / a.columns
		last_row := (end - 1) / a.columns
		for row in first_row .. last_row + 1 {
			a.mark_row_dirty(row)
		}
	}
}

fn (a &TerminalApp) row_string(row int) string {
	if row < 0 || row >= a.rows {
		return ''.clone()
	}
	start := row * a.columns
	mut end := start + a.columns
	for end > start && a.screen[end - 1] == ` ` {
		end--
	}
	return a.screen[start..end].bytestr()
}

fn (mut a TerminalApp) push_history_row(row int) {
	a.lines << a.row_string(row)
	for a.lines.len > terminal_scrollback {
		evicted := a.lines[0]
		a.lines.delete(0)
		if evicted.len > 0 {
			unsafe { evicted.free() }
		}
	}
	a.scroll = 0
}

fn (mut a TerminalApp) scroll_region_up(top int, bottom int, count int) {
	if top < 0 || bottom > a.rows || top >= bottom {
		return
	}
	amount := terminal_clamp(count, 1, bottom - top)
	if !a.alternate_screen && top == 0 && bottom == a.rows {
		for row in top .. top + amount {
			a.push_history_row(row)
		}
	}
	for row in top .. bottom - amount {
		from := (row + amount) * a.columns
		to := row * a.columns
		for column in 0 .. a.columns {
			a.screen[to + column] = a.screen[from + column]
		}
	}
	a.clear_cells((bottom - amount) * a.columns, bottom * a.columns)
	for row in top .. bottom {
		a.mark_row_dirty(row)
	}
}

fn (mut a TerminalApp) scroll_region_down(top int, bottom int, count int) {
	if top < 0 || bottom > a.rows || top >= bottom {
		return
	}
	amount := terminal_clamp(count, 1, bottom - top)
	for row := bottom - 1; row >= top + amount; row-- {
		from := (row - amount) * a.columns
		to := row * a.columns
		for column in 0 .. a.columns {
			a.screen[to + column] = a.screen[from + column]
		}
	}
	a.clear_cells(top * a.columns, (top + amount) * a.columns)
	for row in top .. bottom {
		a.mark_row_dirty(row)
	}
}

fn (mut a TerminalApp) line_feed() {
	a.wrap_pending = false
	a.mark_row_dirty(a.cursor_row)
	if a.cursor_row == a.scroll_bottom - 1 {
		a.scroll_region_up(a.scroll_top, a.scroll_bottom, 1)
	} else if a.cursor_row < a.rows - 1 {
		a.cursor_row++
	}
	a.mark_row_dirty(a.cursor_row)
}

fn (mut a TerminalApp) reverse_index() {
	a.wrap_pending = false
	a.mark_row_dirty(a.cursor_row)
	if a.cursor_row == a.scroll_top {
		a.scroll_region_down(a.scroll_top, a.scroll_bottom, 1)
	} else if a.cursor_row > 0 {
		a.cursor_row--
	}
	a.mark_row_dirty(a.cursor_row)
}

fn (mut a TerminalApp) put_visible_byte(ch u8) {
	if a.wrap_pending {
		a.cursor_column = 0
		a.line_feed()
	}
	row_start := a.cursor_row * a.columns
	if a.insert_mode && a.cursor_column < a.columns - 1 {
		for column := a.columns - 1; column > a.cursor_column; column-- {
			a.screen[row_start + column] = a.screen[row_start + column - 1]
		}
	}
	a.screen[row_start + a.cursor_column] = ch
	a.last_printed = ch
	a.mark_row_dirty(a.cursor_row)
	if a.cursor_column == a.columns - 1 {
		a.wrap_pending = a.autowrap
	} else {
		a.cursor_column++
	}
}

fn (mut a TerminalApp) start_shell(rows int, columns int, width int, height int) {
	a.started = true
	shell := desktop_spawn_shell(terminal_shell, rows, columns, width, height) or {
		a.error = 'cannot start ${terminal_shell}'
		a.ingest_output(a.error.bytes())
		a.exited = true
		return
	}
	a.pid = shell.pid
	a.terminal = shell.terminal
	a.terminal_rows = rows
	a.terminal_columns = columns
}

fn (mut a TerminalApp) poll() bool {
	if a.terminal < 0 {
		return false
	}

	mut changed := false
	for _ in 0 .. terminal_reads_per_frame {
		got := desktop_read(a.terminal, a.read_buf.data, u64(terminal_read_chunk))
		if got <= 0 {
			break
		}
		a.ingest_output(a.read_buf[..int(got)])
		changed = true
		if got < terminal_read_chunk {
			break
		}
	}

	if !a.exited && a.pid >= 0 && desktop_child_exited(a.pid) {
		a.ingest_output('\r\n[${terminal_shell} exited]'.bytes())
		a.exited = true
		desktop_close(a.terminal)
		a.terminal = -1
		a.pid = -1
		changed = true
	}
	return changed
}

fn (mut a TerminalApp) ingest_output(output []u8) {
	a.ensure_screen()
	for ch in output {
		if a.escape_state != 0 {
			a.ingest_escape_byte(ch)
			continue
		}
		if ch == 0x1b {
			a.escape_state = 1
			continue
		}
		a.ingest_terminal_byte(ch)
	}
}

fn (mut a TerminalApp) ingest_terminal_byte(ch u8) {
	match ch {
		0, 0x07 {}
		`\n`, 0x0b, 0x0c { a.line_feed() }
		`\r` { a.move_cursor(a.cursor_row, 0) }
		`\t` {
			next_tab := (a.cursor_column + 8) & ~7
			a.move_cursor(a.cursor_row, terminal_clamp(next_tab, 0, a.columns - 1))
		}
		8 {
			a.move_cursor(a.cursor_row, if a.cursor_column > 0 { a.cursor_column - 1 } else { 0 })
		}
		else {
			if ch >= 0x20 && ch != 0x7f {
				a.put_visible_byte(ch)
			}
		}
	}
}

fn (mut a TerminalApp) begin_csi() {
	a.escape_state = 2
	for index in 0 .. terminal_csi_parameter_limit {
		a.csi_params[index] = 0
	}
	a.csi_count = 1
	a.csi_private = 0
	a.csi_has_digits = false
}

fn (mut a TerminalApp) ingest_escape_byte(ch u8) {
	match a.escape_state {
		1 {
			match ch {
				`[` { a.begin_csi() }
				`]` {
					a.escape_state = 6
				}
				`P`, `^`, `_` {
					a.escape_state = 3
				}
				`7` {
					a.saved_cursor_row = a.cursor_row
					a.saved_cursor_column = a.cursor_column
					a.escape_state = 0
				}
				`8` {
					a.move_cursor(a.saved_cursor_row, a.saved_cursor_column)
					a.escape_state = 0
				}
				`D` {
					a.line_feed()
					a.escape_state = 0
				}
				`E` {
					a.cursor_column = 0
					a.line_feed()
					a.escape_state = 0
				}
				`M` {
					a.reverse_index()
					a.escape_state = 0
				}
				`c` {
					a.reset_active_screen()
					a.escape_state = 0
				}
				`(`, `)`, `*`, `+`, `#` {
					a.escape_state = 5
				}
				else {
					a.escape_state = 0
				}
			}
		}
		2 {
			if ch >= `0` && ch <= `9` {
				index := a.csi_count - 1
				if index >= 0 && index < terminal_csi_parameter_limit {
					a.csi_params[index] = a.csi_params[index] * 10 + int(ch - `0`)
					a.csi_has_digits = true
				}
				return
			}
			if ch == `;` || ch == `:` {
				if a.csi_count < terminal_csi_parameter_limit {
					a.csi_count++
				}
				a.csi_has_digits = false
				return
			}
			if (ch == `?` || ch == `>` || ch == `!`) && a.csi_count == 1
				&& !a.csi_has_digits {
				a.csi_private = ch
				return
			}
			if ch >= 0x40 && ch <= 0x7e {
				a.apply_csi(ch)
				a.escape_state = 0
			}
		}
		3 {
			if ch == 0x07 {
				a.escape_state = 0
			} else if ch == 0x1b {
				a.escape_state = 4
			}
		}
		4 {
			a.escape_state = if ch == `\\` { u8(0) } else { u8(3) }
		}
		5 {
			a.escape_state = 0
		}
		6 {
			// The linux console's palette controls are OSC-shaped but have no
			// BEL/ST terminator: OSC R ends immediately and OSC P consumes one
			// palette index plus six hexadecimal colour digits.
			if ch == `R` {
				a.escape_state = 0
			} else if ch == `P` {
				a.escape_string_remaining = 7
				a.escape_state = 7
			} else if ch == 0x07 {
				a.escape_state = 0
			} else if ch == 0x1b {
				a.escape_state = 4
			} else {
				a.escape_state = 3
			}
		}
		7 {
			a.escape_string_remaining--
			if a.escape_string_remaining <= 0 {
				a.escape_state = 0
			}
		}
		else {
			a.escape_state = 0
		}
	}
}

fn (a &TerminalApp) csi_value(index int, default_value int) int {
	if index < 0 || index >= a.csi_count || index >= terminal_csi_parameter_limit
		|| a.csi_params[index] == 0 {
		return default_value
	}
	return a.csi_params[index]
}

fn (mut a TerminalApp) erase_display(mode int) {
	position := a.cursor_row * a.columns + a.cursor_column
	match mode {
		1 { a.clear_cells(0, position + 1) }
		2, 3 { a.clear_cells(0, a.screen.len) }
		else { a.clear_cells(position, a.screen.len) }
	}
}

fn (mut a TerminalApp) erase_line(mode int) {
	start := a.cursor_row * a.columns
	match mode {
		1 { a.clear_cells(start, start + a.cursor_column + 1) }
		2 { a.clear_cells(start, start + a.columns) }
		else { a.clear_cells(start + a.cursor_column, start + a.columns) }
	}
}

fn (mut a TerminalApp) insert_characters(count int) {
	amount := terminal_clamp(count, 1, a.columns - a.cursor_column)
	start := a.cursor_row * a.columns
	for column := a.columns - 1; column >= a.cursor_column + amount; column-- {
		a.screen[start + column] = a.screen[start + column - amount]
	}
	for column in a.cursor_column .. a.cursor_column + amount {
		a.screen[start + column] = ` `
	}
	a.mark_row_dirty(a.cursor_row)
}

fn (mut a TerminalApp) delete_characters(count int) {
	amount := terminal_clamp(count, 1, a.columns - a.cursor_column)
	start := a.cursor_row * a.columns
	for column in a.cursor_column .. a.columns - amount {
		a.screen[start + column] = a.screen[start + column + amount]
	}
	for column in a.columns - amount .. a.columns {
		a.screen[start + column] = ` `
	}
	a.mark_row_dirty(a.cursor_row)
}

fn (mut a TerminalApp) enter_alternate_screen() {
	if a.alternate_screen {
		return
	}
	a.main_screen = a.screen
	a.main_rows = a.rows
	a.main_columns = a.columns
	a.main_cursor_row = a.cursor_row
	a.main_cursor_column = a.cursor_column
	a.screen = terminal_blank_screen(a.rows, a.columns)
	a.alternate_screen = true
	a.cursor_row = 0
	a.cursor_column = 0
	a.scroll_top = 0
	a.scroll_bottom = a.rows
	a.wrap_pending = false
	a.scroll = 0
	a.reset_row_cache()
}

fn (mut a TerminalApp) leave_alternate_screen() {
	if !a.alternate_screen {
		return
	}
	old_alternate := a.screen
	a.screen = a.main_screen
	a.main_screen = []u8{}
	if old_alternate.cap > 0 {
		unsafe { old_alternate.free() }
	}
	a.alternate_screen = false
	a.cursor_row = terminal_clamp(a.main_cursor_row, 0, a.rows - 1)
	a.cursor_column = terminal_clamp(a.main_cursor_column, 0, a.columns - 1)
	a.scroll_top = 0
	a.scroll_bottom = a.rows
	a.wrap_pending = false
	a.reset_row_cache()
}

fn (mut a TerminalApp) set_private_mode(enabled bool) {
	for index in 0 .. a.csi_count {
		match a.csi_params[index] {
			7 {
				a.autowrap = enabled
			}
			25 {
				a.cursor_visible = enabled
				a.mark_row_dirty(a.cursor_row)
			}
			47, 1047, 1049 {
				if enabled {
					a.enter_alternate_screen()
				} else {
					a.leave_alternate_screen()
				}
			}
			else {}
		}
	}
}

fn (mut a TerminalApp) send_terminal_reply(reply string) {
	if a.terminal >= 0 && reply.len > 0 {
		desktop_write_all(a.terminal, reply.str, u64(reply.len))
	}
}

fn (mut a TerminalApp) apply_csi(command u8) {
	amount := a.csi_value(0, 1)
	match command {
		`A` { a.move_cursor(a.cursor_row - amount, a.cursor_column) }
		`B` { a.move_cursor(a.cursor_row + amount, a.cursor_column) }
		`C`, `a` { a.move_cursor(a.cursor_row, a.cursor_column + amount) }
		`D` { a.move_cursor(a.cursor_row, a.cursor_column - amount) }
		`E` { a.move_cursor(a.cursor_row + amount, 0) }
		`F` { a.move_cursor(a.cursor_row - amount, 0) }
		`G`, `\`` { a.move_cursor(a.cursor_row, a.csi_value(0, 1) - 1) }
		`H`, `f` { a.move_cursor(a.csi_value(0, 1) - 1, a.csi_value(1, 1) - 1) }
		`d` { a.move_cursor(a.csi_value(0, 1) - 1, a.cursor_column) }
		`J` { a.erase_display(a.csi_params[0]) }
		`K` { a.erase_line(a.csi_params[0]) }
		`@` { a.insert_characters(amount) }
		`P` { a.delete_characters(amount) }
		`X` {
			start := a.cursor_row * a.columns + a.cursor_column
			a.clear_cells(start, start + terminal_clamp(amount, 1, a.columns - a.cursor_column))
		}
		`L` {
			if a.cursor_row >= a.scroll_top && a.cursor_row < a.scroll_bottom {
				a.scroll_region_down(a.cursor_row, a.scroll_bottom, amount)
			}
		}
		`M` {
			if a.cursor_row >= a.scroll_top && a.cursor_row < a.scroll_bottom {
				a.scroll_region_up(a.cursor_row, a.scroll_bottom, amount)
			}
		}
		`S` { a.scroll_region_up(a.scroll_top, a.scroll_bottom, amount) }
		`T` { a.scroll_region_down(a.scroll_top, a.scroll_bottom, amount) }
		`b` {
			for _ in 0 .. amount {
				a.put_visible_byte(a.last_printed)
			}
		}
		`r` {
			top := terminal_clamp(a.csi_value(0, 1) - 1, 0, a.rows - 1)
			bottom := terminal_clamp(a.csi_value(1, a.rows), 1, a.rows)
			if top < bottom {
				a.scroll_top = top
				a.scroll_bottom = bottom
			}
			a.move_cursor(0, 0)
		}
		`s` {
			a.saved_cursor_row = a.cursor_row
			a.saved_cursor_column = a.cursor_column
		}
		`u` { a.move_cursor(a.saved_cursor_row, a.saved_cursor_column) }
		`h` {
			if a.csi_private == `?` {
				a.set_private_mode(true)
			} else if a.csi_params[0] == 4 {
				a.insert_mode = true
			}
		}
		`l` {
			if a.csi_private == `?` {
				a.set_private_mode(false)
			} else if a.csi_params[0] == 4 {
				a.insert_mode = false
			}
		}
		`n` {
			if a.csi_params[0] == 6 {
				a.send_terminal_reply('\x1b[${a.cursor_row + 1};${a.cursor_column + 1}R')
			}
		}
		`c` {
			// CSI ? 0/1/8 c selects the Linux console cursor shape. Only an
			// unprefixed CSI c is a device-attributes query that needs a reply.
			if a.csi_private == 0 {
				a.send_terminal_reply('\x1b[?6c')
			}
		}
		else {}
	}
}

fn (mut a TerminalApp) reset_active_screen() {
	a.clear_cells(0, a.screen.len)
	a.cursor_row = 0
	a.cursor_column = 0
	a.saved_cursor_row = 0
	a.saved_cursor_column = 0
	a.scroll_top = 0
	a.scroll_bottom = a.rows
	a.cursor_visible = true
	a.autowrap = true
	a.wrap_pending = false
	a.insert_mode = false
	a.mark_all_rows_dirty()
}

fn (mut a TerminalApp) rendered_row(row int) string {
	if row < 0 || row >= a.rows {
		return ''
	}
	if !a.dirty_rows[row] {
		return a.rendered_rows[row]
	}
	start := row * a.columns
	mut end := start + a.columns
	for end > start && a.screen[end - 1] == ` ` {
		end--
	}
	if a.cursor_visible && row == a.cursor_row {
		cursor_end := start + a.cursor_column + 1
		if cursor_end > end {
			end = cursor_end
		}
	}
	mut bytes := []u8{len: end - start}
	for index in 0 .. bytes.len {
		bytes[index] = a.screen[start + index]
	}
	if a.cursor_visible && row == a.cursor_row && a.cursor_column < bytes.len {
		bytes[a.cursor_column] = `_`
	}
	next := bytes.bytestr()
	if bytes.cap > 0 {
		unsafe { bytes.free() }
	}
	a.rendered_rows[row] = replaced_terminal_text(a.rendered_rows[row], next)
	a.dirty_rows[row] = false
	return a.rendered_rows[row]
}

fn replaced_terminal_text(old string, next string) string {
	if old.len > 0 {
		unsafe { old.free() }
	}
	return next
}

// Feed keystrokes directly to the PTY master. DEL is the slave's default
// VERASE, so normalize the desktop keyboard's Backspace byte to it.
fn (mut a TerminalApp) key_input(text string) {
	if a.terminal < 0 || a.exited || text.len == 0 {
		return
	}
	mut input := []u8{cap: text.len}
	for ch in text {
		input << if ch == 8 { u8(0x7f) } else { ch }
	}
	desktop_write_all(a.terminal, input.data, u64(input.len))
	unsafe { input.free() }
}

fn (mut a TerminalApp) close_app() {
	if a.terminal >= 0 {
		desktop_close(a.terminal)
		a.terminal = -1
	}
	if a.pid >= 0 && !a.exited {
		desktop_terminate_child(a.pid)
	}
	a.pid = -1
	a.exited = true
}

fn (mut a TerminalApp) build(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)
	a.visible_rows = if height > 2 * terminal_padding + terminal_row_height {
		(height - 2 * terminal_padding) / terminal_row_height
	} else {
		1
	}
	columns := if width > 2 * terminal_padding + terminal_column_width {
		(width - 2 * terminal_padding) / terminal_column_width
	} else {
		1
	}
	a.set_geometry(a.visible_rows, columns)
	if !a.started && !a.exited {
		a.start_shell(a.visible_rows, columns, width, height)
	}
	if a.terminal >= 0
		&& (a.visible_rows != a.terminal_rows || columns != a.terminal_columns) {
		if desktop_terminal_winsize(a.terminal, a.visible_rows, columns, width, height) {
			a.terminal_rows = a.visible_rows
			a.terminal_columns = columns
		}
	}

	max_scroll := if !a.alternate_screen { a.lines.len } else { 0 }
	if a.scroll > max_scroll {
		a.scroll = max_scroll
	}
	if a.scroll < 0 {
		a.scroll = 0
	}
	first := a.lines.len - a.scroll

	mut children := frame_elements(a.visible_rows + 2)
	for row in 0 .. a.visible_rows {
		index := first + row
		text := if !a.alternate_screen && index < a.lines.len {
			a.lines[index]
		} else {
			screen_row := if a.alternate_screen { row } else { index - a.lines.len }
			a.rendered_row(screen_row)
		}
		if text.len == 0 {
			continue
		}
		children << ui2.label('', text, ui2.rect(f64(terminal_padding), f64(terminal_padding + row * terminal_row_height), f64(width - 2 * terminal_padding), f64(terminal_row_height)), ui2.TextStyle{
			color: terminal_text
			font_family: 'mono'
			size: 13
		})
	}

	if max_scroll > 0 {
		button := 18
		right := width - terminal_padding - button
		children << ui2.button(terminal_action_scroll_up, '-', ui2.rect(f64(right - button - 4), f64(terminal_padding), f64(button), 18), ui2.BoxStyle{
			bg: terminal_button
			radius: 4
		}, ui2.TextStyle{
			color: terminal_text
			size: 12
			align: .center
		})
		children << ui2.button(terminal_action_scroll_down, '+', ui2.rect(f64(right), f64(terminal_padding), f64(button), 18), ui2.BoxStyle{
			bg: terminal_button
			radius: 4
		}, ui2.TextStyle{
			color: terminal_text
			size: 12
			align: .center
		})
	}

	return ui2.screen(terminal_bg, children)
}

fn (mut a TerminalApp) handle(event_id string) ! {
	match event_id {
		terminal_action_scroll_up {
			a.scroll += a.visible_rows
		}
		terminal_action_scroll_down {
			a.scroll -= a.visible_rows
		}
		else {}
	}
}
