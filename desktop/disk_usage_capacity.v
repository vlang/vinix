// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

// A scan can cross mount points. These figures describe only the filesystem
// containing its root, independently of the logical bytes in the inventory.
struct DiskUsageCapacity {
	valid     bool
	total     u64
	used      u64
	free      u64
	available u64
}

fn disk_usage_capacity(unit u64, blocks u64, free u64, available u64) DiskUsageCapacity {
	if unit == 0 || blocks == 0 || free > blocks || available > free
		|| blocks > ~u64(0) / unit {
		return DiskUsageCapacity{}
	}
	return DiskUsageCapacity{
		valid: true
		total: blocks * unit
		used: (blocks - free) * unit
		free: free * unit
		available: available * unit
	}
}

fn disk_usage_read_capacity(path string) DiskUsageCapacity {
	mut stats := C.vinix_system_information_statvfs{}
	if unsafe { C.vinix_system_information_statvfs(&char(path.str), &stats) } != 0 {
		return DiskUsageCapacity{}
	}
	unit := if stats.f_frsize > 0 { u64(stats.f_frsize) } else { u64(stats.f_bsize) }
	return disk_usage_capacity(unit, stats.f_blocks, stats.f_bfree, stats.f_bavail)
}

fn (a &DiskUsageApp) view_buttons(mut children []ui2.Element, y int) {
	for index, action in [disk_usage_action_inventory, disk_usage_action_capacity]! {
		selected := a.capacity_view == (index == 1)
		children << ui2.button(action, tr(action), ui2.rect(f64(disk_usage_pad + index * 114),
			f64(y), if index == 0 { 108 } else { 156 }, 18), ui2.BoxStyle{
			bg: if selected { app_accent } else { body_panel }
			radius: 4
		}, ui2.TextStyle{
			color: if selected { app_on_accent } else { body_text }
			size: 11
			align: .center
		})
	}
}

fn disk_usage_capacity_value(capacity &DiskUsageCapacity, value u64) string {
	return if capacity.valid { disk_usage_size_text(value) }
		else { tr('disk_usage.capacity.unavailable').clone() }
}

fn (mut a DiskUsageApp) build_capacity(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)
	inner := width - disk_usage_pad * 2
	mut children := frame_elements(18)
	if width < 360 || height < 250 {
		children << ui2.label('', 'Disk Usage', ui2.rect(12, 8, f64(inner), 26),
			ui2.TextStyle{color: body_heading, size: 18, bold: true})
		children << disk_usage_button(disk_usage_action_inventory, tr('disk_usage.view.inventory'),
			12, 42, inner, true)
		children << ui2.label('', tr('disk_usage.capacity.resize'), ui2.rect(12, 72, f64(inner), 18),
			ui2.TextStyle{color: body_muted, size: 11})
		return ui2.screen(app_surface, children)
	}
	children << ui2.label('', 'Disk Usage', ui2.rect(12, 8, 160, 26),
		ui2.TextStyle{color: body_heading, size: 18, bold: true})
	children << disk_usage_button(disk_usage_action_rescan, tr('disk_usage.button.rescan'),
		width - 108, 8, 96, true)
	children << ui2.label('', tr('disk_usage.capacity.scope'), ui2.rect(12, 42, f64(inner), 18),
		ui2.TextStyle{color: body_muted, size: 11})
	children << ui2.label('', a.scanner.root, ui2.rect(12, 64, f64(inner), 18),
		ui2.TextStyle{color: body_text, size: 12})
	a.view_buttons(mut children, 90)
	capacity := &a.scanner.capacity
	keys := ['disk_usage.capacity.total', 'disk_usage.capacity.used',
		'disk_usage.capacity.free', 'disk_usage.capacity.available']!
	values := [capacity.total, capacity.used, capacity.free, capacity.available]!
	columns := if width >= 640 { 4 } else { 2 }
	gap := 10
	metric_width := (inner - gap * (columns - 1)) / columns
	for index, key in keys {
		children << disk_usage_metric(tr(key), disk_usage_capacity_value(capacity, values[index]),
			12 + (metric_width + gap) * (index % columns),
			112 + 72 * (index / columns), metric_width, app_accent)
	}
	notes_y := if columns == 4 { 194 } else { 262 }
	for index, key in ['disk_usage.capacity.refresh', 'disk_usage.capacity.available_note',
		'disk_usage.capacity.inventory_note']! {
		if notes_y + index * 22 + 18 <= height - 12 {
			children << ui2.label('', tr(key), ui2.rect(12, f64(notes_y + index * 22), f64(inner), 18),
				ui2.TextStyle{color: body_muted, size: 11})
		}
	}
	return ui2.screen(app_surface, children)
}
