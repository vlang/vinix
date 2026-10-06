// SPDX-License-Identifier: GPL-2.0-or-later
// A bounded, read-only log viewer with literal filtering and safe export.
module main

import ui2

const console_poll_ms = u64(1000)
const console_default_path = '/var/log/Xorg.startx.log'
const console_filter_limit = 256
const console_field_limit = 4096

struct ConsoleLine {
	start int
	end   int
	severity ConsoleSeverity
}

struct ConsoleApp {
mut:
	path          string
	text          string
	lines         []ConsoleLine
	matching      []int
	path_input    []u8
	filter_input  []u8
	severity_filter ConsoleSeverityFilter
	export_input  []u8
	status_key    string
	export_status string
	count_text    string
	limited       bool
	follow        bool = true
	last_poll_ms  u64
	scroll        int
	horizontal    int
	page_rows     int = 12
	focus         int = -1
	select_all    bool
	pending       [4]u8
	pending_len   int
}

fn console_borrow(text string, start int, end int) string {
	if end <= start { return '' }
	return unsafe { tos(text.str + start, end - start) }
}

fn new_console_app(path string, export_path string) ConsoleApp {
	mut app := ConsoleApp{
		path:         if console_valid_path(path) { path.clone() } else { '' }
		path_input:   []u8{cap: console_field_limit}
		filter_input: []u8{cap: console_filter_limit}
		export_input: []u8{cap: console_field_limit}
		lines:        []ConsoleLine{cap: 256}
		matching:     []int{cap: 256}
	}
	unsafe {
		app.path_input.flags |= .noslices
		app.filter_input.flags |= .noslices
		app.export_input.flags |= .noslices
		app.lines.flags |= .noslices
		app.matching.flags |= .noslices
	}
	if console_valid_path(path) { editor_append(mut app.path_input, path) }
	if console_valid_path(export_path) { editor_append(mut app.export_input, export_path) }
	app.refresh()
	return app
}

fn open_console(mut desktop Desktop) !NativeApp {
	_ = desktop.tz_offset_seconds
	home := if desktop_user_home.len > 0 { desktop_user_home } else { desktop_home }
	export_path := join_path(home, 'vinix-console-export.txt')
	defer { unsafe { export_path.free() } }
	app := new_console_app(console_default_path, export_path)
	return &app
}

fn (mut a ConsoleApp) refresh() bool {
	next := console_read_snapshot(a.path)
	a.last_poll_ms = desktop_monotonic_ms()
	changed := next.text != a.text || next.status != a.status_key || next.limited != a.limited
		|| a.count_text.len == 0
	if !changed {
		unsafe { next.text.free() }
		return false
	}
	// No retained line owns a substring; all offsets refer to this snapshot.
	a.lines.clear()
	a.matching.clear()
	unsafe { a.text.free() }
	a.text = next.text
	a.status_key = next.status
	a.limited = next.limited
	mut start := 0
	for at in 0 .. a.text.len {
		if a.text[at] == `\n` {
			a.lines << ConsoleLine{ start: start, end: at, severity: console_line_severity(a.text, start, at) }
			start = at + 1
		}
	}
	if start < a.text.len { a.lines << ConsoleLine{ start: start, end: a.text.len, severity: console_line_severity(a.text, start, a.text.len) } }
	a.refilter()
	return true
}

fn (mut a ConsoleApp) refilter() {
	a.matching.clear()
	query := editor_bytes_text(a.filter_input)
	for index, line in a.lines {
		if console_severity_matches(a.severity_filter, line.severity)
			&& (query.len == 0 || console_borrow(a.text, line.start, line.end).contains(query)) {
			a.matching << index
		}
	}
	unsafe { a.count_text.free() }
	matched := a.matching.len.str()
	total := a.lines.len.str()
	a.count_text = '${matched} / ${total}'
	unsafe {
		matched.free()
		total.free()
	}
	if a.follow { a.scroll = a.max_scroll() } else { a.clamp_scroll() }
}

fn (a &ConsoleApp) max_scroll() int {
	return if a.matching.len > a.page_rows { a.matching.len - a.page_rows } else { 0 }
}

fn (mut a ConsoleApp) clamp_scroll() {
	if a.scroll < 0 { a.scroll = 0 }
	if a.scroll > a.max_scroll() { a.scroll = a.max_scroll() }
}

fn (mut a ConsoleApp) poll_at(now u64) bool {
	if !a.follow || now == ~u64(0) { return false }
	if a.last_poll_ms != ~u64(0) && now >= a.last_poll_ms
		&& now - a.last_poll_ms < console_poll_ms {
		return false
	}
	changed := a.refresh()
	a.last_poll_ms = now
	return changed
}

fn (mut a ConsoleApp) poll() bool { return a.poll_at(desktop_monotonic_ms()) }

