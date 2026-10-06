// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

struct WindowActionsCloseApp {
mut:
	allow_close bool
	close_calls int
}

fn (mut _ WindowActionsCloseApp) build(_ ui2.Rect) !ui2.Element { return ui2.Element{} }

fn (mut _ WindowActionsCloseApp) handle(_ string) ! {}

fn (mut app WindowActionsCloseApp) prepare_close() bool {
	app.close_calls++
	return app.allow_close
}

fn actions_fixture() Desktop {
	return Desktop{ canvas: Canvas{ width: 800, height: 600 } }
}

fn actions_frame(desktop &Desktop, id int) WindowActionFrame {
	index := desktop.window_index(id) or { panic('missing action window') }
	return window_action_frame(&desktop.windows[index])
}

fn actions_start(mut desktop Desktop, id int, mode WindowActionMode) {
	desktop.open_window_actions(id)
	assert desktop.window_actions.active
	desktop.apply_window_action(if mode == .move { 0 } else { 1 })
	assert desktop.window_actions.mode == mode
}

fn actions_target(desktop &Desktop, action string) HitTarget {
	for target in desktop.targets {
		if target.action_id == action { return target }
	}
	panic('missing action target: ${action}')
}

fn test_window_menu_chords_preserve_app_input_and_handle_fragmented_reads() {
	for chord in [key_window_actions, key_window_actions_legacy] {
		for split in 1 .. chord.len {
			mut desktop := actions_fixture()
			desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
			assert desktop.take_window_actions_keys(chord[..split]) == ''
			assert !desktop.window_actions.active
			assert desktop.take_window_actions_keys(chord[split..]) == ''
			assert desktop.window_actions.active
			assert desktop.window_actions.pending_len == 0
		}
	}
	mut desktop := actions_fixture()
	desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	assert desktop.take_window_actions_keys('ordinary') == 'ordinary'
	assert desktop.take_window_actions_keys('\x1b[A') == '\x1b[A'
	assert desktop.take_window_actions_keys('a\x1b[1;5Ab') == 'a\x1b[1;5Ab'
	assert desktop.take_window_actions_keys('\x1b[') == ''
	malformed := desktop.take_window_actions_keys('unexpected')
	assert malformed == '\x1b[unexpected'
	unsafe { malformed.free() }
	before := desktop.take_window_actions_keys('before' + key_window_actions + 'queued typing')
	assert before == 'before'
	unsafe { before.free() }
	assert desktop.window_actions.active
	assert desktop.take_window_actions_keys('\x1b[57442;1:3u') == ''
	assert desktop.window_actions.active
	assert desktop.take_window_actions_keys('\x1b') == ''
	assert desktop.take_window_actions_keys('') == ''
	assert !desktop.window_actions.active
}

fn test_keyboard_move_precise_steps_accept_and_cancel_restore_full_frame() {
	mut desktop := actions_fixture()
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	before := actions_frame(&desktop, id)
	actions_start(mut desktop, id, .move)
	assert desktop.take_window_actions_keys('\x1b[C\x1b[B\x1b[1;2D\x1b[1;2A') == ''
	frame := actions_frame(&desktop, id)
	assert frame.x == before.x + 9
	assert frame.y == before.y + 9
	assert frame.width == before.width && frame.height == before.height
	assert desktop.take_window_actions_keys('\rqueued') == ''
	assert !desktop.window_actions.active
	accepted := actions_frame(&desktop, id)
	assert accepted.restore_x == accepted.x
	assert accepted.restore_y == accepted.y
	actions_start(mut desktop, id, .move)
	assert desktop.take_window_actions_keys('\x1b[C') == ''
	assert desktop.window_actions_pointer_down(window_actions_dismiss, .desktop)
	assert actions_frame(&desktop, id) == accepted
	assert !desktop.window_actions.active
}

fn test_arranged_move_and_resize_cancel_restore_snap_and_restore_metadata() {
	for snap in [WindowSnap.left, .top_right, .bottom_left] {
		for mode in [WindowActionMode.move, .resize] {
			mut desktop := actions_fixture()
			id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
			desktop.snap_window(id, snap)
			before := actions_frame(&desktop, id)
			actions_start(mut desktop, id, mode)
			assert actions_frame(&desktop, id).snap == .none_
			assert desktop.take_window_actions_keys('\x1b[C\x1b[B') == ''
			assert desktop.take_window_actions_keys('\x1b') == ''
			assert desktop.take_window_actions_keys('') == ''
			assert actions_frame(&desktop, id) == before
		}
	}
	mut desktop := actions_fixture()
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	desktop.maximize(id)
	before := actions_frame(&desktop, id)
	actions_start(mut desktop, id, .resize)
	assert !actions_frame(&desktop, id).maximized
	assert desktop.take_window_actions_keys('\x1b[1;2C\x1b[1;2B') == ''
	desktop.close_window_actions()
	assert actions_frame(&desktop, id) == before
}

