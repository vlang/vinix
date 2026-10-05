// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn disk_utility_detail(key string, value string, x int, y int, width int) ui2.Element {
	clean := system_information_text(value)
	text := tr_fill2('disk_utility.item', tr(key), clean)
	unsafe { clean.free() }
	return ui2.Element{
		...ui2.label(frame_owned_text_id, text, ui2.rect(f64(x), f64(y), f64(width), 24),
			ui2.TextStyle{size: 12, color: body_text})
		tooltip: text
	}
}

fn disk_utility_size_detail(key string, bytes u64, valid bool, x int, y int, width int) ui2.Element {
	if !valid { return disk_utility_detail(key, tr('disk_utility.unavailable'), x, y, width) }
	text := disk_usage_size_text(bytes)
	result := disk_utility_detail(key, text, x, y, width)
	unsafe { text.free() }
	return result
}

fn (mut app DiskUtilityApp) build(size ui2.Rect) !ui2.Element {
	if !app.initialized { app.refresh() }
	width := if int(size.width) >= 640 { int(size.width) } else { 640 }
	height := if int(size.height) >= 460 { int(size.height) } else { 460 }
	mut rows := (height - 212) / 26
	if rows < 1 { rows = 1 }
	if rows > disk_utility_row_actions.len { rows = disk_utility_row_actions.len }
	app.visible_rows = rows
	app.clamp_selection(app.tab)
	mut children := frame_elements(80)
	children << ui2.label('', tr('app.disk_utility'), ui2.rect(12, 12, 220, 28), ui2.TextStyle{size: 18, bold: true, color: body_heading})
	children << ui2.button('disk_utility.refresh', tr('disk_utility.refresh'), ui2.rect(f64(width - 116), 12, 104, 28),
		ui2.BoxStyle{bg: settings_choice_bg, radius: 5}, ui2.TextStyle{size: 12, color: body_text, align: .center})
	children << ui2.label('', tr('disk_utility.read_only'), ui2.rect(12, 44, f64(width - 24), 20), ui2.TextStyle{size: 11, color: body_muted})
	for tab in 0 .. 2 {
		key := if tab == 0 { 'disk_utility.devices' } else { 'disk_utility.volumes' }
		children << ui2.button(key, tr(key), ui2.rect(f64(12 + tab * 130), 68, 122, 28),
			ui2.BoxStyle{bg: if app.tab == tab { app_accent } else { settings_choice_bg }, radius: 5},
			ui2.TextStyle{size: 12, color: if app.tab == tab { u32(0xffffff) } else { body_text }, align: .center})
	}
	count := app.count(app.tab)
	for slot in 0 .. rows {
		index := app.page[app.tab] + slot
		if index >= count { break }
		raw := if app.tab == 0 { app.devices[index].path } else { app.mounts[index].target }
		text := system_information_text(raw)
		children << ui2.Element{
			...ui2.button(frame_owned_text_id, text, ui2.rect(12, f64(104 + slot * 26), 254, 24),
				ui2.BoxStyle{bg: if index == app.selected[app.tab] { app_accent } else { settings_choice_bg }, radius: 3},
				ui2.TextStyle{size: 12, color: if index == app.selected[app.tab] { u32(0xffffff) } else { body_text }, align: .left})
			action_id: disk_utility_row_actions[slot]
			native_style: false
			tooltip: text
		}
	}
	if count == 0 {
		key := if app.tab == 0 {
			if app.devices_unavailable { 'disk_utility.devices_unavailable' } else { 'disk_utility.devices_empty' }
		} else { if app.mounts_unavailable { 'disk_utility.mounts_unavailable' } else { 'disk_utility.mounts_empty' } }
		children << ui2.label('', tr(key), ui2.rect(284, 104, f64(width - 296), 40), ui2.TextStyle{size: 12, color: body_muted})
	} else if app.tab == 0 {
		device := &app.devices[app.selected[0]]
		children << disk_utility_detail('disk_utility.device', device.path, 284, 104, width - 296)
		children << disk_utility_detail('disk_utility.kind', tr('disk_utility.block_device'), 284, 132, width - 296)
		children << disk_utility_size_detail('disk_utility.size', device.bytes, device.bytes > 0, 284, 160, width - 296)
		children << ui2.label('', tr('disk_utility.metadata_unavailable'), ui2.rect(284, 204, f64(width - 296), 80), ui2.TextStyle{size: 11, color: body_muted})
	} else {
		mount := &app.mounts[app.selected[1]]
		children << disk_utility_detail('disk_utility.mount', mount.target, 284, 104, width - 296)
		children << disk_utility_detail('disk_utility.source', mount.source, 284, 132, width - 296)
		children << disk_utility_detail('disk_utility.filesystem', mount.filesystem, 284, 160, width - 296)
		children << disk_utility_detail('disk_utility.options', mount.options, 284, 188, width - 296)
		children << disk_utility_size_detail('disk_utility.total', mount.capacity[0], mount.capacity_valid, 284, 224, width - 296)
		children << disk_utility_size_detail('disk_utility.used', mount.capacity[1], mount.capacity_valid, 284, 252, width - 296)
		children << disk_utility_size_detail('disk_utility.available', mount.capacity[2], mount.capacity_valid, 284, 280, width - 296)
	}
	children << ui2.button('disk_utility.previous', tr('disk_utility.previous'), ui2.rect(12, f64(height - 104), 94, 26),
		ui2.BoxStyle{bg: settings_choice_bg, radius: 4}, ui2.TextStyle{size: 11, color: body_text, align: .center})
	children << ui2.button('disk_utility.next', tr('disk_utility.next'), ui2.rect(114, f64(height - 104), 94, 26),
		ui2.BoxStyle{bg: settings_choice_bg, radius: 4}, ui2.TextStyle{size: 11, color: body_text, align: .center})
	if app.limited {
		children << ui2.label('', tr('disk_utility.limited'), ui2.rect(220, f64(height - 104), f64(width - 232), 26), ui2.TextStyle{size: 11, color: body_muted})
	}
	children << ui2.label('', tr('disk_utility.destination'), ui2.rect(12, f64(height - 74), 250, 18), ui2.TextStyle{size: 11, color: body_muted})
	children << disk_usage_path_field('disk_utility.path', disk_usage_buffer_text(app.report_path), 12, height - 54, width - 136, app.path_focus)
	children << ui2.button('disk_utility.export', tr('disk_utility.export'), ui2.rect(f64(width - 116), f64(height - 54), 104, 28),
		ui2.BoxStyle{bg: settings_choice_bg, radius: 5}, ui2.TextStyle{size: 12, color: body_text, align: .center})
	if app.report_status.len > 0 {
		children << ui2.label('', tr(app.report_status), ui2.rect(12, f64(height - 23), f64(width - 24), 20), ui2.TextStyle{size: 11, color: body_muted})
	}
	return ui2.view('disk_utility.body', ui2.rect(0, 0, f64(width), f64(height)), ui2.BoxStyle{bg: app_surface}, children)
}
