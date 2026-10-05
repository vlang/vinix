// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

const activity_inspect_limit = 65_536
const activity_inspect_fd_limit = 128
const activity_inspect_line_limit = 2048
const activity_inspect_close = 'activity.inspector.close'
const activity_inspect_export = 'activity.inspector.export'
const activity_inspect_overview = 'activity.inspector.overview'
const activity_inspect_memory = 'activity.inspector.memory'
const activity_inspect_files = 'activity.inspector.files'
const activity_inspect_io = 'activity.inspector.io'
const activity_inspect_scrollbar = 'activity.inspector.scrollbar'
const activity_inspect_io_count = 6

struct ActivityInspectorIoSnapshot {
mut:
	values [activity_inspect_io_count]u64
	valid [activity_inspect_io_count]bool
}

// Fixed storage: sampling and calculating rates allocate no temporary lists.
// Each field has its own validity because older kernels may omit network I/O.
struct ActivityInspectorIo {
mut:
	pid int
	at_ms i64
	totals ActivityInspectorIoSnapshot
	rates [activity_inspect_io_count]f64
	rate_valid [activity_inspect_io_count]bool
}

fn activity_inspector_io_snapshot(data string, available bool) ActivityInspectorIoSnapshot {
	mut snapshot := ActivityInspectorIoSnapshot{}
	if !available { return snapshot }
	keys := ['rchar', 'wchar', 'read_bytes', 'write_bytes', 'net_recv_bytes', 'net_send_bytes']!
	mut start := 0
	for start < data.len {
		mut end := start
		for end < data.len && data[end] != `\n` { end++ }
		for index, key in keys {
			if end - start <= key.len || data[start + key.len] != `:` { continue }
			mut matches := true
			for j := 0; matches && j < key.len; j++ { matches = data[start + j] == key[j] }
			if !matches { continue }
			value, next := activity_resource_number(data, start + key.len + 1) or { continue }
			mut at := next
			for at < end && data[at] in [` `, `\t`, `\r`] { at++ }
			if at != end { continue }
			snapshot.values[index] = value
			snapshot.valid[index] = true
		}
		start = end + 1
	}
	return snapshot
}

fn (mut io ActivityInspectorIo) apply(pid int, now_ms i64, snapshot ActivityInspectorIoSnapshot) {
	elapsed := if now_ms > io.at_ms && io.at_ms >= 0 { u64(now_ms - io.at_ms) } else { u64(0) }
	for index in 0 .. activity_inspect_io_count {
		io.rates[index] = 0
		io.rate_valid[index] = false
		if pid > 0 && pid == io.pid && snapshot.valid[index] && io.totals.valid[index] {
			if rate := activity_resource_rate(snapshot.values[index], io.totals.values[index], elapsed) {
				io.rates[index] = rate
				io.rate_valid[index] = true
			}
		}
	}
	io.pid = pid
	io.at_ms = now_ms
	io.totals = snapshot
}

fn activity_inspector_io_rate_text(rate f64, valid bool) string {
	if !valid { return tr('activity.inspector.io.unknown').clone() }
	// Avoid an out-of-range float-to-u64 conversion for a malformed or very
	// large synthetic counter, while keeping the stored rate exact as f64.
	bytes := if rate >= f64(u64(-1)) { u64(-1) } else { u64(rate) }
	size := human_size(bytes)
	text := tr_fill('activity.resources.rate', size)
	unsafe { size.free() }
	return text
}

enum ActivityInspectTab {
	overview
	memory
	files
	io
}

struct ActivityInspector {
mut:
	pid               int
	pid_text          string
	executable        string
	command           string
	status            string
	maps              string
	smaps             string
	statm             string
	files             string
	io_raw            string
	io                ActivityInspectorIo
	overview_lines    []string
	memory_lines      []string
	file_lines        []string
	io_lines          []string
	buffer            []u8
	tab               ActivityInspectTab
	scroll            int
	visible_rows      int = 1
	error             string
	export_status     string
	last_sample_ms    i64
	truncated         bool
	files_available   bool
	memory_available  bool
	status_available  bool
	command_available bool
	io_available      bool
	width             int
	language          DesktopLanguage
	dragging          bool
	drag_y            int
	drag_scroll       int
}

