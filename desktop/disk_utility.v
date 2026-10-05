// SPDX-License-Identifier: GPL-2.0-or-later
// Bounded read-only device and mount inventory. Every retained string belongs
// to the model; frame text borrows it or uses frame_owned_text_id.
module main

const disk_utility_row_limit = 256
const disk_utility_entry_limit = 4096
const disk_utility_text_limit = 512
const disk_utility_path_limit = 512
const disk_utility_row_actions = ['disk_utility.row.0', 'disk_utility.row.1', 'disk_utility.row.2',
	'disk_utility.row.3', 'disk_utility.row.4', 'disk_utility.row.5', 'disk_utility.row.6', 'disk_utility.row.7',
	'disk_utility.row.8', 'disk_utility.row.9', 'disk_utility.row.10', 'disk_utility.row.11',
	'disk_utility.row.12', 'disk_utility.row.13', 'disk_utility.row.14', 'disk_utility.row.15']

fn disk_utility_join_path(directory string, name string) string {
	return if directory.ends_with('/') { directory + name } else { '${directory}/${name}' }
}

struct DiskUtilityDevice {
	path string
	bytes u64
}

struct DiskUtilityMount {
	source string
	target string
	filesystem string
	options string
	capacity [3]u64
	capacity_valid bool
}

struct DiskUtilitySources {
	devices string = '/dev'
	mounts string = '/proc/mounts'
}

struct DiskUtilityApp {
mut:
	devices []DiskUtilityDevice
	mounts []DiskUtilityMount
	tab int
	selected [2]int
	page [2]int
	visible_rows int = 12
	initialized bool
	devices_unavailable bool
	mounts_unavailable bool
	limited bool
	report_path []u8
	report_status string
	path_focus bool
	path_selected bool
	pending [4]u8
	pending_len int
	buffer [65537]u8
}

fn open_disk_utility(mut _ Desktop) !NativeApp {
	mut app := &DiskUtilityApp{}
	app.initialize()
	app.refresh()
	return app
}

fn (mut app DiskUtilityApp) initialize() {
	if app.report_path.cap > 0 { unsafe { app.report_path.free() } }
	app.report_path = []u8{cap: disk_utility_path_limit}
	unsafe { app.report_path.flags |= .noslices }
	home := if desktop_user_home.len > 0 { desktop_user_home } else { desktop_home }
	path := disk_utility_join_path(home, 'disk-utility.txt')
	disk_usage_append(mut app.report_path, path)
	unsafe { path.free() }
}

fn (mut app DiskUtilityApp) clear_snapshot() {
	for device in app.devices { unsafe { device.path.free() } }
	for mount in app.mounts { unsafe { mount.source.free(); mount.target.free(); mount.filesystem.free(); mount.options.free() } }
	app.devices.clear()
	app.mounts.clear()
	app.devices_unavailable = false
	app.mounts_unavailable = false
	app.limited = false
}

fn (mut app DiskUtilityApp) prepare_snapshot() {
	app.clear_snapshot()
	if app.devices.cap == 0 { app.devices = []DiskUtilityDevice{cap: disk_utility_row_limit} }
	if app.mounts.cap == 0 { app.mounts = []DiskUtilityMount{cap: disk_utility_row_limit} }
	unsafe { app.devices.flags |= .noslices; app.mounts.flags |= .noslices }
}

fn (mut app DiskUtilityApp) refresh() { app.refresh_sources(DiskUtilitySources{}) }

fn (mut app DiskUtilityApp) refresh_sources(sources DiskUtilitySources) {
	app.prepare_snapshot()
	app.collect_devices(sources.devices)
	app.collect_mounts(sources.mounts)
	app.initialized = true
	app.report_status = ''
	for tab in 0 .. 2 { app.clamp_selection(tab) }
}

fn (app &DiskUtilityApp) count(tab int) int { return if tab == 0 { app.devices.len } else { app.mounts.len } }

fn (mut app DiskUtilityApp) clamp_selection(tab int) {
	count := app.count(tab)
	if app.selected[tab] >= count { app.selected[tab] = if count > 0 { count - 1 } else { 0 } }
	if app.selected[tab] < 0 { app.selected[tab] = 0 }
	maximum := if count > app.visible_rows { count - app.visible_rows } else { 0 }
	if app.page[tab] > maximum { app.page[tab] = maximum }
	if app.page[tab] < 0 { app.page[tab] = 0 }
}

