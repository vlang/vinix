// SPDX-License-Identifier: GPL-2.0-or-later
// Bounded snapshots of the machine's published reports. Strings in each
// section belong to that section; frame elements only borrow them.
module main

import ui2

const system_information_row_limit = 512
const system_information_text_limit = 512
const system_information_path_limit = 512
const system_information_tab_keys = ['system_information.overview', 'system_information.hardware',
	'system_information.storage', 'system_information.packages']
const system_information_tab_actions = ['system_information.tab.0', 'system_information.tab.1',
	'system_information.tab.2', 'system_information.tab.3']

// Keep this local name distinct from os.join_path: V3 can resolve an
// unqualified join_path to os.join_path_single, whose escaped builder is not
// released by the current compiler under -manualfree.
fn system_information_join_path(directory string, name string) string {
	return if directory.ends_with('/') { directory + name } else { '${directory}/${name}' }
}

struct SystemInformationLine {
	key string
	text string
	heading bool
	unavailable bool
}

struct SystemInformationSection {
mut:
	rows []SystemInformationLine
	limited bool
}

fn (mut section SystemInformationSection) clear() {
	for row in section.rows { unsafe { row.text.free() } }
	section.rows.clear()
	section.limited = false
}

// Takes ownership even when the section has reached its limit.
fn (mut section SystemInformationSection) add(key string, text string, heading bool) {
	section.add_row(SystemInformationLine{key: key, text: text, heading: heading})
}

fn (mut section SystemInformationSection) add_row(row SystemInformationLine) {
	text := row.text
	if section.rows.len >= system_information_row_limit {
		section.limited = true
		unsafe { text.free() }
		return
	}
	if section.rows.cap == 0 {
		section.rows = []SystemInformationLine{cap: 32}
		unsafe { section.rows.flags |= .noslices }
	}
	mut value := text
	if value.len > system_information_text_limit {
		value = system_information_text(text)
		unsafe { text.free() }
		section.limited = true
	}
	section.rows << SystemInformationLine{...row, text: value}
}

// Keep report text printable, bounded, and on whole UTF-8 characters.
fn system_information_text(text string) string {
	mut length_bound := text.len
	for length_bound > 0 && (text[length_bound - 1] == `\n` || text[length_bound - 1] == `\r`) { length_bound-- }
	mut out := []u8{cap: if length_bound < system_information_text_limit { length_bound } else { system_information_text_limit }}
	unsafe { out.flags |= .noslices }
	mut at := 0
	for at < length_bound && out.len < system_information_text_limit {
		ch := text[at]
		if ch < 32 || ch == 127 { out << ` `; at++; continue }
		length := editor_utf8_length(ch)
		if length == 0 { out << `?`; at++; continue }
		if at + length > length_bound || out.len + length > system_information_text_limit { break }
		mut valid := true
		for next in 1 .. length { if !editor_utf8_follows(ch, next, text[at + next]) { valid = false; break } }
		if !valid { out << `?`; at++; continue }
		for next in 0 .. length { out << text[at + next] }
		at += length
	}
	value := if out.len > 0 { unsafe { tos(out.data, out.len).clone() } } else { '' }
	unsafe { out.free() }
	return value
}

struct SystemInformationSources {
	version string = '/proc/version'
	cpu string = '/proc/cpuinfo'
	memory string = '/proc/meminfo'
	uptime string = '/proc/uptime'
	cpu_online string = '/sys/devices/system/cpu/online'
	node_online string = '/sys/devices/system/node/online'
	device_tree string = '/sys/devices'
	gpu string = '/proc/activity_gpu'
	network string = '/proc/net/dev'
	mounts string = '/proc/mounts'
	packages string = '/lib/apk/db/installed'
	custom_directory string = '/var/lib/vinix-pkg'
}

struct SystemInformationApp {
mut:
	sections [4]SystemInformationSection
	tab int
	scroll [4]int
	visible_rows int = 12
	initialized bool
	report_path []u8
	report_status string
	path_focus bool
	path_selected bool
	pending [4]u8
	pending_len int
	buffer [32769]u8
	read_limited bool
	search [128]u8
	search_len int
	search_focus bool
	search_selected bool
	search_indices [4][512]int
	search_counts [4]int
	search_language DesktopLanguage
	escape [16]u8
	escape_len int
	escape_ms u64
}