fn (a &ConsoleApp) next_poll_ms() u64 { return console_poll_ms }

fn (mut a ConsoleApp) load_path(path string) {
	if !console_valid_path(path) {
		a.status_key = 'console.invalid_path'
		a.follow = false
		return
	}
	next_path := path.clone()
	unsafe { a.path.free() }
	a.path = next_path
	a.scroll = 0
	a.horizontal = 0
	a.export_status = ''
	a.focus = -1
	a.pending_len = 0
	a.refresh()
	if a.status_key.len == 0 { record_recent_item('vinix-console', a.path) }
}

fn (mut a ConsoleApp) set_source(path string) {
	if !console_valid_path(path) {
		a.status_key = 'console.invalid_path'
		a.follow = false
		return
	}
	a.path_input.clear()
	editor_append(mut a.path_input, path)
	a.load_path(path)
}

fn (mut a ConsoleApp) focus_field(field int) {
	a.focus = field
	a.select_all = false
	a.pending_len = 0
}

fn (mut a ConsoleApp) scroll_by(rows int) {
	a.follow = false
	a.scroll += rows
	a.clamp_scroll()
}

// Export all matching rows of the retained snapshot, including rows beyond
// the current viewport. Filtering and sanitization are reflected exactly.
fn (a &ConsoleApp) visible_text() string {
	mut bytes := []u8{cap: a.text.len + 1}
	for index in a.matching {
		line := a.lines[index]
		editor_append(mut bytes, console_borrow(a.text, line.start, line.end))
		bytes << `\n`
	}
	result := bytes.bytestr()
	unsafe { bytes.free() }
	return result
}

fn (mut a ConsoleApp) export_visible() {
	if a.status_key.len > 0 { return }
	data := a.visible_text()
	defer { unsafe { data.free() } }
	a.export_status = console_write_export(editor_bytes_text(a.export_input), data)
}

fn (mut a ConsoleApp) handle(event_id string) ! {
	a.pending_len = 0
	for index, action in console_severity_actions {
		if event_id == action {
			if a.severity_filter != console_severity_filters[index] {
				a.severity_filter = console_severity_filters[index]
				a.export_status = ''
				a.refilter()
			}
			return
		}
	}
	if event_id.starts_with(jump_open_prefix) {
		a.set_source(console_borrow(event_id, jump_open_prefix.len, event_id.len))
		return
	}
	match event_id {
		'console.source.xorg' { a.set_source(console_default_path) }
		'console.source.firefox' { a.set_source('/var/log/firefox.log') }
		'console.source.chromium' { a.set_source('/var/log/chromium.log') }
		'console.path' { a.focus_field(0) }
		'console.filter' { a.focus_field(1) }
		'console.export_path' { a.focus_field(2) }
		'console.load' {
			path := editor_bytes_text(a.path_input).clone()
			a.load_path(path)
			unsafe { path.free() }
		}
		'console.refresh' { a.refresh() }
		'console.follow' {
			a.follow = !a.follow
			if a.follow {
				a.refresh()
				a.scroll = a.max_scroll()
			}
		}
		'console.up' { a.scroll_by(-a.page_rows) }
		'console.down' { a.scroll_by(a.page_rows) }
		'console.left' { a.horizontal = if a.horizontal >= 16 { a.horizontal - 16 } else { 0 } }
		'console.right' {
			if a.horizontal < console_tail_bytes { a.horizontal += 16 }
		}
		'console.export' { a.export_visible() }
		else {}
	}
}

fn console_edit_character(mut bytes []u8, character string, maximum int, select_all bool) {
	if select_all { bytes.clear() }
	if bytes.len + character.len <= maximum { editor_append(mut bytes, character) }
}

fn (mut a ConsoleApp) append_character(character string) {
	match a.focus {
		0 { console_edit_character(mut a.path_input, character, console_field_limit, a.select_all) }
		1 {
			console_edit_character(mut a.filter_input, character, console_filter_limit, a.select_all)
		}
		2 {
			console_edit_character(mut a.export_input, character, console_field_limit, a.select_all)
		}
		else { return }
	}
	a.select_all = false
	if a.focus == 1 { a.refilter() }
	a.export_status = ''
}

fn console_backspace(mut bytes []u8, select_all bool) {
	if select_all {
		bytes.clear()
		return
	}
	if bytes.len > 0 { bytes.trim(editor_char_before(bytes, bytes.len)) }
}