fn (mut app DiskUtilityApp) move_selection(delta int) {
	app.path_focus = false
	app.selected[app.tab] += delta
	app.clamp_selection(app.tab)
	if app.selected[app.tab] < app.page[app.tab] { app.page[app.tab] = app.selected[app.tab] }
	if app.selected[app.tab] >= app.page[app.tab] + app.visible_rows { app.page[app.tab] = app.selected[app.tab] - app.visible_rows + 1 }
}

fn (mut app DiskUtilityApp) handle(id string) ! {
	for slot, action in disk_utility_row_actions {
		if id == action {
			app.selected[app.tab] = app.page[app.tab] + slot
			app.clamp_selection(app.tab)
			app.path_focus = false
			return
		}
	}
	match id {
		'disk_utility.devices' { app.tab = 0; app.path_focus = false; app.pending_len = 0 }
		'disk_utility.volumes' { app.tab = 1; app.path_focus = false; app.pending_len = 0 }
		'disk_utility.refresh' { app.refresh() }
		'disk_utility.previous' { app.page[app.tab] -= app.visible_rows; app.clamp_selection(app.tab) }
		'disk_utility.next' { app.page[app.tab] += app.visible_rows; app.clamp_selection(app.tab) }
		'disk_utility.path' { app.path_focus = true; app.path_selected = true; app.pending_len = 0 }
		'disk_utility.export' { app.export_report() }
		else {}
	}
}

fn (app &DiskUtilityApp) pointer_input_enabled() bool { return true }
fn (app &DiskUtilityApp) pointer_moves_matter() bool { return false }
fn (mut app DiskUtilityApp) pointer_event(phase AppPointerPhase, _ AppPointerButton,
	scroll int, x int, y int, _ int, height int) {
	if phase == .scroll && x >= 12 && x < 270 && y >= 96 && y < height - 106 {
		app.page[app.tab] -= scroll * 3
		app.clamp_selection(app.tab)
	}
}

fn (mut app DiskUtilityApp) path_text(text string) {
	if app.path_selected { app.report_path.clear(); app.path_selected = false }
	if app.report_path.len + text.len <= disk_utility_path_limit { disk_usage_append(mut app.report_path, text) }
	app.report_status = ''
}

fn (mut app DiskUtilityApp) path_byte(ch u8) {
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
	} else if ch >= 32 && ch < 127 { app.path_text(unsafe { tos(&ch, 1) }) }
	else if editor_utf8_length(ch) > 1 { app.pending[0] = ch; app.pending_len = 1 }
	app.report_status = ''
}

fn (mut app DiskUtilityApp) key_input(text string) {
	match text {
		'\x1b[A' { app.move_selection(-1); return }
		'\x1b[B' { app.move_selection(1); return }
		'\x1b[5~' { app.move_selection(-app.visible_rows); return }
		'\x1b[6~' { app.move_selection(app.visible_rows); return }
		'\x1b[H', '\x1b[1~' { app.move_selection(-disk_utility_row_limit); return }
		'\x1b[F', '\x1b[4~' { app.move_selection(disk_utility_row_limit); return }
		else {}
	}
	mut at := 0
	for at < text.len {
		ch := text[at]
		if ch == 0x1b && at + 1 < text.len && text[at + 1] == `[` {
			at += 2
			for at < text.len { final := text[at] >= 0x40 && text[at] <= 0x7e; at++; if final { break } }
			continue
		}
		match ch {
			0x0c { app.path_focus = true; app.path_selected = true; app.pending_len = 0 }
			0x12 { app.pending_len = 0; app.refresh() }
			0x15 { if app.path_focus { app.report_path.clear(); app.pending_len = 0; app.path_selected = false; app.report_status = '' } }
			0x1b { app.path_focus = false; app.pending_len = 0 }
			`\r`, `\n` { if app.path_focus { app.pending_len = 0; app.export_report() } }
			else { if app.path_focus { app.path_byte(ch) } }
		}
		at++
	}
}