fn (mut inspector ActivityInspector) read_proc(entry string) (string, bool) {
	if inspector.buffer.len == 0 { inspector.buffer = []u8{len: activity_inspect_limit + 1} }
	path := '/proc/${inspector.pid_text}/${entry}'
	defer { unsafe { path.free() } }
	fd := desktop_open_ro_nonblock(path)
	if fd < 0 { return '', false }
	defer { desktop_close(fd) }
	mut length := 0
	for length < inspector.buffer.len {
		got := desktop_read(fd, unsafe { &inspector.buffer[length] }, u64(inspector.buffer.len - length))
		if got < 0 { return '', false }
		if got == 0 { break }
		length += int(got)
	}
	if length > activity_inspect_limit {
		inspector.truncated = true
		length = activity_inspect_limit
	}
	return if length > 0 { unsafe { tos(inspector.buffer.data, length).clone() } } else { '' }, true
}

fn (inspector &ActivityInspector) read_link(entry string) string {
	path := '/proc/${inspector.pid_text}/${entry}'
	defer { unsafe { path.free() } }
	mut buffer := [4096]u8{}
	length := C.readlink(&char(path.str), &char(&buffer[0]), usize(buffer.len))
	return if length > 0 { unsafe { tos(&buffer[0], int(length)).clone() } } else { '' }
}

// Preserve argument boundaries in the command display. Embedded whitespace
// and shell metacharacters are quoted; this is a diagnostic display only.
fn activity_inspector_command(bytes string) string {
	mut result := []u8{cap: bytes.len * 2 + 1}
	unsafe { result.flags |= .noslices }
	mut start := 0
	mut first := true
	for start < bytes.len {
		mut end := start
		for end < bytes.len && bytes[end] != 0 { end++ }
		if !first { result << ` ` }
		first = false
		mut quote := end == start
		for index := start; index < end; index++ {
			if bytes[index] in [` `, `\t`, `\n`, `\r`, `'`, `"`, `\\`, `$`, `;`, `|`, `&`, `(`,
				`)`, `<`, `>`] {
				quote = true
			}
		}
		if quote { result << `'` }
		for index := start; index < end; index++ {
			byte := bytes[index]
			if byte == `'` && quote {
				result << `'`
				result << `\\`
				result << `'`
				result << `'`
			} else if byte == `\n` || byte == `\r` {
				result << ` `
			} else {
				result << byte
			}
		}
		if quote { result << `'` }
		start = end + 1
	}
	text := if result.len > 0 { unsafe { tos(result.data, result.len).clone() } } else { '' }
	unsafe { result.free() }
	return text
}

fn activity_inspector_free_lines(mut lines []string) {
	for line in lines {
		unsafe { line.free() }
	}
	lines.clear()
}

// Wrap stored lines to the inspector's monospace-sized cells once per sample
// or resize. This lets long commands and memory mappings be read by scrolling.
fn activity_inspector_append_lines(mut lines []string, text string, columns int) {
	unsafe { lines.flags |= .noslices }
	mut start := 0
	mut index := 0
	mut cells := 0
	for index < text.len && lines.len < activity_inspect_line_limit {
		byte := text[index]
		if byte == `\n` {
			lines << unsafe { tos(&u8(text.str) + start, index - start).clone() }
			index++
			start = index
			cells = 0
			continue
		}
		if byte & 0xc0 != 0x80 { cells++ }
		if cells > columns && index > start {
			lines << unsafe { tos(&u8(text.str) + start, index - start).clone() }
			start = index
			cells = 1
		}
		index++
	}
	if start < index && lines.len < activity_inspect_line_limit {
		lines << unsafe { tos(&u8(text.str) + start, index - start).clone() }
	}
}