fn test_keyboard_resize_anchors_top_left_and_enforces_minimum_and_work_area() {
	mut desktop := actions_fixture()
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	actions_start(mut desktop, id, .resize)
	assert desktop.take_window_actions_keys('\x1b[C\x1b[B\x1b[1;2D') == ''
	frame := actions_frame(&desktop, id)
	assert frame.x == 120 && frame.y == 80
	assert frame.width == 409 && frame.height == 270
	for _ in 0 .. 100 { desktop.step_window_action_geometry(-1, -1, false) }
	minimum := actions_frame(&desktop, id)
	assert minimum.width == window_min_width
	assert minimum.height == desktop.theme().title_height + window_min_body_height
	for _ in 0 .. 100 { desktop.step_window_action_geometry(1, 1, false) }
	maximum := actions_frame(&desktop, id)
	assert maximum.x + maximum.width == desktop.canvas.width
	assert maximum.y + maximum.height == desktop_usable_height(desktop.canvas.height)
	desktop.accept_window_action_geometry()
	accepted := actions_frame(&desktop, id)
	assert accepted.restore_width == accepted.width
	assert accepted.restore_height == accepted.height
	assert !desktop.window_actions.active
}

fn test_keyboard_move_keeps_title_bar_reachable_and_cancellation_does_not_focus_stale_anchor() {
	mut desktop := actions_fixture()
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	actions_start(mut desktop, id, .move)
	for _ in 0 .. 100 { desktop.step_window_action_geometry(1, -1, false) }
	frame := actions_frame(&desktop, id)
	assert frame.y == 0
	assert frame.x == desktop.canvas.width - 60
	for _ in 0 .. 150 { desktop.step_window_action_geometry(-1, 1, false) }
	frame2 := actions_frame(&desktop, id)
	assert frame2.x + frame2.width == 60
	assert frame2.y + desktop.theme().title_height == desktop_usable_height(desktop.canvas.height)
	desktop.close_window_actions()
	other := desktop.spawn('System', .system, 220, 80, 400, 260)
	actions_start(mut desktop, id, .move)
	desktop.close_window(id)
	desktop.raise(other)
	assert desktop.take_window_actions_keys('\x1b[Cqueued') == ''
	assert !desktop.window_actions.active
	assert desktop.focus == other
}

fn test_menu_actions_minimize_restore_arrange_migrate_and_guard_closing() {
	mut desktop := actions_fixture()
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	desktop.open_window_actions(id)
	desktop.apply_window_action(3)
	assert actions_frame(&desktop, id).maximized
	desktop.open_window_actions(id)
	assert desktop.window_action_label(3) == tr('window.layout.restore')
	desktop.apply_window_action(3)
	assert !actions_frame(&desktop, id).maximized
	desktop.snap_window(id, .left)
	desktop.open_window_actions(id)
	desktop.apply_window_action(3)
	assert actions_frame(&desktop, id).snap == .none_
	desktop.open_window_actions(id)
	desktop.apply_window_action(4)
	assert desktop.window_layout.active && !desktop.window_actions.active
	desktop.close_window_layout()
	desktop.open_window_actions(id)
	desktop.apply_window_action(6)
	index := desktop.window_index(id) or { panic('missing migrated window') }
	assert desktop.windows[index].workspace == 1
	assert !desktop.window_actions.active
	desktop.switch_workspace(1)
	desktop.open_window_actions(id)
	desktop.apply_window_action(2)
	assert desktop.windows[index].minimized
	desktop.activate(id)
	mut app := &WindowActionsCloseApp{}
	desktop.apps << app
	desktop.windows[index].app_index = desktop.apps.len - 1
	desktop.open_window_actions(id)
	desktop.apply_window_action(9)
	assert app.close_calls == 1
	assert desktop.window_index(id) != none
	assert !desktop.window_actions.active
	app.allow_close = true
	desktop.open_window_actions(id)
	desktop.apply_window_action(9)
	assert app.close_calls == 2
	assert desktop.window_index(id) == none
}