fn (mut app DiskUtilityApp) paste_input(text string) {
	if !app.path_focus { return }
	app.pending_len = 0
	for ch in text { if ch >= 32 && ch != 127 { app.path_byte(ch) } }
	app.pending_len = 0
}

fn disk_utility_report_field(mut out []u8, key string, value string) {
	disk_usage_append(mut out, tr(key))
	disk_usage_append(mut out, ': ')
	clean := system_information_text(value)
	disk_usage_append(mut out, clean)
	disk_usage_append(mut out, '\n')
	unsafe { clean.free() }
}

fn disk_utility_report_bytes(mut out []u8, key string, bytes u64, valid bool) {
	if !valid { disk_utility_report_field(mut out, key, tr('disk_utility.unavailable')); return }
	text := bytes.str()
	disk_utility_report_field(mut out, key, text)
	unsafe { text.free() }
}

fn (app &DiskUtilityApp) report() []u8 {
	mut data := []u8{cap: 8192}
	unsafe { data.flags |= .noslices }
	disk_usage_append(mut data, tr('app.disk_utility'))
	disk_usage_append(mut data, '\n')
	disk_usage_append(mut data, tr('disk_utility.read_only'))
	disk_usage_append(mut data, '\n\n')
	disk_usage_append(mut data, tr('disk_utility.devices'))
	disk_usage_append(mut data, '\n')
	if app.devices_unavailable { disk_usage_append(mut data, tr('disk_utility.devices_unavailable')); disk_usage_append(mut data, '\n') }
	else if app.devices.len == 0 { disk_usage_append(mut data, tr('disk_utility.devices_empty')); disk_usage_append(mut data, '\n') }
	for device in app.devices {
		disk_utility_report_field(mut data, 'disk_utility.device', device.path)
		disk_utility_report_bytes(mut data, 'disk_utility.size_bytes', device.bytes, device.bytes > 0)
	}
	disk_usage_append(mut data, '\n')
	disk_usage_append(mut data, tr('disk_utility.volumes'))
	disk_usage_append(mut data, '\n')
	if app.mounts_unavailable { disk_usage_append(mut data, tr('disk_utility.mounts_unavailable')); disk_usage_append(mut data, '\n') }
	else if app.mounts.len == 0 { disk_usage_append(mut data, tr('disk_utility.mounts_empty')); disk_usage_append(mut data, '\n') }
	for mount in app.mounts {
		disk_utility_report_field(mut data, 'disk_utility.mount', mount.target)
		disk_utility_report_field(mut data, 'disk_utility.source', mount.source)
		disk_utility_report_field(mut data, 'disk_utility.filesystem', mount.filesystem)
		disk_utility_report_field(mut data, 'disk_utility.options', mount.options)
		disk_utility_report_bytes(mut data, 'disk_utility.total_bytes', mount.capacity[0], mount.capacity_valid)
		disk_utility_report_bytes(mut data, 'disk_utility.used_bytes', mount.capacity[1], mount.capacity_valid)
		disk_utility_report_bytes(mut data, 'disk_utility.available_bytes', mount.capacity[2], mount.capacity_valid)
		disk_usage_append(mut data, '\n')
	}
	disk_usage_append(mut data, tr('disk_utility.metadata_unavailable'))
	disk_usage_append(mut data, '\n')
	if app.limited { disk_usage_append(mut data, tr('disk_utility.limited')); disk_usage_append(mut data, '\n') }
	return data
}

fn (mut app DiskUtilityApp) export_report() {
	path := disk_usage_buffer_text(app.report_path).clone()
	defer { unsafe { path.free() } }
	if path.len == 0 || path[0] != `/` { app.report_status = 'disk_utility.report.invalid'; return }
	if desktop_lstat(path) != none { app.report_status = 'disk_utility.report.exists'; return }
	data := app.report()
	saved := disk_usage_write_report(path, data)
	unsafe { data.free() }
	app.report_status = if saved { 'disk_utility.report.saved' } else { 'disk_utility.report.failed' }
}

fn (mut app DiskUtilityApp) close_app() {
	app.clear_snapshot()
	unsafe { app.devices.free(); app.mounts.free(); app.report_path.free() }
	app.devices = []DiskUtilityDevice{}
	app.mounts = []DiskUtilityMount{}
	app.report_path = []u8{}
	app.initialized = false
	app.pending_len = 0
}
