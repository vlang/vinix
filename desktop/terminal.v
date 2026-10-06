// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
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

// PollPacedApp is a PollingApp that knows when its next poll can find
// something new, and returns that in each poll reply. The compositor then
// waits that long rather than its fixed cadence: a clock showing seconds has
// nothing new for most of a second, and a quiet shell for longer still.
interface PollPacedApp {
	next_poll_ms() u64
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
	back
}

interface PointerApp {
mut:
	pointer_input_enabled() bool
	pointer_event(phase AppPointerPhase, button AppPointerButton, scroll int, x int, y int, width int, height int)
}

// PointerMoveApp is a PointerApp that can tell whether moving the pointer
// can change it now. The answer travels back in the pointer reply, so a
// window whose application ignores a move is neither rebuilt nor repainted
// for it. An application without this is assumed to change on every event.
interface PointerMoveApp {
	pointer_moves_matter() bool
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
// Malformed UTF-8 takes one cell per rejected byte or cut-short sequence.
const terminal_replacement_char = rune(0xfffd)

const terminal_action_scroll_up = 'term.scroll.up'
const terminal_action_scroll_down = 'term.scroll.down'

const terminal_row_height = 16
const terminal_column_width = 8
const terminal_padding = 8
const terminal_rebuild_notice_path = '/run/vinix-desktop-rebuild'
const terminal_rebuild_snapshot_path = '/run/vinix-desktop-rebuild-terminal'
const terminal_rebuild_notice_max_age_ms = u64(600_000)
const terminal_rebuild_snapshot_max_bytes = u64(1024 * 1024)

const terminal_active_poll_ms = u64(100)
const terminal_quiet_poll_ms = u64(250)
const terminal_idle_poll_ms = u64(500)

struct TerminalApp {
mut:
	// When the shell last printed anything; see next_poll_ms.
	last_output_ms u64
	// The visible terminal is a fixed grid of code points, one per cell. Keeping
	// it flat makes scrolling and erasing deterministic and avoids one
	// allocation per cell.
	screen          []rune
	rendered_rows   []string
	dirty_rows      []bool
	rows            int
	columns         int
	cursor_row      int
	cursor_column   int
	cursor_visible  bool = true
	autowrap        bool = true
	wrap_pending    bool
	insert_mode     bool
	bracketed_paste bool
	last_printed    rune = ` `

	scroll_top          int
	scroll_bottom       int
	saved_cursor_row    int
	saved_cursor_column int

	// Vim uses the alternate screen. Preserve the shell's main screen so leaving
	// Vim reveals the command that launched it and its prompt again.
	alternate_screen   bool
	main_screen        []rune
	main_rows          int
	main_columns       int
	main_cursor_row    int
	main_cursor_column int

	// Completed rows pushed off the top of the main screen.
	lines  []string
	scroll int
	search_query []u8
	search_open bool
	search_match int = -1
	search_pending [4]u8
	search_pending_len int
	search_escape_state int
	selection_anchor TerminalSelectionPoint
	selection_head TerminalSelectionPoint
	selection_dragging bool
	selection_block bool
	selection_unit TerminalSelectionUnit
	selection_origin_start TerminalSelectionPoint
	selection_origin_end TerminalSelectionPoint
	selection_click TerminalSelectionClick
	view_width int
	view_height int
	copy_client TextCopyClient
	copy_key_pending [8]u8
	copy_key_len int
	copy_key_ms u64

	// Escape parser state survives non-blocking reads. CSI parameters use a
	// fixed array so a noisy child cannot allocate without bound.
	escape_state            u8
	escape_string_remaining int
	csi_params              [terminal_csi_parameter_limit]int
	csi_count               int
	csi_private             u8
	csi_has_digits          bool
	// The start of an OSC string, enough to recognise the taskbar progress
	// sequence OSC 9;4. Anything longer is skipped, as before.
	osc_bytes [terminal_osc_limit]u8
	osc_len   int
	// Taskbar state published for this window: progress from OSC 9;4 and a
	// new attention serial for each bell.
	taskbar TaskStatus

