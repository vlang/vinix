// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Persistent taskbar pins use application process names so catalog reorderings
// do not turn a pinned icon into a different application.
module main

const taskbar_pins_filename = '.vinix-taskbar-pins'
const taskbar_pins_file_limit = 4096
const taskbar_pin_action_prefix = 'taskpin.'
const taskbar_pin_actions = ['taskpin.0', 'taskpin.1', 'taskpin.2', 'taskpin.3', 'taskpin.4',
	'taskpin.5', 'taskpin.6', 'taskpin.7', 'taskpin.8', 'taskpin.9', 'taskpin.10', 'taskpin.11',
	'taskpin.12', 'taskpin.13', 'taskpin.14', 'taskpin.15', 'taskpin.16', 'taskpin.17', 'taskpin.18',
	'taskpin.19', 'taskpin.20', 'taskpin.21', 'taskpin.22', 'taskpin.23', 'taskpin.24']

fn taskbar_pins_path(home string) string {
	return '${home}/${taskbar_pins_filename}'
}

fn load_taskbar_pins(home string) []int {
	path := taskbar_pins_path(home)
	info := desktop_stat(path) or {
		unsafe { path.free() }
		return []int{}
	}
	if info.size == 0 || info.size > u64(taskbar_pins_file_limit) {
		unsafe { path.free() }
		return []int{}
	}
	mut buffer := []u8{len: int(info.size)}
	got := desktop_read_file(path, buffer.data, info.size)
	unsafe { path.free() }
	if got <= 0 {
		unsafe { buffer.free() }
		return []int{}
	}
	mut pins := []int{cap: available_apps.len}
	mut start := 0
	for offset := 0; offset <= int(got); offset++ {
		if offset < int(got) && buffer[offset] != `\n` {
			continue
		}
		mut end := offset
		if end > start && buffer[end - 1] == `\r` {
			end--
		}
		if end > start {
			name := unsafe { tos(&u8(buffer.data) + start, end - start) }
			index := shortcut_app_index_named(name)
			if index >= 0 && !shortcut_order_contains(pins, index) {
				pins << index
			}
		}
		start = offset + 1
	}
	unsafe { buffer.free() }
	return pins
}

fn save_taskbar_pins(home string, pins []int) bool {
	mut bytes := []u8{cap: pins.len * 24}
	defer { unsafe { bytes.free() } }
	for index in pins {
		if index < 0 || index >= available_apps.len {
			return false
		}
		for ch in available_apps[index].process_name {
			bytes << ch
		}
		bytes << `\n`
	}
	path := taskbar_pins_path(home)
	defer { unsafe { path.free() } }
	data := if bytes.len > 0 { voidptr(bytes.data) } else { voidptr(unsafe { nil }) }
	return desktop_write_file(path, data, u64(bytes.len))
}

fn (d &Desktop) taskbar_is_pinned(index int) bool {
	return shortcut_order_contains(d.pinned_apps, index)
}

fn (mut d Desktop) pin_taskbar_app_in(home string, index int) bool {
	if index < 0 || index >= available_apps.len || d.taskbar_is_pinned(index) {
		return false
	}
	d.pinned_apps << index
	if !save_taskbar_pins(home, d.pinned_apps) {
		d.pinned_apps.delete(d.pinned_apps.len - 1)
		return false
	}
	d.dirty = true
	return true
}

fn (mut d Desktop) unpin_taskbar_app_in(home string, index int) bool {
	for slot, pinned in d.pinned_apps {
		if pinned != index {
			continue
		}
		d.pinned_apps.delete(slot)
		if !save_taskbar_pins(home, d.pinned_apps) {
			d.pinned_apps.insert(slot, index)
			return false
		}
		d.dirty = true
		return true
	}
	return false
}

fn (d &Desktop) taskbar_window_for_app(index int) int {
	for window_index := d.windows.len - 1; window_index >= 0; window_index-- {
		if d.windows[window_index].factory_index == index {
			return d.windows[window_index].id
		}
	}
	return 0
}