fn open_system_information(mut _ Desktop) !NativeApp {
	mut app := &SystemInformationApp{}
	app.initialize()
	app.refresh()
	return app
}

fn (mut app SystemInformationApp) initialize() {
	// V3 zero-initializes the array header in this heap-allocated model.
	// Give it a byte element size before the first append.
	if app.report_path.cap > 0 { unsafe { app.report_path.free() } }
	app.report_path = []u8{cap: system_information_path_limit}
	unsafe { app.report_path.flags |= .noslices }
	home := if desktop_user_home.len > 0 { desktop_user_home } else { desktop_home }
	path := system_information_join_path(home, 'system-information.txt')
	disk_usage_append(mut app.report_path, path)
	unsafe { path.free() }
}

fn (mut app SystemInformationApp) refresh() { app.refresh_sources(SystemInformationSources{}) }

fn (mut app SystemInformationApp) read(path string) ?string {
	got := desktop_read_file(path, &app.buffer[0], u64(app.buffer.len))
	app.read_limited = got > app.buffer.len - 1
	if got < 0 { return none }
	length := if got < app.buffer.len { int(got) } else { app.buffer.len - 1 }
	return unsafe { tos(&app.buffer[0], length) }
}

fn (mut app SystemInformationApp) value(tab int, key string, value string) {
	if value.len == 0 {
		app.sections[tab].add_row(SystemInformationLine{key: key, unavailable: true})
	} else {
		if value.len > system_information_text_limit { app.sections[tab].limited = true }
		app.sections[tab].add(key, system_information_text(value), false)
	}
}

fn (mut app SystemInformationApp) field(tab int, key string, data string, field string) {
	value := settings_about_value(data, field)
	app.value(tab, key, value)
	unsafe { value.free() }
}

fn (mut app SystemInformationApp) raw_report(tab int, key string, path string) {
	app.sections[tab].add(key, path.clone(), true)
	data := app.read(path) or {
		app.sections[tab].add('system_information.unavailable', '', false)
		return
	}
	app.sections[tab].limited = app.sections[tab].limited || app.read_limited
	mut start := 0
	for end in 0 .. data.len + 1 {
		if end < data.len && data[end] != `\n` { continue }
		if end > start {
			line := unsafe { tos(data.str + start, end - start) }
			if line.len > system_information_text_limit { app.sections[tab].limited = true }
			app.sections[tab].add('', system_information_text(line), false)
		}
		start = end + 1
	}
	if data.len == 0 { app.sections[tab].add('system_information.unavailable', '', false) }
}

fn (mut app SystemInformationApp) refresh_sources(sources SystemInformationSources) {
	for index in 0 .. 4 { app.sections[index].clear() }
	app.value(0, 'system_information.kernel', app.read(sources.version) or { '' })
	cpu := app.read(sources.cpu) or { '' }
	mut model := settings_about_value(cpu, 'model name')
	if model.len == 0 { model = settings_about_value(cpu, 'Hardware') }
	if model.len == 0 { model = settings_about_value(cpu, 'Processor') }
	app.value(0, 'system_information.cpu', model)
	unsafe { model.free() }
	app.field(0, 'system_information.architecture', cpu, 'CPU architecture:')
	app.value(0, 'system_information.cpu_online', app.read(sources.cpu_online) or { '' })
	memory := app.read(sources.memory) or { '' }
	app.field(0, 'system_information.memory_total', memory, 'MemTotal:')
	app.field(0, 'system_information.memory_available', memory, 'MemAvailable:')
	app.field(0, 'system_information.memory_cached', memory, 'Cached:')
	uptime := app.read(sources.uptime) or { '' }
	mut end := 0
	for end < uptime.len && uptime[end] != ` ` && uptime[end] != `\t` && uptime[end] != `\n` { end++ }
	app.value(0, 'system_information.uptime', unsafe { tos(uptime.str, end) })
	app.raw_report(1, 'system_information.cpu_report', sources.cpu)
	app.raw_report(1, 'system_information.cpu_online', sources.cpu_online)
	app.raw_report(1, 'system_information.numa_nodes', sources.node_online)
	app.raw_report(1, 'system_information.gpu_report', sources.gpu)
	app.raw_report(1, 'system_information.network_report', sources.network)
	// This sysfs implements CPU/NUMA topology, not PCI/USB driver inventory.
	app.sections[1].add('system_information.device_inventory_unavailable', sources.device_tree.clone(), false)
	app.collect_mounts(sources.mounts)
	app.collect_packages(sources.packages)
	names := ['gtk+3.0-demo', 'sublime-text', 'minecraft', 'voffice']!
	for name in names {
		filename := '${name}.files'
		path := system_information_join_path(sources.custom_directory, filename)
		info := desktop_lstat(path) or { unsafe { path.free(); filename.free() }; continue }
		if info.is_file && info.size > 0 { app.sections[3].add('system_information.custom_package', name.clone(), false) }
		unsafe { path.free(); filename.free() }
	}
	app.initialized = true
	app.report_status = ''
	app.refilter_search(false)
}