fn (mut inspector ActivityInspector) read_files() string {
	path := '/proc/${inspector.pid_text}/fd'
	defer { unsafe { path.free() } }
	dir := desktop_opendir(path)
	inspector.files_available = dir != unsafe { nil }
	if !inspector.files_available { return '' }
	defer { desktop_closedir(dir) }
	mut name_buffer := [256]u8{}
	mut names := unsafe { (&name_buffer[0]).vbytes(name_buffer.len) }
	mut text := []u8{cap: 2048}
	unsafe { text.flags |= .noslices }
	mut count := 0
	for desktop_readdir(dir, mut names) {
		mut length := 0
		for length < name_buffer.len && name_buffer[length] != 0 { length++ }
		if length == 0 || name_buffer[0] == `.` { continue }
		if count >= activity_inspect_fd_limit {
			inspector.truncated = true
			break
		}
		count++
		name := unsafe { tos(&name_buffer[0], length) }
		entry := 'fd/${name}'
		target := inspector.read_link(entry)
		unsafe { entry.free() }
		for byte in name { text << byte }
		text << `:`
		text << ` `
		if target.len > 0 {
			for byte in target { text << byte }
		} else {
			for byte in tr('activity.inspector.fd_unavailable') { text << byte }
		}
		if target.starts_with('socket:') || target.starts_with('socket[') {
			text << ` `
			text << `(`
			for byte in tr('activity.inspector.socket') { text << byte }
			text << `)`
		}
		text << `\n`
		unsafe { target.free() }
	}
	if count == 0 {
		for byte in tr('activity.inspector.no_files') { text << byte }
	}
	result := if text.len > 0 { unsafe { tos(text.data, text.len).clone() } } else { '' }
	unsafe { text.free() }
	return result
}

fn (mut inspector ActivityInspector) sample(pid int) {
	if pid <= 0 { return }
	if inspector.pid != pid {
		inspector.pid = pid
		inspector.pid_text = replace_activity_text(inspector.pid_text, pid.str())
		inspector.scroll = 0
		inspector.export_status = replace_activity_text(inspector.export_status, '')
	}
	inspector.truncated = false
	status, status_ok := inspector.read_proc('status')
	inspector.status_available = status_ok
	inspector.status = replace_activity_text(inspector.status, status)
	command, command_ok := inspector.read_proc('cmdline')
	inspector.command_available = command_ok
	inspector.command = replace_activity_text(inspector.command, activity_inspector_command(command))
	unsafe { command.free() }
	inspector.executable = replace_activity_text(inspector.executable, inspector.read_link('exe'))
	maps, maps_ok := inspector.read_proc('maps')
	inspector.maps = replace_activity_text(inspector.maps, maps)
	smaps, smaps_ok := inspector.read_proc('smaps')
	inspector.smaps = replace_activity_text(inspector.smaps, smaps)
	statm, _ := inspector.read_proc('statm')
	inspector.statm = replace_activity_text(inspector.statm, statm)
	inspector.memory_available = maps_ok || smaps_ok
	inspector.files = replace_activity_text(inspector.files, inspector.read_files())
	io_text, io_ok := inspector.read_proc('io')
	inspector.io_raw = replace_activity_text(inspector.io_raw, io_text)
	inspector.io_available = io_ok && inspector.io_raw.len < activity_inspect_limit
	inspector.error = replace_activity_text(inspector.error, if !status_ok && !command_ok && !maps_ok {
		tr('activity.inspector.unavailable').clone()
	} else {
		''
	})
	inspector.last_sample_ms = monotonic_millis()
	inspector.io.apply(pid, inspector.last_sample_ms, activity_inspector_io_snapshot(inspector.io_raw, inspector.io_available))
	inspector.rebuild_lines()
}

