// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// A terminal, built into the desktop.
//
// It runs the shell on a Unix98 pseudo-terminal. The kernel line discipline
// owns echo, canonical editing and terminal-generated signals; this process is
// only the display and keyboard side of the PTY master.
//
// Like the file browser it satisfies NativeApp, so its process speaks the same
// compositor protocol. It additionally satisfies KeyboardApp, which is how
// keystrokes reach it.
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
// one of them each frame whether anything changed, which is what makes a
// command's output appear instead of waiting for a redraw someone else
// provokes.
interface PollingApp {
mut:
	poll() bool
}

enum AppPointerPhase {
	move
	down
	up
}

// PointerApp is used by pixel surfaces such as an embedded X server. Ordinary
// ui2 applications receive semantic action ids; a foreign toolkit needs the
// pointer position and button edges that produced those actions.
interface PointerApp {
mut:
	pointer_input_enabled() bool
	pointer_event(phase AppPointerPhase, x int, y int, width int, height int)
}

// ClosingApp releases subprocesses an application owns before its own process
// leaves. Ordinary app resources are closed by exit; Terminal also owns a
// shell process, which must not be orphaned when its window closes.
interface ClosingApp {
mut:
	close_app()
}

const terminal_shell = '/bin/busybox'
const terminal_shell_arg = 'sh'

// How much output is kept. A terminal that remembered everything would grow
// without bound on a system with no garbage collector.
const terminal_scrollback = 400

// Read this much of the shell's output at a time. poll() drains several chunks
// but caps the work per frame so a noisy command cannot hold the compositor.
const terminal_read_chunk = 4096
const terminal_reads_per_frame = 8

const terminal_action_scroll_up = 'term.scroll.up'
const terminal_action_scroll_down = 'term.scroll.down'

const terminal_row_height = 16
const terminal_column_width = 8
const terminal_padding = 8

struct TerminalApp {
mut:
	// Finished lines, oldest first.
	lines []string
	// The current terminal row is held as bytes. Reusing it avoids allocating
	// once per incoming character on this no-GC target.
	partial []u8
	cursor  int
	// Escape-sequence parser state is retained across non-blocking reads.
	escape_state       u8
	csi_value          int
	csi_has_value      bool
	csi_parameter_done bool
	saved_cursor       int
	// Reused across reads, for the same reason.
	read_buf []u8
	// The current row as rendered, rebuilt only when output changes.
	partial_text string = '_'

	pid      int = -1
	terminal int = -1
	started  bool
	exited   bool
	error    string

	// Last geometry sent through TIOCSWINSZ. Zero forces the first build to
	// publish the actual window size to the shell.
	terminal_rows    int
	terminal_columns int

	// Rows from the bottom the view is scrolled back by. Zero follows output.
	scroll       int
	visible_rows int = 1
}

fn open_terminal(mut _ Desktop) !NativeApp {
	mut app := &TerminalApp{
		read_buf: []u8{len: terminal_read_chunk}
	}
	app.lines << 'Vinix terminal — ${terminal_shell} ${terminal_shell_arg}'
	app.lines << ''
	return app
}

fn (mut a TerminalApp) start_shell(rows int, columns int, width int, height int) {
	a.started = true
	shell := desktop_spawn_shell(terminal_shell, terminal_shell_arg, rows, columns, width, height) or {
		a.error = 'cannot start ${terminal_shell}'
		a.push_line(a.error)
		a.exited = true
		a.refresh_partial()
		return
	}
	a.pid = shell.pid
	a.terminal = shell.terminal
	a.terminal_rows = rows
	a.terminal_columns = columns
}

// poll drains output waiting on the non-blocking PTY master and folds it into
// scrollback. Prompts and input echo are ordinary slave output now, so there
// is no separate readiness or prompt protocol to synchronize.
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
		a.exited = true
		if a.partial.len != 0 {
			a.push_line(a.partial.bytestr())
			a.partial.clear()
			a.cursor = 0
		}
		a.push_line('[${terminal_shell} exited]')
		desktop_close(a.terminal)
		a.terminal = -1
		a.pid = -1
		a.refresh_partial()
		changed = true
	}
	return changed
}

// Output-side terminal emulation. The shell is deliberately told TERM=dumb,
// so line feed, carriage return, tab and backspace are the cursor operations
// required for its prompt, line editor and ordinary command output.
fn (mut a TerminalApp) ingest_output(output []u8) {
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
	a.refresh_partial()
}

fn (mut a TerminalApp) ingest_terminal_byte(ch u8) {
	match ch {
		`\n` {
			a.push_line(a.partial.bytestr())
			a.partial.clear()
			a.cursor = 0
		}
		`\r` {
			a.cursor = 0
		}
		`\t` {
			next_tab := (a.cursor + 8) & ~7
			for a.cursor < next_tab {
				a.put_visible_byte(` `)
			}
		}
		8 {
			if a.cursor > 0 {
				a.cursor--
			}
		}
		else {
			if ch >= 0x20 && ch != 0x7f {
				a.put_visible_byte(ch)
			}
		}
	}
}