fn (mut a ConsoleApp) key_input(input string) {
	if input == '\x1b[A' {
		a.scroll_by(-1)
		return
	}
	if input == '\x1b[B' {
		a.scroll_by(1)
		return
	}
	if input == '\x1b[5~' {
		a.scroll_by(-a.page_rows)
		return
	}
	if input == '\x1b[6~' {
		a.scroll_by(a.page_rows)
		return
	}
	if input == '\x1b[H' || input == '\x1b[1~' {
		a.follow = false
		a.scroll = 0
		return
	}
	if input == '\x1b[F' || input == '\x1b[4~' {
		a.follow = false
		a.scroll = a.max_scroll()
		return
	}
	if input == '\x1b[D' {
		a.handle('console.left') or {}
		return
	}
	if input == '\x1b[C' {
		a.handle('console.right') or {}
		return
	}
	// Unknown terminal escape sequences are commands, never field text.
	if input.len > 1 && input[0] == 0x1b {
		a.pending_len = 0
		return
	}
	for byte in input {
		if a.pending_len > 0 {
			if editor_utf8_follows(a.pending[0], a.pending_len, byte) {
				a.pending[a.pending_len] = byte
				a.pending_len++
				if a.pending_len == editor_utf8_length(a.pending[0]) {
					a.append_character(unsafe { tos(&a.pending[0], a.pending_len) })
					a.pending_len = 0
				}
				continue
			}
			a.pending_len = 0
		}
		if byte == 0x1b {
			a.focus = -1
			a.select_all = false
		} else if byte == `\t` {
			a.focus_field((a.focus + 1) % 3)
		} else if byte == `\r` || byte == `\n` {
			if a.focus == 0 {
				a.handle('console.load') or {}
			} else if a.focus == 2 {
				a.export_visible()
			}
		} else if byte == 0x01 {
			a.select_all = true
		} else if byte == 0x7f || byte == 0x08 {
			match a.focus {
				0 { console_backspace(mut a.path_input, a.select_all) }
				1 {
					console_backspace(mut a.filter_input, a.select_all)
					a.refilter()
				}
				2 { console_backspace(mut a.export_input, a.select_all) }
				else {}
			}
			a.select_all = false
		} else if byte >= 0x20 && byte < 0x7f {
			a.append_character(unsafe { tos(&byte, 1) })
		} else if editor_utf8_length(byte) > 1 {
			a.pending[0] = byte
			a.pending_len = 1
		}
	}
}

fn (mut a ConsoleApp) paste_input(text string) {
	if a.focus < 0 { return }
	a.pending_len = 0
	match a.focus {
		0 { console_paste_field(mut a.path_input, text, console_field_limit, a.select_all) }
		1 {
			console_paste_field(mut a.filter_input, text, console_filter_limit, a.select_all)
			a.refilter()
		}
		2 { console_paste_field(mut a.export_input, text, console_field_limit, a.select_all) }
		else { return }
	}
	a.select_all = false
	a.export_status = ''
}

fn console_paste_field(mut bytes []u8, text string, maximum int, select_all bool) {
	mut at := 0
	mut pasted := false
	for at < text.len {
		lead := text[at]
		length := editor_utf8_length(lead)
		mut valid := lead >= 0x20 && lead != 0x7f && length > 0 && at + length <= text.len
		for index := 1; valid && index < length; index++ {
			valid = editor_utf8_follows(lead, index, text[at + index])
		}
		if valid && !(length == 2 && lead == 0xc2 && text[at + 1] <= 0x9f) {
			if !pasted && select_all { bytes.clear() }
			if bytes.len + length > maximum { break }
			editor_append(mut bytes, console_borrow(text, at, at + length))
			pasted = true
			at += length
		} else {
			at++
		}
	}
}

fn console_button(id string, key string, x int, y int, width int, active bool) ui2.Element {
	return ui2.button(id, tr(key), ui2.rect(f64(x), f64(y), f64(width), 28),
		ui2.BoxStyle{ bg: if active { app_accent } else { body_panel }, radius: 5 },
		ui2.TextStyle{ color: if active { app_on_accent } else { body_text }, size: 12, align: .center })
}

fn console_field(id string, value string, x int, y int, width int, focused bool) ui2.Element {
	mut children := frame_elements(1)
	// Append the temporary directly: inserting a named Element parameter
	// deep-clones its strings in V3, defeating the frame's borrowed text.
	children << ui2.text_field('', '', value, ui2.rect(8, 0, f64(width - 16), 30),
		ui2.BoxStyle{ transparent: true }, ui2.TextStyle{ color: body_text, size: 12 }, 0)
	return ui2.clickable_view(id, ui2.rect(f64(x), f64(y), f64(width), 30),
		ui2.BoxStyle{
			bg:            body_panel
			radius:        5
			border_color:  if focused { app_accent } else { body_rule }
			border_top:    1
			border_bottom: 1
			border_left:   1
			border_right:  1
		},
		children)
}

