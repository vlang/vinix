// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// A terminal, built into the desktop.
//
// It runs the real shell that is on the image — BusyBox's — rather than
// interpreting commands itself, so what it can do is whatever the system can
// do. Vinix has no pseudo-terminals, so the shell is given plain pipes; since
// those are not a terminal it neither echoes what is typed nor prints a
// visible prompt. The terminal echoes input itself and turns private BusyBox
// prompt markers into the visible prompt. That keeps the prompt behind the
// foreground command even though there is no pty to provide that state.
//
// Like the file browser it satisfies NativeApp, so its process speaks the same
// compositor protocol. It additionally satisfies
// KeyboardApp, which is how the keystrokes reach it.
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

// ClosingApp releases subprocesses an application owns before its own process
// leaves. Ordinary app resources are closed by exit; Terminal also owns a
// shell process, which must not be orphaned when its window closes.
interface ClosingApp {
mut:
	close_app()
}

const terminal_shell = '/bin/busybox'
// `sh -i` rather than plain `sh`: without a terminal on its stdin the shell
// would otherwise decide it is running a script.
const terminal_shell_arg = 'sh'

// How much output is kept. A terminal that remembered everything would grow
// without bound on a system with no garbage collector.
const terminal_scrollback = 400

// Read this much of the shell's output per frame. Enough that `ls` of a large
// directory arrives in one or two frames, small enough that a program printing
// without pause cannot hold up the compositor.
const terminal_read_chunk = 4096

const terminal_action_scroll_up = 'term.scroll.up'
const terminal_action_scroll_down = 'term.scroll.down'

const terminal_row_height = 16
const terminal_padding = 8
const terminal_prompt = '\$ '
const terminal_continuation_prompt = '> '

// BusyBox writes these as PS1/PS2. They are deliberately control-delimited:
// the output parser consumes them instead of putting them in scrollback, and
// either marker can be split across two non-blocking pipe reads.
const terminal_prompt_marker_start = u8(0x1e)
const terminal_prompt_marker_end = u8(0x1f)
const terminal_primary_prompt_code = u8(`P`)
const terminal_continuation_prompt_code = u8(`C`)
const terminal_primary_prompt_marker = '\x1eP\x1f'
const terminal_continuation_prompt_marker = '\x1eC\x1f'

struct TerminalApp {
mut:
	// Finished lines, oldest first.
	lines []string
	// The line arriving from the shell and the line being typed, held as bytes
	// rather than strings. `s += c` once per character allocates a new string
	// per character, and on a target with no garbage collector that is how a
	// machine is run out of memory by something as ordinary as `ls`. These two
	// are cleared and refilled, so a steady terminal stops allocating.
	partial []u8
	input   []u8
	// Reused across reads, for the same reason.
	read_buf []u8
	// The two buffers rendered as strings, rebuilt only when their bytes
	// change. build() runs on every frame the desktop redraws, and turning
	// bytes into a string there would allocate once a frame for as long as the
	// window is open.
	partial_text string
	input_text   string
	// The prompt line as drawn, cursor and all. Same reason.
	prompt_text string = terminal_prompt + '_'
	// Input is accepted only while BusyBox is actually asking for another
	// command. Without this state the synthetic `$` prompt used to reappear on
	// every Return while a package install was still running.
	ready        bool
	continuation bool
	marker_state u8
	marker_code  u8

	pid        int = -1
	to_child   int = -1
	from_child int = -1
	exited     bool
	error      string

	// Rows from the bottom the view is scrolled back by. Zero follows the
	// output, which is what a terminal does unless told otherwise.
	scroll       int
	visible_rows int = 1
}

fn open_terminal(mut _ Desktop) !NativeApp {
	mut app := &TerminalApp{
		read_buf: []u8{len: terminal_read_chunk}
	}
	shell := desktop_spawn_shell(terminal_shell, terminal_shell_arg, terminal_primary_prompt_marker, terminal_continuation_prompt_marker) or {
		app.error = 'cannot start ${terminal_shell}'
		app.lines << app.error
		return app
	}
	app.pid = shell.pid
	app.to_child = shell.to_child
	app.from_child = shell.from_child
	app.lines << 'Vinix terminal — ${terminal_shell} ${terminal_shell_arg}'
	app.lines << ''
	return app
}

// poll reads whatever the shell has produced and folds it into the scrollback,
// reporting whether anything changed. The desktop calls it every frame, which
// is what makes a command's output appear without the user having to move the
// mouse to provoke a redraw.
//
// Carriage returns are dropped rather than interpreted: without a pty there is
// no cursor for them to move, and a program that uses them to redraw a line is
// beyond what a minimal terminal promises.
fn (mut a TerminalApp) poll() bool {
	if a.from_child < 0 {
		return false
	}
	got := desktop_read(a.from_child, a.read_buf.data, u64(terminal_read_chunk))
	if got <= 0 {
		if !a.exited && a.pid >= 0 && desktop_child_exited(a.pid) {
			a.exited = true
			a.push_line('[${terminal_shell} exited]')
			return true
		}
		return false
	}

	a.ingest_output(a.read_buf[..int(got)])
	return true
}