// Consume the small ANSI surface that interactive line editors use even with
// TERM=dumb. Unknown CSI and OSC sequences remain invisible rather than
// leaking their payload into the terminal as literal "[J"-style text.
fn (mut a TerminalApp) ingest_escape_byte(ch u8) {
	match a.escape_state {
		1 {
			match ch {
				`[` {
					a.escape_state = 2
					a.csi_value = 0
					a.csi_has_value = false
					a.csi_parameter_done = false
				}
				`]` {
					a.escape_state = 3
				}
				`7` {
					a.saved_cursor = a.cursor
					a.escape_state = 0
				}
				`8` {
					a.cursor = a.saved_cursor
					a.escape_state = 0
				}
				else {
					a.escape_state = 0
				}
			}
		}
		2 {
			if ch >= `0` && ch <= `9` {
				if !a.csi_parameter_done {
					a.csi_value = a.csi_value * 10 + int(ch - `0`)
					a.csi_has_value = true
				}
				return
			}
			if ch == `;` {
				a.csi_parameter_done = true
				return
			}
			// Private-mode prefixes are part of the sequence, not display text.
			if ch == `?` || ch == `>` {
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
		else {
			a.escape_state = 0
		}
	}
}

fn (mut a TerminalApp) apply_csi(command u8) {
	amount := if a.csi_has_value && a.csi_value > 0 { a.csi_value } else { 1 }
	match command {
		`C` {
			a.cursor += amount
		}
		`D` {
			a.cursor = if amount < a.cursor { a.cursor - amount } else { 0 }
		}
		`G` {
			a.cursor = amount - 1
		}
		`s` {
			a.saved_cursor = a.cursor
		}
		`u` {
			a.cursor = a.saved_cursor
		}
		`J`, `K` {
			mode := if a.csi_has_value { a.csi_value } else { 0 }
			if mode == 2 {
				a.partial.clear()
				a.cursor = 0
			} else if mode == 0 {
				for a.partial.len > a.cursor {
					a.partial.delete_last()
				}
			}
		}
		else {}
	}
}

fn (mut a TerminalApp) put_visible_byte(ch u8) {
	if a.cursor < a.partial.len {
		a.partial[a.cursor] = ch
	} else {
		for a.partial.len < a.cursor {
			a.partial << ` `
		}
		a.partial << ch
	}
	a.cursor++
}

fn (mut a TerminalApp) refresh_partial() {
	if !a.exited {
		// Appending the cursor only for bytestr() avoids a second temporary
		// allocation from string concatenation.
		a.partial << `_`
		a.partial_text = replaced(a.partial_text, a.partial.bytestr())
		a.partial.delete_last()
		return
	}
	a.partial_text = replaced(a.partial_text, a.partial.bytestr())
}

fn (mut a TerminalApp) push_line(line string) {
	a.lines << line
	// Evicted lines are freed rather than dropped. With no garbage collector a
	// terminal left running leaks one string per line of output otherwise.
	for a.lines.len > terminal_scrollback {
		evicted := a.lines[0]
		a.lines.delete(0)
		if evicted.len > 0 {
			unsafe { evicted.free() }
		}
	}
	// New output pulls the view back to the bottom, as a terminal does.
	a.scroll = 0
}

// replaced releases the string being replaced and hands back the new one. V
// will not take a `mut string`, so the caller assigns what comes out.
fn replaced(old string, next string) string {
	if old.len > 0 {
		unsafe { old.free() }
	}
	return next
}

// Feed keystrokes directly to the PTY master. DEL is the slave's default
// VERASE, so normalize the desktop keyboard's Backspace byte to it. Echo,
// command submission and control-character signals all happen in the kernel.
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

	// The output followed by the current row. Count rather than gather into a
	// new array: copying the scrollback every frame would allocate continuously.
	partial_rows := if !a.exited || a.partial.len > 0 { 1 } else { 0 }
	total := a.lines.len + partial_rows

	max_scroll := if total > a.visible_rows { total - a.visible_rows } else { 0 }
	if a.scroll > max_scroll {
		a.scroll = max_scroll
	}
	if a.scroll < 0 {
		a.scroll = 0
	}
	first := max_scroll - a.scroll

	mut children := frame_elements(a.visible_rows + 2)
	for row := 0; row < a.visible_rows; row++ {
		index := first + row
		if index < 0 || index >= total {
			continue
		}
		text := if index < a.lines.len { a.lines[index] } else { a.partial_text }
		children << ui2.label('', text, ui2.rect(f64(terminal_padding), f64(terminal_padding + row * terminal_row_height), f64(width - 2 * terminal_padding), f64(terminal_row_height)), ui2.TextStyle{
			color: terminal_text
			font_family: 'mono'
			size: 13
		})
	}

	// Scroll buttons, only when there is somewhere to scroll to. The keyboard
	// belongs to the shell, so they cannot be keys.
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
