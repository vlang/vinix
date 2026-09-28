// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn test_taskbar_pin_persists_and_stays_after_window_closes() {
	assert taskbar_pin_actions.len == available_apps.len
	home := os.join_path(os.temp_dir(), 'vinix-taskbar-pin-test-${os.getpid()}')
	os.mkdir_all(home) or { panic(err) }
	defer { os.rmdir_all(home) or {} }
	mut desktop := Desktop{
		canvas: Canvas{
			width:  1280
			height: 720
		}
	}
	assert desktop.pin_taskbar_app_in(home, 3)
	assert load_taskbar_pins(home) == [3]
	window_id := desktop.spawn('Terminal', .welcome, 10, 10, 300, 200)
	desktop.windows[0].factory_index = 3
	entries := desktop.taskbar_entries()
	assert entries.len == 1
	assert entries[0].id == taskbar_pin_actions[3]
	assert entries[0].window_id == window_id
	unsafe { entries.free() }
	second_id := desktop.spawn('Terminal', .welcome, 30, 30, 300, 200)
	desktop.windows[1].factory_index = 3
	multiple := desktop.taskbar_entries()
	assert multiple.len == 1
	assert multiple[0].window_id == second_id
	unsafe { multiple.free() }
	desktop.close_window(window_id)
	desktop.close_window(second_id)
	closed := desktop.taskbar_entries()
	assert closed.len == 1
	assert closed[0].window_id == 0
	unsafe { closed.free() }
	desktop.targets << HitTarget{
		action_id: taskbar_pin_actions[3]
		world:     .desktop
		x:         60
		y:         680
		width:     120
		height:    40
	}
	assert desktop.open_create_context_menu(80, 700)
	assert create_context_menu.target == .taskbar
	assert create_context_menu.taskbar_window_id == 0
	desktop.close_create_context_menu()
	assert desktop.unpin_taskbar_app_in(home, 3)
	assert load_taskbar_pins(home).len == 0
	empty := desktop.taskbar_entries()
	assert empty.len == 0
	unsafe { empty.free() }
}

fn test_taskbar_right_click_opens_pin_menu_for_app() {
	mut desktop := Desktop{
		canvas: Canvas{
			width:  1280
			height: 720
		}
	}
	id := desktop.spawn('Terminal', .welcome, 10, 10, 300, 200)
	desktop.windows[0].factory_index = 3
	desktop.targets << HitTarget{
		action_id: desktop.windows[0].id_task
		world:     .desktop
		x:         60
		y:         680
		width:     120
		height:    40
	}
	assert desktop.open_create_context_menu(80, 700)
	assert create_context_menu.target == .taskbar
	assert create_context_menu.app_index == 3
	assert create_context_menu.taskbar_window_id == id
	assert create_context_menu.y + context_menu_height(.taskbar, true) <= desktop.canvas.height
	desktop.close_create_context_menu()
}