fn (mut inspector ActivityInspector) rebuild_lines() {
	columns := if inspector.width > 160 { (inspector.width - 36) / 7 } else { 20 }
	activity_inspector_free_lines(mut inspector.overview_lines)
	activity_inspector_free_lines(mut inspector.memory_lines)
	activity_inspector_free_lines(mut inspector.file_lines)
	activity_inspector_free_lines(mut inspector.io_lines)
	activity_inspector_append_lines(mut inspector.overview_lines, tr('activity.inspector.executable'), columns)
	activity_inspector_append_lines(mut inspector.overview_lines, if inspector.executable != '' {
		inspector.executable
	} else {
		tr('activity.inspector.not_available')
	}, columns)
	activity_inspector_append_lines(mut inspector.overview_lines, tr('activity.inspector.command'), columns)
	activity_inspector_append_lines(mut inspector.overview_lines, if inspector.command_available {
		inspector.command
	} else {
		tr('activity.inspector.not_available')
	}, columns)
	activity_inspector_append_lines(mut inspector.overview_lines, '', columns)
	activity_inspector_append_lines(mut inspector.overview_lines, if inspector.status_available {
		inspector.status
	} else {
		tr('activity.inspector.status_unavailable')
	}, columns)
	if inspector.memory_available {
		activity_inspector_append_lines(mut inspector.memory_lines, tr('activity.inspector.maps'), columns)
		activity_inspector_append_lines(mut inspector.memory_lines, inspector.maps, columns)
		activity_inspector_append_lines(mut inspector.memory_lines, tr('activity.inspector.smaps'), columns)
		activity_inspector_append_lines(mut inspector.memory_lines, inspector.smaps, columns)
	} else {
		activity_inspector_append_lines(mut inspector.memory_lines, tr('activity.inspector.memory_unavailable'), columns)
	}
	activity_inspector_append_lines(mut inspector.file_lines, if inspector.files_available {
		inspector.files
	} else {
		tr('activity.inspector.files_unavailable')
	}, columns)
	if !inspector.io_available {
		activity_inspector_append_lines(mut inspector.io_lines, tr('activity.inspector.io.unavailable'), columns)
	}
	labels := ['activity.inspector.io.logical_read', 'activity.inspector.io.logical_write',
		'activity.inspector.io.disk_read', 'activity.inspector.io.disk_write',
		'activity.inspector.io.net_recv', 'activity.inspector.io.net_send']!
	for index, key in labels {
		total := if inspector.io.totals.valid[index] {
			inspector.io.totals.values[index].str()
		} else { tr('activity.inspector.io.unknown').clone() }
		rate := activity_inspector_io_rate_text(inspector.io.rates[index], inspector.io.rate_valid[index])
		line := tr_fill3('activity.inspector.io.counter', tr(key), total, rate)
		activity_inspector_append_lines(mut inspector.io_lines, line, columns)
		unsafe { total.free() rate.free() line.free() }
	}
	activity_inspector_append_lines(mut inspector.io_lines, tr('activity.inspector.io.scope'), columns)
	if inspector.overview_lines.len >= activity_inspect_line_limit || inspector.memory_lines.len >= activity_inspect_line_limit || inspector.file_lines.len >= activity_inspect_line_limit {
		inspector.truncated = true
	}
	inspector.clamp_scroll()
}

fn (inspector &ActivityInspector) line_count() int {
	return match inspector.tab {
		.overview { inspector.overview_lines.len }
		.memory { inspector.memory_lines.len }
		.files { inspector.file_lines.len }
		.io { inspector.io_lines.len }
	}
}

fn (inspector &ActivityInspector) line_at(index int) string {
	return match inspector.tab {
		.overview { inspector.overview_lines[index] }
		.memory { inspector.memory_lines[index] }
		.files { inspector.file_lines[index] }
		.io { inspector.io_lines[index] }
	}
}

fn (mut inspector ActivityInspector) clamp_scroll() {
	maximum := inspector.line_count() - inspector.visible_rows
	if inspector.scroll > maximum { inspector.scroll = maximum }
	if inspector.scroll < 0 { inspector.scroll = 0 }
}