fn test_titlebar_right_click_and_menu_hit_targets_are_modal_and_page_on_small_screens() {
	mut desktop := Desktop{ canvas: Canvas{ width: 320, height: 240 } }
	id := desktop.spawn('Welcome', .welcome, 30, 20, 240, 160)
	index := desktop.window_index(id) or { panic('missing menu window') }
	desktop.targets << HitTarget{ action_id: desktop.windows[index].id_titlebar, x: 30, y: 20, width: 240, height: desktop.theme().title_height }
	assert desktop.window_actions_right_down(140, 32)
	assert desktop.window_actions.active
	assert desktop.window_layout_right_release
	bounds := desktop.window_actions_bounds()
	assert bounds.valid && bounds.rows < window_actions_ids.len
	assert bounds.x >= 0 && bounds.y >= 0
	assert bounds.x + bounds.width <= desktop.canvas.width
	assert bounds.y + bounds.height <= desktop_usable_height(desktop.canvas.height)
	root := desktop.build_tree()
	desktop.targets.clear()
	desktop.record_subtree_targets(&root, 0, 0, desktop.canvas.width, desktop.canvas.height)
	move := actions_target(&desktop, window_actions_ids[0])
	desktop.on_pointer_down(move.x + 10, move.y + 10)
	assert desktop.window_actions.mode == .move
	assert desktop.chrome_pointer_capture
	free_tree(root)
	desktop.close_window_actions()
	desktop.open_window_actions(id)
	assert desktop.window_actions_pointer_down(window_actions_next, .desktop)
	assert desktop.window_actions.page == 1
	assert desktop.window_actions.selected == bounds.rows
	assert desktop.window_actions_pointer_down(window_actions_previous, .desktop)
	assert desktop.window_actions.page == 0
	assert desktop.window_actions_pointer_down('arbitrary.app.selector', .application)
	assert !desktop.window_actions.active
}

fn test_menu_keyboard_navigation_and_replacement_modals_cancel_geometry() {
	mut desktop := actions_fixture()
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	before := actions_frame(&desktop, id)
	desktop.open_window_actions(id)
	assert desktop.take_window_actions_keys('\x1b[B\r') == ''
	assert desktop.window_actions.mode == .resize
	assert desktop.take_window_actions_keys('\x1b[C') == ''
	assert desktop.take_window_actions_keys(key_window_overview) == ''
	assert desktop.overview.active && !desktop.window_actions.active
	assert actions_frame(&desktop, id) == before
	desktop.close_window_overview()
	actions_start(mut desktop, id, .move)
	assert desktop.take_window_actions_keys('\x1b[C') == ''
	assert desktop.take_window_actions_keys(key_super_z) == ''
	assert desktop.window_layout.active && !desktop.window_actions.active
	assert actions_frame(&desktop, id) == before
}

fn test_display_scale_cancels_keyboard_geometry_before_translating_original_frame() {
	previous_width := desktop_physical_width
	previous_height := desktop_physical_height
	previous_requested := desktop_requested_scale()
	previous_applied := desktop_current_scale()
	defer {
		desktop_physical_width = previous_width
		desktop_physical_height = previous_height
		desktop_request_scale(previous_requested)
		desktop_commit_scale(previous_applied)
	}
	for mode in [WindowActionMode.move, .resize] {
		for arrangement in 0 .. 4 {
			desktop_configure_scale(800, 600)
			mut desktop := Desktop{
				canvas: new_scaled_canvas(800, 600, 800, 600, desktop_scale_100)
			}
			id := desktop.spawn('Scale anchor', .welcome, 120, 80, 240, 160)
			match arrangement {
				1 { desktop.snap_window(id, .right) }
				2 { desktop.snap_window(id, .bottom_right) }
				3 { desktop.maximize(id) }
				else {}
			}
			actions_start(mut desktop, id, mode)
			desktop.step_window_action_geometry(1, 1, false)
			desktop_request_scale(desktop_scale_200)
			desktop.apply_requested_scale()
			assert !desktop.window_actions.active
			assert desktop.canvas.width == 400 && desktop.canvas.height == 300
			assert desktop_current_scale() == desktop_scale_200
			frame := actions_frame(&desktop, id)
			// Cancellation restores the original state; then the normal scale
			// policy translates it. The transient 10px move/resize must vanish.
			assert frame.restore_x == 60 && frame.restore_y == 40
			assert frame.restore_width == 240 && frame.restore_height == 160
			if arrangement == 0 {
				assert frame.x == 60 && frame.y == 40
				assert frame.width == 240 && frame.height == 160
				assert frame.snap == .none_ && !frame.maximized
			} else if arrangement == 3 {
				assert frame.x == 0 && frame.y == 0
				assert frame.width == 400 && frame.height == desktop_usable_height(300)
				assert frame.maximized && frame.snap == .none_
			} else {
				snap := if arrangement == 1 { WindowSnap.right } else { WindowSnap.bottom_right }
				expected := window_placement_frame(WindowPlacement{ snap: snap }, 400, 300)
				assert frame.snap == snap && !frame.maximized
				assert frame.x == expected.x && frame.y == expected.y
				assert frame.width == expected.w && frame.height == expected.h
			}
			desktop.close_window(id)
			unsafe {
				free(voidptr(desktop.canvas.pixels))
				desktop.windows.free()
			}
		}
	}
}