fn (mut app SystemInformationApp) clamp_scroll(tab int) {
	count := app.filtered_count(tab)
	maximum := if count > app.visible_rows { count - app.visible_rows } else { 0 }
	if app.scroll[tab] < 0 { app.scroll[tab] = 0 }
	if app.scroll[tab] > maximum { app.scroll[tab] = maximum }
}

fn (mut app SystemInformationApp) handle(id string) ! {
	for tab, action in system_information_tab_actions {
		if id == action { app.tab = tab; app.path_focus = false; app.search_focus = false; app.pending_len = 0; return }
	}
	match id {
		'system_information.refresh' { app.refresh() }
		'system_information.export' { app.export_report() }
		'system_information.path' { app.focus_path() }
		'system_information.search' { app.focus_search(false) }
		'system_information.search.clear' { app.clear_search() }
		'system_information.previous' { app.scroll[app.tab] -= app.visible_rows; app.clamp_scroll(app.tab) }
		'system_information.next' { app.scroll[app.tab] += app.visible_rows; app.clamp_scroll(app.tab) }
		else {}
	}
}

fn (app &SystemInformationApp) pointer_input_enabled() bool { return true }
fn (app &SystemInformationApp) pointer_moves_matter() bool { return false }

fn (mut app SystemInformationApp) pointer_event(phase AppPointerPhase, _ AppPointerButton,
	scroll int, x int, y int, _ int, height int) {
	if phase == .scroll && x >= 150 && y >= 94 && y < height - 100 {
		app.scroll[app.tab] -= scroll * 3
		app.clamp_scroll(app.tab)
	}
}

fn (mut app SystemInformationApp) path_byte(ch u8) {
	if app.pending_len > 0 {
		if editor_utf8_follows(app.pending[0], app.pending_len, ch) {
			app.pending[app.pending_len] = ch
			app.pending_len++
			if app.pending_len == editor_utf8_length(app.pending[0]) {
				app.path_text(unsafe { tos(&app.pending[0], app.pending_len) })
				app.pending_len = 0
			}
			return
		}
		app.pending_len = 0
	}
	if ch == 8 || ch == 127 {
		if app.path_selected { app.report_path.clear(); app.path_selected = false; return }
		mut from := app.report_path.len - 1
		for from > 0 && app.report_path[from] & 0xc0 == 0x80 { from-- }
		if from >= 0 { app.report_path.trim(from) }
	} else if ch >= 32 && ch < 127 {
		app.path_text(unsafe { tos(&ch, 1) })
	} else if editor_utf8_length(ch) > 1 {
		app.pending[0] = ch
		app.pending_len = 1
	}
	app.report_status = ''
}

fn (mut app SystemInformationApp) path_text(text string) {
	if app.path_selected { app.report_path.clear(); app.path_selected = false }
	if app.report_path.len + text.len <= system_information_path_limit {
		unsafe { app.report_path.flags |= .noslices }
		disk_usage_append(mut app.report_path, text)
	}
	app.report_status = ''
}

