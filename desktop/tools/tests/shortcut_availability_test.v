// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn test_shortcuts_only_render_installed_apps_without_gaps_or_changed_actions() {
	mut desktop := Desktop{
		canvas:         Canvas{ width: 1024, height: 768 }
		shortcut_order: default_shortcut_order()
	}
	defer { unsafe { desktop.shortcut_order.free() } }
	// A saved order can put unavailable apps before the native utilities.
	desktop.shortcut_order.reverse_in_place()
	begin_frame_elements()
	icons := desktop.shortcut_elements()
	defer {
		for icon in icons { free_tree(icon) }
	}
	rows := shortcut_rows_for_height(desktop.canvas.height, desktop.taskbar_height())
	assert desktop.shortcut_order_slot_for_visible_slot(-1) == -1
	mut visible := 0
	for slot, index in desktop.shortcut_order {
		if !available_apps[index].shortcut_available() { continue }
		assert icons[visible].id == app_shortcut_actions[index]
		assert icons[visible].frame.x == f64(shortcut_left + visible / rows * (shortcut_width + shortcut_gap))
		assert icons[visible].frame.y == f64(shortcut_top + visible % rows * (shortcut_height + shortcut_gap))
		assert desktop.shortcut_order_slot_for_visible_slot(visible) == slot
		visible++
	}
	assert icons.len == visible
	assert icons.any(it.id == app_shortcut_actions[0]) // Files
	assert icons.any(it.id == app_shortcut_actions[2]) // Native Calculator
	if !shortcut_executable('/usr/bin/minecraft') {
		assert !icons.any(it.id == app_shortcut_actions[9])
		assert !desktop.begin_shortcut_press(app_shortcut_actions[9], 10, 10)
	}
	// Missing standalone apps must not be represented by multicall adapters.
	for app in available_apps {
		if app.standalone {
			path := '/usr/bin/${app.process_name}'
			defer { unsafe { path.free() } }
			assert app.shortcut_available() == shortcut_executable(path)
		}
	}
}

fn test_shortcut_drag_uses_visible_positions_and_keeps_uninstalled_order_entries() {
	root := os.join_path(os.temp_dir(), 'vinix-shortcut-availability-${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	mut desktop := Desktop{
		canvas:         Canvas{ width: 1024, height: 768 }
		shortcut_order: default_shortcut_order()
	}
	defer { unsafe { desktop.shortcut_order.free() } }
	target := desktop.shortcut_order_slot_for_visible_slot(3)
	assert target >= 3
	assert desktop.begin_shortcut_press(app_shortcut_actions[0], shortcut_left + 2, shortcut_top + 2)
	assert (desktop.finish_shortcut_press_in(root, app_shortcut_actions[0], shortcut_left + 2,
		shortcut_top + 3 * (shortcut_height + shortcut_gap) + 2) or { -1 }) == -1
	assert desktop.shortcut_slot_for_app(0) == target
	assert desktop.shortcut_order.len == available_apps.len
	loaded := load_shortcut_order(root)
	defer { unsafe { loaded.free() } }
	assert loaded == desktop.shortcut_order
	for index in 0 .. available_apps.len {
		assert shortcut_order_contains(loaded, index)
	}
}

fn test_shortcut_probe_requires_execute_permission_and_tracks_install_removal() {
	path := os.join_path(os.temp_dir(), 'vinix-shortcut-probe-${os.getpid()}')
	defer { os.rm(path) or {} }
	assert !shortcut_executable(path)
	os.write_file(path, 'fixture')!
	os.chmod(path, 0o600)!
	assert shortcut_readable(path)
	assert !shortcut_executable(path)
	os.chmod(path, 0o700)!
	assert shortcut_executable(path)
	os.rm(path)!
	assert !shortcut_executable(path)
}