	// Text outside escape sequences is UTF-8, and a sequence may straddle two
	// reads. The bounds limit the next byte so overlong forms, surrogates and
	// code points past U+10FFFF are rejected as they arrive.
	utf8_code   u32
	utf8_needed int
	utf8_lower  u8 = 0x80
	utf8_upper  u8 = 0xbf

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

const terminal_osc_limit = 32

fn open_terminal(mut _ Desktop) !NativeApp {
	return &TerminalApp{
		read_buf: []u8{len: terminal_read_chunk}
	}
}

// The shell that ran vinix-desktop-build exits with the old session. Its
// replacement Terminal consumes the result after the new compositor is ready.
struct TerminalRebuildRecord {
	started_ms u64
	shell_pid  int = -1
}

fn terminal_rebuild_uptime_ms(value string) ?u64 {
	parts := value.split('.')
	if parts.len != 2 || parts[0].len == 0 || parts[0].len > 10 || parts[1].len != 2 {
		return none
	}
	for ch in value {
		if ch != `.` && (ch < `0` || ch > `9`) {
			return none
		}
	}
	return parts[0].u64() * 1000 + parts[1].u64() * 10
}

fn terminal_rebuild_record(record string, compositor_pid int, now_ms u64) ?TerminalRebuildRecord {
	fields := record.trim_space().split(' ')
	if (fields.len != 2 && fields.len != 3) || fields[0].int() != compositor_pid
		|| compositor_pid <= 0
		|| now_ms == ~u64(0) {
		return none
	}
	started_ms := terminal_rebuild_uptime_ms(fields[1]) or { return none }
	if started_ms > now_ms || now_ms - started_ms > terminal_rebuild_notice_max_age_ms {
		return none
	}
	shell_pid := if fields.len == 3 { fields[2].int() } else { -1 }
	if fields.len == 3 && shell_pid <= 0 {
		return none
	}
	return TerminalRebuildRecord{
		started_ms: started_ms
		shell_pid:  shell_pid
	}
}

fn terminal_rebuild_result(record TerminalRebuildRecord, now_ms u64) string {
	return 'vinix-desktop has been rebuilt in ${f64(now_ms - record.started_ms) / 1000.0:.2f} seconds\r\n'
}

fn terminal_rebuild_message(value string, compositor_pid int, now_ms u64) string {
	record := terminal_rebuild_record(value, compositor_pid, now_ms) or { return '' }
	return terminal_rebuild_result(record, now_ms)
}

fn terminal_take_rebuild_snapshot() string {
	info := desktop_stat(terminal_rebuild_snapshot_path) or { return '' }
	defer {
		desktop_unlink(terminal_rebuild_snapshot_path)
	}
	if info.is_dir || info.size == 0 || info.size > terminal_rebuild_snapshot_max_bytes {
		return ''
	}
	mut data := []u8{len: int(info.size)}
	got := desktop_read_file(terminal_rebuild_snapshot_path, data.data, info.size)
	if got != i64(info.size) {
		unsafe { data.free() }
		return ''
	}
	return data.bytestr()
}

fn terminal_take_rebuild_message() string {
	if !desktop_is_development_session()
		|| C.access(c'/run/vinix-desktop-ready', 0) != 0 {
		return ''
	}
	mut data := []u8{len: 64}
	got := desktop_read_file(terminal_rebuild_notice_path, data.data, u64(data.len))
	if got < 0 {
		return ''
	}
	desktop_unlink(terminal_rebuild_notice_path)
	if got == 0 || got >= data.len {
		return ''
	}
	now_ms := desktop_monotonic_ms()
	record := terminal_rebuild_record(data[..int(got)].bytestr(), C.getppid(), now_ms) or {
		return ''
	}
	snapshot := terminal_take_rebuild_snapshot()
	result := terminal_rebuild_result(record, now_ms)
	return snapshot + result
}

fn terminal_append_snapshot_line(mut output []u8, line string) bool {
	if u64(output.len + line.len + 2) > terminal_rebuild_snapshot_max_bytes {
		return false
	}
	for ch in line {
		output << ch
	}
	output << `\r`
	output << `\n`
	return true
}

// Flatten the visible main screen and scrollback into ordinary terminal text.
// The replacement gets a new PTY, so control state cannot safely be retained;
// the displayed rows are the durable part users need after a self-hosted build.
fn (a &TerminalApp) rebuild_snapshot() string {
	if a.alternate_screen || a.rows <= 0 || a.columns <= 0 || a.screen.len == 0 {
		return ''
	}
	mut output := []u8{cap: 16 * 1024}
	for line in a.lines {
		if !terminal_append_snapshot_line(mut output, line) {
			unsafe { output.free() }
			return ''
		}
	}
	mut last_row := -1
	for row in 0 .. a.rows {
		start := row * a.columns
		for column in 0 .. a.columns {
			if a.screen[start + column] != ` ` {
				last_row = row
				break
			}
		}
	}
	for row in 0 .. last_row + 1 {
		line := a.row_string(row)
		if !terminal_append_snapshot_line(mut output, line) {
			unsafe { line.free() }
			unsafe { output.free() }
			return ''
		}
		if line.len > 0 {
			unsafe { line.free() }
		}
	}
	return output.bytestr()
}

fn (mut a TerminalApp) preserve_rebuild_snapshot() {
	if a.pid <= 0 {
		return
	}
	mut data := []u8{len: 96}
	got := desktop_read_file(terminal_rebuild_notice_path, data.data, u64(data.len))
	if got <= 0 || got >= data.len {
		return
	}
	record := terminal_rebuild_record(data[..int(got)].bytestr(), C.getppid(),
		desktop_monotonic_ms()) or { return }
	if record.shell_pid != a.pid {
		return
	}
	// The reload signal can reach the compositor before its next regular app
	// poll. Drain the final helper line before taking the screen snapshot.
	a.poll()
	snapshot := a.rebuild_snapshot()
	if snapshot.len > 0 {
		desktop_write_file(terminal_rebuild_snapshot_path, snapshot.str, u64(snapshot.len))
		unsafe { snapshot.free() }
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

fn terminal_blank_screen(rows int, columns int) []rune {
	return []rune{len: rows * columns, init: ` `}
}

fn terminal_resize_cells(cells []rune, old_rows int, old_columns int, rows int, columns int) []rune {
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

// Freeing an array of strings already releases every string it holds. Never
// release the rows here as well: the extra free hands the same pointers to
// the allocator twice, and musl aborts the process when it notices. The row
// cache is rebuilt whenever the grid changes size, so that abort killed the
// terminal the moment its window was maximised or resized.
fn (mut a TerminalApp) release_rendered_rows() {
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
	a.clear_selection()

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
	a.clear_selection()
	if row >= 0 && row < a.dirty_rows.len {
		a.dirty_rows[row] = true
	}
}

fn (mut a TerminalApp) mark_all_rows_dirty() {
	a.clear_selection()
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
	return terminal_cells_text(a.screen, start, end, -1)
}

// Cells only ever hold valid scalar values, so encoding has no error case.
fn terminal_utf8_len(ch rune) int {
	code := u32(ch)
	return if code < 0x80 {
		1
	} else if code < 0x800 {
		2
	} else if code < 0x10000 {
		3
	} else {
		4
	}
}

fn terminal_append_utf8(mut output []u8, ch rune) {
	code := u32(ch)
	if code < 0x80 {
		output << u8(code)
	} else if code < 0x800 {
		output << u8(0xc0 | (code >> 6))
		output << u8(0x80 | (code & 0x3f))
	} else if code < 0x10000 {
		output << u8(0xe0 | (code >> 12))
		output << u8(0x80 | ((code >> 6) & 0x3f))
		output << u8(0x80 | (code & 0x3f))
	} else {
		output << u8(0xf0 | (code >> 18))
		output << u8(0x80 | ((code >> 12) & 0x3f))
		output << u8(0x80 | ((code >> 6) & 0x3f))
		output << u8(0x80 | (code & 0x3f))
	}
}

// terminal_cells_text encodes cells[start..end] as the UTF-8 a label draws.
// The cell at index `cursor`, if any, is drawn as the cursor instead.
fn terminal_cells_text(cells []rune, start int, end int, cursor int) string {
	mut size := 0
	for index in start .. end {
		size += if index == cursor { 1 } else { terminal_utf8_len(cells[index]) }
	}
	// Empty rows are common during search and rendering. bytestr() allocates
	// even for an empty array, while row consumers treat '' as borrowed text.
	if size == 0 { return '' }
	mut bytes := []u8{cap: size}
	for index in start .. end {
		terminal_append_utf8(mut bytes, if index == cursor { `_` } else { cells[index] })
	}
	next := bytes.bytestr()
	if bytes.cap > 0 {
		unsafe { bytes.free() }
	}
	return next
}

fn (mut a TerminalApp) push_history_row(row int) {
	a.clear_selection()
	unsafe { a.lines.flags |= .noslices }
	a.lines << a.row_string(row)
	for a.lines.len > terminal_scrollback {
		evicted := a.lines[0]
		a.lines.delete(0)
		if a.search_match >= 0 { a.search_match-- }
		if evicted.len > 0 {
			unsafe { evicted.free() }
		}
	}
	if a.search_open && a.scroll > 0 {
		a.scroll++
		if a.scroll > a.lines.len { a.scroll = a.lines.len }
	} else {
		a.scroll = 0
	}
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

// Every code point takes one cell; wide and combining characters are not
// distinguished yet.
fn (mut a TerminalApp) put_visible_char(ch rune) {
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
	// The first Terminal after setup installs the apps chosen there, then
	// hands the same PTY to the ordinary interactive shell.
	command := desktop_take_first_run_install()
	defer {
		if command.len > 0 {
			unsafe { command.free() }
		}
	}
	shell := desktop_spawn_shell(terminal_shell, command, rows, columns, width, height) or {
		a.error = tr_fill('terminal.cannot_start', terminal_shell)
		a.ingest_output(a.error.bytes())
		a.exited = true
		return
	}
	a.pid = shell.pid
	a.terminal = shell.terminal
	a.terminal_rows = rows
	a.terminal_columns = columns
	message := terminal_take_rebuild_message()
	if message.len > 0 {
		a.ingest_output(message.bytes())
	}
}

fn (mut a TerminalApp) poll() bool {
	mut changed := a.expire_copy_key(desktop_monotonic_ms())
	if a.terminal < 0 {
		return changed
	}

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
	if changed {
		a.last_output_ms = desktop_monotonic_ms()
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

// A shell that has just printed is polled at the Terminal's full cadence, so
// a command's output streams. One that has been quiet for a while is only
// waiting for its user, whose typing polls it at once; background output
// then shows within a quarter or half of a second instead of a tenth.
fn (a &TerminalApp) next_poll_ms() u64 {
	if a.copy_key_len > 0 { return terminal_active_poll_ms }
	now := desktop_monotonic_ms()
	if a.terminal < 0 {
		return 0
	}
	if now == ~u64(0) || now < a.last_output_ms || now - a.last_output_ms < 1000 {
		return terminal_active_poll_ms
	}
	if now - a.last_output_ms < 10_000 {
		return terminal_quiet_poll_ms
	}
	return terminal_idle_poll_ms
}

fn (mut a TerminalApp) ingest_output(output []u8) {
	a.ensure_screen()
	for ch in output {
		if a.escape_state != 0 {
			a.ingest_escape_byte(ch)
			continue
		}
		if a.utf8_needed > 0 {
			if a.continue_utf8(ch) {
				continue
			}
			// A sequence cut short is replaced as a whole, and the byte that
			// interrupted it is read afresh rather than swallowed.
			a.put_visible_char(terminal_replacement_char)
		}
		if ch == 0x1b {
			a.escape_state = 1
			continue
		}
		if ch >= 0x80 {
			a.begin_utf8(ch)
			continue
		}
		a.ingest_terminal_byte(ch)
	}
}

// begin_utf8 starts a sequence at its lead byte. E0, ED, F0 and F4 narrow the
// range of the next byte; that is what rules out overlong forms, surrogates
// and code points past U+10FFFF. A byte that cannot lead is replaced alone.
fn (mut a TerminalApp) begin_utf8(ch u8) {
	a.utf8_lower = 0x80
	a.utf8_upper = 0xbf
	if ch >= 0xc2 && ch <= 0xdf {
		a.utf8_code = u32(ch & 0x1f)
		a.utf8_needed = 1
	} else if ch >= 0xe0 && ch <= 0xef {
		if ch == 0xe0 {
			a.utf8_lower = 0xa0
		} else if ch == 0xed {
			a.utf8_upper = 0x9f
		}
		a.utf8_code = u32(ch & 0x0f)
		a.utf8_needed = 2
	} else if ch >= 0xf0 && ch <= 0xf4 {
		if ch == 0xf0 {
			a.utf8_lower = 0x90
		} else if ch == 0xf4 {
			a.utf8_upper = 0x8f
		}
		a.utf8_code = u32(ch & 0x07)
		a.utf8_needed = 3
	} else {
		a.put_visible_char(terminal_replacement_char)
	}
}

// continue_utf8 reports whether ch belongs to the pending sequence, and prints
// the code point once the sequence is complete. C1 controls have no glyph and
// are dropped, like DEL.
fn (mut a TerminalApp) continue_utf8(ch u8) bool {
	if ch < a.utf8_lower || ch > a.utf8_upper {
		a.utf8_needed = 0
		return false
	}
	a.utf8_lower = 0x80
	a.utf8_upper = 0xbf
	a.utf8_code = (a.utf8_code << 6) | u32(ch & 0x3f)
	a.utf8_needed--
	if a.utf8_needed == 0 && a.utf8_code >= 0xa0 {
		a.put_visible_char(rune(a.utf8_code))
	}
	return true
}

fn (mut a TerminalApp) ingest_terminal_byte(ch u8) {
	match ch {
		0 {}
		0x07 {
			// A bell asks for attention. The taskbar flags the button until
			// the window is next brought up, and not at all if it is focused.
			a.taskbar.attention_serial++
			publish_taskbar_status(a.taskbar)
		}
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
				a.put_visible_char(rune(ch))
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
				a.osc_bytes[0] = ch
				a.osc_len = 1
				a.escape_state = 8
			}
		}
		8 {
			// Collecting a short OSC string until BEL or ST ends it.
			if ch == 0x07 {
				a.finish_osc()
				a.escape_state = 0
			} else if ch == 0x1b {
				a.escape_state = 9
			} else if a.osc_len < terminal_osc_limit {
				a.osc_bytes[a.osc_len] = ch
				a.osc_len++
			} else {
				a.escape_state = 3
			}
		}
		9 {
			if ch == `\\` {
				a.finish_osc()
				a.escape_state = 0
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

// finish_osc acts on OSC 9;4;<state>;<percent>, the progress report that
// Windows Terminal and ConEmu put on the taskbar: 0 clears it, 1 is ordinary
// progress, 2 an error, 3 indeterminate and 4 paused. An error or pause with
// no percentage keeps the last one. Every other OSC is ignored, as before.
fn (mut a TerminalApp) finish_osc() {
	if a.osc_len < 3 || a.osc_bytes[0] != `9` || a.osc_bytes[1] != `;` || a.osc_bytes[2] != `4` {
		return
	}
	mut values := [2]int{}
	mut present := [2]bool{}
	mut field := -1
	for index in 3 .. a.osc_len {
		ch := a.osc_bytes[index]
		if ch == `;` {
			field++
			continue
		}
		if field < 0 || field > 1 || ch < `0` || ch > `9` {
			continue
		}
		if values[field] < 1000 {
			values[field] = values[field] * 10 + int(ch - `0`)
		}
		present[field] = true
	}
	state := match values[0] {
		1 { TaskProgress.normal }
		2 { TaskProgress.error }
		3 { TaskProgress.indeterminate }
		4 { TaskProgress.paused }
		else { TaskProgress.none_ }
	}
	a.taskbar.progress_state = state
	if present[1] || state == .normal || state == .none_ {
		a.taskbar.progress = if values[1] > 100 { 100 } else { values[1] }
	}
	publish_taskbar_status(a.taskbar)
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
	a.clear_selection()
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
	a.clear_selection()
	old_alternate := a.screen
	a.screen = a.main_screen
	a.main_screen = []rune{}
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
			2004 { a.bracketed_paste = enabled }
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
				a.put_visible_char(a.last_printed)
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
	a.bracketed_paste = false
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
	cursor := if a.cursor_visible && row == a.cursor_row { start + a.cursor_column } else { -1 }
	next := terminal_cells_text(a.screen, start, end, cursor)
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
	if a.search_open { a.search_input(text); return }
	a.selection_key_input(text)
}

fn (mut a TerminalApp) paste_input(text string) {
	if a.search_open { a.paste_search(text); return }
	// Paste is literal shell input. A pending shortcut fragment precedes it;
	// pasted CSI-u text is never interpreted as Copy.
	a.flush_copy_key()
	if a.terminal < 0 || a.exited || text.len == 0 {
		return
	}
	if a.bracketed_paste {
		desktop_write_all(a.terminal, c'\x1b[200~', 6)
	}
	desktop_write_all(a.terminal, text.str, u64(text.len))
	if a.bracketed_paste {
		desktop_write_all(a.terminal, c'\x1b[201~', 6)
	}
}

fn (mut a TerminalApp) close_app() {
	a.preserve_rebuild_snapshot()
	a.copy_client.close()
	a.clear_selection()
	a.copy_key_len = 0
	if a.search_query.cap > 0 { unsafe { a.search_query.free() } }
	a.search_query = []u8{}
	a.search_pending_len = 0
	a.search_escape_state = 0
	if a.terminal >= 0 {
		desktop_close(a.terminal)
		a.terminal = -1
	}
	if a.pid >= 0 && !a.exited {
		_ = desktop_terminate_child(a.pid)
	}
	a.pid = -1
	a.exited = true
	a.release_rendered_rows()
	if a.screen.cap > 0 { unsafe { a.screen.free() } }
	if a.main_screen.cap > 0 { unsafe { a.main_screen.free() } }
	if a.lines.cap > 0 { unsafe { a.lines.free() } }
	if a.read_buf.cap > 0 { unsafe { a.read_buf.free() } }
	if a.error.len > 0 { unsafe { a.error.free() } }
	a.screen = []rune{}
	a.main_screen = []rune{}
	a.lines = []string{}
	a.read_buf = []u8{}
	a.error = ''
}

fn (mut a TerminalApp) build(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)
	if a.view_width != width || a.view_height != height { a.clear_selection() }
	a.view_width = width
	a.view_height = height
	a.visible_rows = if height > terminal_toolbar_height + terminal_selection_status_height + 2 * terminal_padding + terminal_row_height {
		(height - terminal_toolbar_height - terminal_selection_status_height - 2 * terminal_padding) / terminal_row_height
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

	mut children := frame_elements(a.visible_rows * 2 + 10)
	a.build_search_toolbar(mut children, width)
	for row in 0 .. a.visible_rows {
		index := first + row
		text := if !a.alternate_screen && index < a.lines.len {
			a.lines[index]
		} else {
			screen_row := if a.alternate_screen { row } else { index - a.lines.len }
			a.rendered_row(screen_row)
		}
		row_y := terminal_toolbar_height + terminal_padding + row * terminal_row_height
		if a.search_open && a.search_match == (if a.alternate_screen { row } else { index }) {
			children << ui2.view('', ui2.rect(f64(terminal_padding), f64(row_y), f64(width - 2 * terminal_padding), f64(terminal_row_height)),
				ui2.BoxStyle{ bg: terminal_button }, [])
		}
		a.build_selection_highlight(mut children, if a.alternate_screen { row } else { index }, row_y, width)
		if text.len == 0 { continue }
		children << ui2.label('', text, ui2.rect(f64(terminal_padding), f64(row_y), f64(width - 2 * terminal_padding), f64(terminal_row_height)), ui2.TextStyle{
			color:       terminal_text
			font_family: 'mono'
			size:        13
		})
	}

	if max_scroll > 0 {
		button := 18
		right := width - terminal_padding - button
		children << ui2.button(terminal_action_scroll_up, '-', ui2.rect(f64(right - button - 4), f64(terminal_toolbar_height + terminal_padding), f64(button), 18), ui2.BoxStyle{
			bg:     terminal_button
			radius: 4
		}, ui2.TextStyle{
			color: terminal_text
			size:  12
			align: .center
		})
		children << ui2.button(terminal_action_scroll_down, '+', ui2.rect(f64(right), f64(terminal_toolbar_height + terminal_padding), f64(button), 18), ui2.BoxStyle{
			bg:     terminal_button
			radius: 4
		}, ui2.TextStyle{
			color: terminal_text
			size:  12
			align: .center
		})
	}
	a.build_selection_status(mut children, width, height)

	return ui2.screen(terminal_bg, children)
}

fn (mut a TerminalApp) handle(event_id string) ! {
	if event_id == terminal_action_copy { a.copy_selection(); return }
	if event_id == terminal_action_selection_mode { a.toggle_selection_mode(); return }
	if a.handle_search(event_id) { return }
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