fn (mut app SystemInformationApp) key_input(text string) {
	if app.search_language != desktop_language { app.refilter_search(false) }
	for ch in text {
		if ch == 0x06 { app.focus_search(true); continue }
		if ch == 0x0c { app.focus_path(); continue }
		if app.escape_byte(ch) { continue }
		match ch {
			0x01 { app.pending_len = 0; if app.search_focus { app.search_selected = true } else if app.path_focus { app.path_selected = true } }
			0x12 { app.pending_len = 0; app.refresh() }
			0x15 { if app.search_focus { app.clear_search() } else if app.path_focus { app.report_path.clear(); app.pending_len = 0; app.path_selected = false; app.report_status = '' } }
			0x1b { app.escape[0] = ch; app.escape_len = 1; app.escape_ms = desktop_monotonic_ms(); app.pending_len = 0 }
			`\r`, `\n` { if app.path_focus { app.pending_len = 0; app.export_report() } }
			else { if app.search_focus { app.search_byte(ch) } else if app.path_focus { app.path_byte(ch) } }
		}
	}
}

fn (mut app SystemInformationApp) paste_input(text string) {
	app.expire_escape(~u64(0))
	if app.search_focus { app.paste_search(text); return }
	if !app.path_focus { return }
	app.pending_len = 0
	for ch in text { if ch >= 32 && ch != 127 { app.path_byte(ch) } }
	app.pending_len = 0
}

fn system_information_row_text(row SystemInformationLine) (string, bool) {
	if row.key.len == 0 { return row.text, false }
	if row.unavailable { return tr_fill2('system_information.item', tr(row.key), tr('system_information.unavailable')), true }
	if row.text.len == 0 { return tr(row.key), false }
	return tr_fill2('system_information.item', tr(row.key), row.text), true
}

fn (mut app SystemInformationApp) build(size ui2.Rect) !ui2.Element {
	if !app.initialized { app.refresh() }
	width := if int(size.width) >= 400 { int(size.width) } else { 400 }
	height := if int(size.height) >= 250 { int(size.height) } else { 250 }
	if app.search_language != desktop_language { app.refilter_search(false) }
	mut rows := (height - 220) / 22
	if rows < 1 { rows = 1 }
	if rows > 48 { rows = 48 }
	app.visible_rows = rows
	app.clamp_scroll(app.tab)
	mut children := frame_elements(96)
	children << ui2.label('', tr('app.system_information'), ui2.rect(12, 12, 250, 28), ui2.TextStyle{size: 18, bold: true, color: body_heading})
	children << ui2.button('system_information.refresh', tr('system_information.refresh'), ui2.rect(f64(width - 116), 12, 104, 28), ui2.BoxStyle{bg: settings_choice_bg, radius: 5}, ui2.TextStyle{size: 12, color: body_text, align: .center})
	children << app.search_field(width)
	children << ui2.button('system_information.search.clear', tr('system_information.search.clear'), ui2.rect(f64(width - 88), 54, 76, 28), ui2.BoxStyle{bg: settings_choice_bg, radius: 5}, ui2.TextStyle{size: 12, color: body_text, align: .center})
	for tab, key in system_information_tab_keys {
		tab_y := if height < 300 { 50 + tab * 30 } else { 54 + tab * 36 }
		tab_height := if height < 300 { 26 } else { 30 }
		children << ui2.button(system_information_tab_actions[tab], tr(key), ui2.rect(12, f64(tab_y), 134, f64(tab_height)),
			ui2.BoxStyle{bg: if app.tab == tab { app_accent } else { settings_choice_bg }, radius: 5},
			ui2.TextStyle{size: 12, color: if app.tab == tab { u32(0xffffff) } else { body_text }, align: .center})
	}
	section := &app.sections[app.tab]
	for slot in 0 .. rows {
		filtered := app.scroll[app.tab] + slot
		if filtered >= app.filtered_count(app.tab) { break }
		index := if app.search_len == 0 { filtered } else { app.search_indices[app.tab][filtered] }
		row := section.rows[index]
		text, owned := system_information_row_text(row)
		children << ui2.Element{
			...ui2.label(if owned { frame_owned_text_id } else { '' }, text,
				ui2.rect(158, f64(94 + slot * 22), f64(width - 170), 22),
				ui2.TextStyle{size: 12, color: if row.heading { body_heading } else { body_text }, bold: row.heading})
			tooltip: text
		}
	}
	if app.filtered_count(app.tab) == 0 && app.search_len > 0 {
		children << ui2.label('system_information.search.empty', tr('system_information.search.empty'), ui2.rect(158, 94, f64(width - 170), 38), ui2.TextStyle{size: 12, color: body_muted, lines: 2})
	}
	page_width := if width < 500 { 56 } else { 80 }
	count_x := 158 + page_width * 2 + 20
	children << ui2.button('system_information.previous', tr('system_information.previous'), ui2.rect(158, f64(height - 112), f64(page_width), 26), ui2.BoxStyle{bg: settings_choice_bg, radius: 4}, ui2.TextStyle{size: 11, color: body_text, align: .center})
	children << ui2.button('system_information.next', tr('system_information.next'), ui2.rect(f64(166 + page_width), f64(height - 112), f64(page_width), 26), ui2.BoxStyle{bg: settings_choice_bg, radius: 4}, ui2.TextStyle{size: 11, color: body_text, align: .center})
	if app.search_len > 0 {
		count_key := if width < 500 { 'system_information.search.count_short' } else { 'system_information.search.count' }
		children << ui2.label(frame_owned_text_id, tr_count(count_key, i64(app.filtered_count(app.tab))), ui2.rect(f64(count_x), f64(height - 112), f64(width - count_x - 12), 26), ui2.TextStyle{size: 11, color: body_muted})
	} else if section.limited {
		children << ui2.label('', tr('system_information.limited'), ui2.rect(338, f64(height - 112), f64(width - 350), 26), ui2.TextStyle{size: 11, color: body_muted})
	}
	children << ui2.label('', tr('system_information.destination'), ui2.rect(12, f64(height - 77), 220, 20), ui2.TextStyle{size: 11, color: body_muted})
	children << disk_usage_path_field('system_information.path', disk_usage_buffer_text(app.report_path), 12, height - 55, width - 136, app.path_focus)
	children << ui2.button('system_information.export', tr('system_information.export'), ui2.rect(f64(width - 116), f64(height - 55), 104, 28), ui2.BoxStyle{bg: settings_choice_bg, radius: 5}, ui2.TextStyle{size: 12, color: body_text, align: .center})
	if app.report_status.len > 0 {
		children << ui2.label('', tr(app.report_status), ui2.rect(12, f64(height - 24), f64(width - 24), 20), ui2.TextStyle{size: 11, color: body_muted})
	}
	return ui2.view('system_information.body', ui2.rect(0, 0, f64(width), f64(height)), ui2.BoxStyle{bg: app_surface}, children)
}