fn console_line_window(text string, line ConsoleLine, column int, width int) string {
	mut at := line.start
	mut skip := column
	for at < line.end && skip > 0 {
		at += editor_utf8_length(text[at])
		skip--
	}
	start := at
	mut remaining := width
	for at < line.end && remaining > 0 {
		at += editor_utf8_length(text[at])
		remaining--
	}
	return console_borrow(text, start, at)
}

fn (mut a ConsoleApp) build(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)
	if width < 380 || height < 360 {
		mut small := frame_elements(1)
		small << ui2.label('console.resize', tr('console.resize'),
			ui2.rect(8, 8, f64(if width > 16 { width - 16 } else { 1 }),
				f64(if height > 16 { height - 16 } else { 1 })),
			ui2.TextStyle{ color: body_muted, size: 12, lines: 3 })
		return ui2.screen(app_surface, small)
	}
	footer := height - 92
	log_top := a.severity_log_top(width)
	a.page_rows = if footer > log_top { (footer - log_top) / 20 } else { 1 }
	if a.page_rows < 1 { a.page_rows = 1 }
	if a.follow { a.scroll = a.max_scroll() } else { a.clamp_scroll() }
	mut children := frame_elements(a.page_rows + 34)
	children << console_button('console.source.xorg', 'console.source.xorg', 14, 10, 110, false)
	children << console_button('console.source.firefox', 'console.source.firefox', 132, 10, 110, false)
	children << console_button('console.source.chromium', 'console.source.chromium', 250, 10, 110, false)
	children << console_field('console.path', editor_bytes_text(a.path_input), 14, 46, width - 104, a.focus == 0)
	children << console_button('console.load', 'console.load', width - 82, 47, 68, false)
	children << console_button('console.refresh', 'console.refresh', 14, 84, 100, false)
	children << console_button('console.follow', 'console.follow', 122, 84, 112, a.follow)
	children << ui2.label('', tr('console.matches'), ui2.rect(250, 84, 106, 28), ui2.TextStyle{ color: body_muted, size: 12 })
	children << ui2.label('', a.count_text, ui2.rect(362, 84, f64(width - 376), 28), ui2.TextStyle{ color: body_text, size: 12 })
	children << ui2.label('', tr('console.filter'), ui2.rect(14, 125, 98, 28), ui2.TextStyle{ color: body_muted, size: 12 })
	children << console_field('console.filter', editor_bytes_text(a.filter_input), 114, 122, width - 128, a.focus == 1)
	a.build_severity_controls(mut children, width)
	if a.status_key.len > 0 || a.matching.len == 0 {
		key := if a.status_key.len > 0 {
			a.status_key
		} else if a.lines.len == 0 {
			'console.empty'
		} else {
			'console.no_matches'
		}
		message_height := if footer - log_top > 64 { 60 } else { footer - log_top - 4 }
		children << ui2.label('', tr(key), ui2.rect(18, f64(log_top), f64(width - 36), f64(message_height)),
			ui2.TextStyle{ color: body_muted, size: 13, lines: 3 })
	} else {
		columns := if width > 40 { (width - 40) / 8 } else { 1 }
		for row in 0 .. a.page_rows {
			index := a.scroll + row
			if index >= a.matching.len { break }
			line := a.lines[a.matching[index]]
			children << ui2.label('', console_line_window(a.text, line, a.horizontal, columns),
				ui2.rect(18, f64(log_top + row * 20), f64(width - 36), 20),
				ui2.TextStyle{ color: body_text, font_family: 'mono', size: 12 })
		}
	}
	children << console_button('console.up', 'console.up', 14, footer, 76, false)
	children << console_button('console.down', 'console.down', 98, footer, 76, false)
	children << console_button('console.left', 'console.left', 182, footer, 64, false)
	children << console_button('console.right', 'console.right', 254, footer, 64, false)
	if a.limited {
		children << ui2.label('', tr('console.limited'), ui2.rect(330, f64(footer), f64(width - 344), 28),
			ui2.TextStyle{ color: body_muted, size: 11 })
	}
	children << console_field('console.export_path', editor_bytes_text(a.export_input), 14, footer + 36, width - 142, a.focus == 2)
	children << console_button('console.export', 'console.export', width - 120, footer + 37, 106, false)
	children << ui2.label('', if a.export_status.len > 0 {
		tr(a.export_status)
	} else {
		tr('console.hint')
	},
		ui2.rect(14, f64(footer + 70), f64(width - 28), 20), ui2.TextStyle{ color: body_muted, size: 11 })
	return ui2.screen(app_surface, children)
}

fn (mut a ConsoleApp) close_app() {
	unsafe {
		a.path.free()
		a.text.free()
		a.count_text.free()
		a.lines.free()
		a.matching.free()
		a.path_input.free()
		a.filter_input.free()
		a.export_input.free()
	}
	a = ConsoleApp{}
}