// ingest_output separates the private prompt protocol from ordinary command
// output. Keeping the marker state on TerminalApp makes a marker that straddles
// two poll() reads just as reliable as one delivered in a single read.
fn (mut a TerminalApp) ingest_output(output []u8) {
	for ch in output {
		if a.marker_state == 0 {
			if ch == terminal_prompt_marker_start {
				a.marker_state = 1
				continue
			}
			a.ingest_visible_byte(ch)
			continue
		}

		if a.marker_state == 1 {
			if ch == terminal_primary_prompt_code || ch == terminal_continuation_prompt_code {
				a.marker_code = ch
				a.marker_state = 2
				continue
			}
			a.marker_state = 0
			// The leading record separator was invisible under the old parser
			// too. Preserve the byte after it, including another marker start.
			if ch == terminal_prompt_marker_start {
				a.marker_state = 1
			} else {
				a.ingest_visible_byte(ch)
			}
			continue
		}

		if ch == terminal_prompt_marker_end {
			a.ready = true
			a.continuation = a.marker_code == terminal_continuation_prompt_code
			a.marker_state = 0
			a.refresh_prompt()
			continue
		}

		// It looked like a marker but was ordinary output. The printable code
		// remains visible; the control delimiter remains filtered as before.
		code := a.marker_code
		a.marker_state = 0
		a.ingest_visible_byte(code)
		if ch == terminal_prompt_marker_start {
			a.marker_state = 1
		} else {
			a.ingest_visible_byte(ch)
		}
	}
	a.partial_text = replaced(a.partial_text, a.partial.bytestr())
}

fn (mut a TerminalApp) ingest_visible_byte(ch u8) {
	match ch {
		`\n` {
			a.push_line(a.partial.bytestr())
			a.partial.clear()
		}
		`\r` {}
		`\t` {
			// Tabs to the next multiple of eight, which is what a terminal
			// would have done and what keeps `ls -l` in columns.
			for _ in 0 .. 8 - a.partial.len % 8 {
				a.partial << ` `
			}
		}
		8 {
			if a.partial.len > 0 {
				a.partial.delete_last()
			}
		}
		else {
			if ch >= 0x20 {
				a.partial << ch
			}
		}
	}
}

fn (mut a TerminalApp) push_line(line string) {
	a.lines << line
	// Evicted lines are freed rather than dropped. With no garbage collector a
	// terminal left running leaks one string per line of output otherwise, and
	// a shell loop printing flat out gets through a lot of lines. Every string
	// that reaches here came from bytestr or an interpolation, both of which
	// allocate; the only ones that did not are the empty literals, which the
	// length check skips.
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

// key_input takes what was typed. The shell is on the far side of a pipe and
// cannot echo, so the terminal shows the line as it is built and only hands it
// over when Return completes it. While a foreground command owns the shell,
// there is intentionally no editable prompt: type-ahead cannot masquerade as
// commands the shell has already accepted.
fn (mut a TerminalApp) key_input(text string) {
	if !a.ready || a.exited {
		return
	}
	for ch in text {
		match ch {
			`\n`, `\r` {
				line := a.input.bytestr()
				prompt := if a.continuation {
					terminal_continuation_prompt
				} else {
					terminal_prompt
				}
				a.push_line('${prompt}${line}')
				if a.send('${line}\n') {
					a.ready = false
				}
				a.input.clear()
				a.refresh_prompt()
				return
			}
			8, 127 {
				if a.input.len > 0 {
					a.input.delete_last()
				}
			}
			else {
				if ch >= 0x20 && ch < 0x7f {
					a.input << ch
				}
			}
		}
	}
	a.refresh_prompt()
}

fn (mut a TerminalApp) refresh_prompt() {
	prompt := if a.continuation { terminal_continuation_prompt } else { terminal_prompt }
	a.input_text = replaced(a.input_text, a.input.bytestr())
	a.prompt_text = replaced(a.prompt_text, '${prompt}${a.input_text}_')
}

fn (mut a TerminalApp) send(line string) bool {
	if a.to_child < 0 || a.exited {
		return false
	}
	return desktop_write_all(a.to_child, line.str, u64(line.len))
}

fn (mut a TerminalApp) close_app() {
	if a.to_child >= 0 {
		desktop_close(a.to_child)
		a.to_child = -1
	}
	if a.from_child >= 0 {
		desktop_close(a.from_child)
		a.from_child = -1
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

	// The output, then the partial line the shell has not finished, then the
	// line being typed. Counted rather than gathered into one array: copying
	// the whole scrollback every frame would allocate as fast as the old
	// per-character concatenation did.
	partial_rows := if a.partial.len > 0 { 1 } else { 0 }
	prompt_rows := if a.exited || !a.ready { 0 } else { 1 }
	total := a.lines.len + partial_rows + prompt_rows

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
		text := if index < a.lines.len {
			a.lines[index]
		} else if index == a.lines.len && partial_rows == 1 {
			a.partial_text
		} else {
			// The cursor is a trailing underscore: there is no blink, and a
			// terminal that cannot show where typing goes is worse than one
			// whose cursor does not flash.
			a.prompt_text
		}
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