fn (app &SystemInformationApp) report() []u8 {
	mut data := []u8{cap: 8192}
	unsafe { data.flags |= .noslices }
	disk_usage_append(mut data, tr('app.system_information'))
	disk_usage_append(mut data, '\n')
	for tab, section in app.sections {
		disk_usage_append(mut data, '\n')
		disk_usage_append(mut data, tr(system_information_tab_keys[tab]))
		disk_usage_append(mut data, '\n')
		for row in section.rows {
			if row.key.len > 0 {
				disk_usage_append(mut data, tr(row.key))
				if row.text.len > 0 || row.unavailable { disk_usage_append(mut data, ': ') }
			}
			disk_usage_append(mut data, if row.unavailable { tr('system_information.unavailable') } else { row.text })
			disk_usage_append(mut data, '\n')
		}
		if section.limited { disk_usage_append(mut data, tr('system_information.limited')); disk_usage_append(mut data, '\n') }
	}
	return data
}

fn (mut app SystemInformationApp) export_report() {
	path := disk_usage_buffer_text(app.report_path).clone()
	defer { unsafe { path.free() } }
	if path.len == 0 || path[0] != `/` { app.report_status = 'system_information.report.invalid'; return }
	if desktop_lstat(path) != none { app.report_status = 'system_information.report.exists'; return }
	data := app.report()
	saved := disk_usage_write_report(path, data)
	unsafe { data.free() }
	app.report_status = if saved { 'system_information.report.saved' } else { 'system_information.report.failed' }
}

fn (mut app SystemInformationApp) close_app() {
	for index in 0 .. 4 {
		app.sections[index].clear()
		unsafe { app.sections[index].rows.free() }
		app.sections[index].rows = []SystemInformationLine{}
	}
	unsafe { app.report_path.free() }
	app.report_path = []u8{}
	app.initialized = false
	app.pending_len = 0
	app.search_len = 0
	app.search_focus = false
	app.search_selected = false
	app.search_counts = [4]int{}
	app.escape_len = 0
}
