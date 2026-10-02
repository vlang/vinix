// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Persistent taskbar pins use application process names so catalog reorderings
// do not turn a pinned icon into a different application.
module main

const taskbar_pins_filename = '.vinix-taskbar-pins'
const taskbar_pin_action_prefix = 'taskpin.'
const taskbar_pin_actions = ['taskpin.0', 'taskpin.1', 'taskpin.2', 'taskpin.3', 'taskpin.4',
	'taskpin.5', 'taskpin.6', 'taskpin.7', 'taskpin.8', 'taskpin.9', 'taskpin.10', 'taskpin.11',
	'taskpin.12', 'taskpin.13', 'taskpin.14', 'taskpin.15', 'taskpin.16', 'taskpin.17', 'taskpin.18',
	'taskpin.19', 'taskpin.20', 'taskpin.21', 'taskpin.22', 'taskpin.23', 'taskpin.24',
	'taskpin.25', 'taskpin.26', 'taskpin.27']

fn taskbar_pins_path(home string) string {
	return '${home}/${taskbar_pins_filename}'
}

fn load_taskbar_pins(home string) []int {
	path := taskbar_pins_path(home)
	defer { unsafe { path.free() } }
	return load_app_name_list(path, available_apps.len)
}

fn save_taskbar_pins(home string, pins []int) bool {
	path := taskbar_pins_path(home)
	defer { unsafe { path.free() } }
	return save_app_name_list(path, pins)
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