fn (mut inspector ActivityInspector) export_report(home string) bool {
	if inspector.pid <= 0 { return false }
	filename := 'Activity-Monitor-${inspector.pid_text}.txt'
	path := '${home}/${filename}'
	status_note := if inspector.status_available {
		''
	} else {
		tr('activity.inspector.status_unavailable')
	}
	memory_note := if inspector.memory_available {
		''
	} else {
		tr('activity.inspector.memory_unavailable')
	}
	files_note := if inspector.files_available {
		''
	} else {
		tr('activity.inspector.files_unavailable')
	}
	limit_note := if inspector.truncated { tr('activity.inspector.truncated') } else { '' }
	io_note := if inspector.io_available { '' } else { tr('activity.inspector.io.unavailable') }
	report := 'Activity Monitor process report\nPID: ${inspector.pid_text}\nExecutable: ${inspector.executable}\nCommand: ${inspector.command}\n${limit_note}\n\nSTATUS\n${status_note}\n${inspector.status}\nMEMORY MAPS\n${memory_note}\n${inspector.maps}\nMEMORY DETAILS (kB)\n${inspector.smaps}\nSTATM (pages)\n${inspector.statm}\nOPEN FILES AND SOCKETS\n${files_note}\n${inspector.files}\nPROCESS I/O (bytes)\n${io_note}\n${inspector.io_raw}\n'
	defer {
		unsafe {
			report.free()
			path.free()
			filename.free()
		}
	}
	ok := activity_write_record(home, filename, report)
	message := if ok {
		tr_fill('activity.inspector.exported', path)
	} else {
		tr('activity.inspector.export_failed').clone()
	}
	inspector.export_status = replace_activity_text(inspector.export_status, message)
	return ok
}

fn (mut inspector ActivityInspector) handle(action string) bool {
	match action {
		activity_inspect_overview {
			inspector.tab = .overview
			inspector.scroll = 0
		}
		activity_inspect_memory {
			inspector.tab = .memory
			inspector.scroll = 0
		}
		activity_inspect_files {
			inspector.tab = .files
			inspector.scroll = 0
		}
		activity_inspect_io {
			inspector.tab = .io
			inspector.scroll = 0
		}
		activity_inspect_export {
			inspector.export_report(if desktop_user_home != '' {
				desktop_user_home
			} else {
				desktop_home
			})
		}
		activity_inspect_scrollbar {}
		else { return false }
	}
	return true
}

fn (mut inspector ActivityInspector) build(width int, height int) ui2.Element {
	if inspector.width != width || inspector.language != desktop_language {
		inspector.language = desktop_language
		inspector.width = width
		inspector.rebuild_lines()
	}
	inspector.visible_rows = if height > 108 { (height - 108) / activity_row_height } else { 1 }
	inspector.clamp_scroll()
	mut children := frame_elements(inspector.visible_rows + 12)
	children << ui2.label('', tr('activity.inspector.title'), ui2.rect(12, 4, f64(width - 80), 26), ui2.TextStyle{ color: body_heading, size: 13, bold: true })
	children << ui2.Element{
		...ui2.button_with_image(activity_inspect_close, '', 'builtin:close', ui2.rect(f64(width - 38), 4, 26, 26), ui2.BoxStyle{ bg: app_surface, radius: 4 }, ui2.TextStyle{ color: body_text })
		tooltip:             tr('activity.inspector.close')
		accessibility_label: tr('activity.inspector.close')
	}
	tab_width := (width - 42) / 4
	children << activity_toolbar_button(activity_inspect_overview, tr('activity.inspector.overview'), 12, 36, tab_width, inspector.tab == .overview)
	children << activity_toolbar_button(activity_inspect_memory, tr('activity.inspector.memory'), 18 + tab_width, 36, tab_width, inspector.tab == .memory)
	children << activity_toolbar_button(activity_inspect_files, tr('activity.inspector.files'), 24 + tab_width * 2, 36, tab_width, inspector.tab == .files)
	children << activity_toolbar_button(activity_inspect_io, tr('activity.inspector.io'), 30 + tab_width * 3, 36, tab_width, inspector.tab == .io)
	for index := inspector.scroll; index < inspector.line_count() && index < inspector.scroll + inspector.visible_rows; index++ {
		children << ui2.label('', inspector.line_at(index), ui2.rect(12, f64(72 + (index - inspector.scroll) * activity_row_height), f64(width - 36), f64(activity_row_height)),
			ui2.TextStyle{ color: body_text, size: 11 })
	}
	if inspector.line_count() > inspector.visible_rows {
		position, thumb := activity_scroll_thumb(height - 108, inspector.visible_rows, inspector.line_count(), inspector.scroll)
		mut marks := frame_elements(1)
		marks << ui2.view('', ui2.rect(1, f64(position), 6, f64(thumb)), ui2.BoxStyle{ bg: body_muted, radius: 3 }, [])
		children << ui2.clickable_view(activity_inspect_scrollbar, ui2.rect(f64(width - 10), 72, 8, f64(height - 108)), ui2.BoxStyle{ bg: body_rule, radius: 4 }, marks)
	}
	children << activity_toolbar_button(activity_inspect_export, tr('activity.inspector.export'), 12, height - 32, 116, false)
	children << ui2.label('', if inspector.export_status != '' {
		inspector.export_status
	} else if inspector.error != '' {
		inspector.error
	} else if inspector.truncated {
		tr('activity.inspector.truncated')
	} else {
		''
	}, ui2.rect(136, f64(height - 30), f64(width - 148), 26), ui2.TextStyle{ color: body_muted, size: 10 })
	return ui2.view('activity.inspector', ui2.rect(0, 0, f64(width), f64(height)), ui2.BoxStyle{ bg: body_panel }, children)
}

fn (mut inspector ActivityInspector) key_input(input string) {
	match input {
		'\x1b[A' { inspector.scroll-- }
		'\x1b[B' { inspector.scroll++ }
		'\x1b[5~' { inspector.scroll -= inspector.visible_rows }
		'\x1b[6~' { inspector.scroll += inspector.visible_rows }
		'\x1b[H', '\x1b[1~' { inspector.scroll = 0 }
		'\x1b[F', '\x1b[4~' { inspector.scroll = inspector.line_count() }
		else {}
	}
	inspector.clamp_scroll()
}

fn (mut inspector ActivityInspector) pointer_event(phase AppPointerPhase, button AppPointerButton, scroll int,
	x int, y int, width int, height int) {
	if phase == .scroll && y >= 72 && y < height - 36 {
		inspector.scroll -= scroll * 3
		inspector.clamp_scroll()
		return
	}
	if phase == .up {
		inspector.dragging = false
		return
	}
	if phase == .move && inspector.dragging {
		_, thumb := activity_scroll_thumb(height - 108, inspector.visible_rows, inspector.line_count(), inspector.drag_scroll)
		travel := height - 108 - thumb
		maximum := inspector.line_count() - inspector.visible_rows
		if travel > 0 {
			inspector.scroll = inspector.drag_scroll + (y - inspector.drag_y) * maximum / travel
			inspector.clamp_scroll()
		}
		return
	}
	if phase != .down || button != .left || x < width - 12 || y < 72 || y >= height - 36
		|| inspector.line_count() <= inspector.visible_rows {
		return
	}
	position, thumb := activity_scroll_thumb(height - 108, inspector.visible_rows, inspector.line_count(), inspector.scroll)
	if y - 72 < position || y - 72 >= position + thumb {
		inspector.scroll += if y - 72 < position {
			-inspector.visible_rows
		} else {
			inspector.visible_rows
		}
		inspector.clamp_scroll()
	}
	inspector.dragging = true
	inspector.drag_y = y
	inspector.drag_scroll = inspector.scroll
}

fn (mut inspector ActivityInspector) close() {
	activity_inspector_free_lines(mut inspector.overview_lines)
	activity_inspector_free_lines(mut inspector.memory_lines)
	activity_inspector_free_lines(mut inspector.file_lines)
	activity_inspector_free_lines(mut inspector.io_lines)
	unsafe {
		inspector.overview_lines.free()
		inspector.memory_lines.free()
		inspector.file_lines.free()
		inspector.io_lines.free()
		inspector.buffer.free()
		inspector.pid_text.free()
		inspector.executable.free()
		inspector.command.free()
		inspector.status.free()
		inspector.maps.free()
		inspector.smaps.free()
		inspector.statm.free()
		inspector.files.free()
		inspector.io_raw.free()
		inspector.error.free()
		inspector.export_status.free()
	}
}
