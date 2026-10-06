// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

struct OverviewPointerTestApp {
mut:
	presses          int
	releases         int
	released_buttons u32
}

fn (mut app OverviewPointerTestApp) build(_ ui2.Rect) !ui2.Element {
	return ui2.screen(0, [])
}

fn (mut app OverviewPointerTestApp) handle(_ string) ! {}

fn (mut app OverviewPointerTestApp) pointer_input_enabled() bool {
	return true
}

fn (mut app OverviewPointerTestApp) pointer_event(phase AppPointerPhase, button AppPointerButton, _ int, _ int, _ int, _ int, _ int) {
	if phase == .down {
		app.presses++
	} else if phase == .up {
		app.releases++
		app.released_buttons |= match button {
			.left { button_left }
			.right { button_right }
			.middle { button_middle }
			.back { button_back }
			.no_button { u32(0) }
		}
	}
}

fn overview_fixture() Desktop {
	return Desktop{ canvas: Canvas{ width: 1024, height: 768 } }
}

fn test_keyboard_opened_modals_cancel_held_app_buttons_and_consume_real_releases() {
	for layout in [false, true] {
		for held in [button_left, button_right, button_middle, button_back,
			button_left | button_right | button_middle | button_back] {
			mut desktop := overview_fixture()
			desktop.apps << OverviewPointerTestApp{}
			id := desktop.spawn('Pointer surface', .app, 120, 80, 400, 260)
			index := desktop.window_index(id) or { panic('missing pointer window') }
			desktop.windows[index].app_index = 0
			desktop.buttons = held
			if held & button_left != 0 {
				desktop.on_pointer_down(200, 160)
			}
			if held & button_right != 0 {
				desktop.on_app_pointer_button(200, 160, .down, .right)
			}
			if held & button_middle != 0 {
				desktop.on_app_pointer_button(200, 160, .down, .middle)
			}
			if held & button_back != 0 {
				desktop.on_app_pointer_button(200, 160, .down, .back)
			}
			presses := if held == button_left | button_right | button_middle | button_back {
				4
			} else {
				1
			}
			assert desktop.pointer_capture == id
			if layout {
				assert desktop.take_window_layout_keys(key_super_z) == ''
				assert desktop.window_layout.active
			} else {
				assert desktop.take_window_overview_keys(key_window_overview) == ''
				assert desktop.overview.active
			}
			assert desktop.buttons == held
			assert desktop.pointer_capture == 0
			before_release := desktop.apps[0]
			if before_release is OverviewPointerTestApp {
				assert before_release.presses == presses
				assert before_release.releases == presses
				assert before_release.released_buttons == held
			} else {
				panic('missing pointer fixture')
			}
			desktop.buttons = 0
			desktop.on_pointer_move(200, 160)
			desktop.on_pointer_up(200, 160)
			desktop.on_app_pointer_button(200, 160, .up, .right)
			desktop.on_app_pointer_button(200, 160, .up, .middle)
			desktop.on_app_pointer_button(200, 160, .up, .back)
			assert desktop.overview.active || desktop.window_layout.active
			assert desktop.pointer_capture == 0
			assert !desktop.chrome_pointer_capture
			assert desktop.drag.kind == .none_
			app := desktop.apps[0]
			if app is OverviewPointerTestApp {
				assert app.presses == presses
				assert app.releases == presses
				assert app.released_buttons == held
			} else {
				panic('missing pointer fixture')
			}
		}
	}
}

fn overview_named(element ui2.Element, id string) ?ui2.Element {
	if element.id == id {
		return element
	}
	for child in element.children {
		found := overview_named(child, id) or { continue }
		return found
	}
	return none
}

fn overview_has_image(element ui2.Element, path string) bool {
	if element.image_path == path {
		return true
	}
	for child in element.children {
		if overview_has_image(child, path) {
			return true
		}
	}
	return false
}

fn overview_targets(mut desktop Desktop) ui2.Element {
	root := desktop.build_tree()
	desktop.targets.clear()
	desktop.record_subtree_targets(&root, 0, 0, desktop.canvas.width, desktop.canvas.height)
	return root
}

fn overview_target(desktop &Desktop, action string) HitTarget {
	for target in desktop.targets {
		if target.action_id == action {
			return target
		}
	}
	panic('missing overview target: ${action}')
}

fn test_overview_includes_minimized_windows_and_filters_workspaces() {
	mut desktop := overview_fixture()
	one := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	two := desktop.spawn('System', .system, 210, 110, 400, 260)
	desktop.minimize(one)
	desktop.switch_workspace(1)
	other := desktop.spawn('Notes', .notes, 120, 80, 400, 260)
	desktop.switch_workspace(0)
	index := desktop.window_index(two) or { panic('missing thumbnail window') }
	desktop.windows[index].thumbnail = []u32{len: 8, init: 0x123456}
	desktop.windows[index].thumbnail_width = 4
	desktop.windows[index].thumbnail_height = 2
	desktop.windows[index].thumbnail_scale = 1
	thumb := desktop.windows[index].thumbnail.data
	desktop.open_window_overview()
	assert desktop.overview.active
	assert desktop.window_overview_count() == 2
	assert desktop.window_overview_position(other) == none
	root := overview_targets(mut desktop)
	assert overview_named(root, window_overview_panel) != none
	for id in [one, two] {
		window_index := desktop.window_index(id) or { panic('missing overview window') }
		assert overview_named(root, desktop.windows[window_index].id_preview) != none
	}
	assert overview_has_image(root, desktop.windows[index].id_thumbnail)
	assert overview_has_image(root, 'builtin:window')
	assert desktop.windows[index].thumbnail.data == thumb
	assert desktop.windows[index].thumbnail.len == 8
	free_tree(root)
}

fn test_overview_keyboard_selection_opens_minimized_window_and_owns_typing() {
	mut desktop := overview_fixture()
	one := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	two := desktop.spawn('System', .system, 210, 110, 400, 260)
	desktop.minimize(one)
	assert desktop.take_window_overview_keys(key_window_overview) == ''
	assert desktop.overview.active
	assert desktop.overview.selected_id == two
	assert desktop.take_window_overview_keys('\x1b[C') == ''
	assert desktop.overview.selected_id == one
	assert desktop.take_window_overview_keys('text') == ''
	assert desktop.take_window_overview_keys('\rqueued typing') == ''
	assert !desktop.overview.active
	assert desktop.focus == one
	index := desktop.window_index(one) or { panic('missing activated window') }
	assert !desktop.windows[index].minimized
	assert desktop.take_window_overview_keys('ordinary') == 'ordinary'
	assert desktop.take_window_overview_keys('\x1b[A') == '\x1b[A'
	assert desktop.take_window_overview_keys('a\x1b[1;5Ab') == 'a\x1b[1;5Ab'
}

fn test_overview_toggle_handles_every_fragment_boundary_and_escape_dismisses() {
	for split in 1 .. key_window_overview.len {
		mut desktop := overview_fixture()
		desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
		assert desktop.take_window_overview_keys(key_window_overview[..split]) == ''
		assert !desktop.overview.active
		assert desktop.take_window_overview_keys(key_window_overview[split..]) == ''
		assert desktop.overview.active
		assert desktop.overview.pending_len == 0
		assert desktop.take_window_overview_keys('\x1b') == ''
		assert desktop.take_window_overview_keys('') == ''
		assert !desktop.overview.active
	}
	mut desktop := overview_fixture()
	assert desktop.take_window_overview_keys('\x1b[') == ''
	assert desktop.take_window_overview_keys('unexpected') == '\x1b[unexpected'
	assert !desktop.overview.active
	assert desktop.take_window_overview_keys('\x1b') == ''
	assert desktop.take_window_overview_keys('') == '\x1b'
}

fn test_overview_opens_from_taskbar_and_clicks_restore_without_forwarding() {
	mut desktop := overview_fixture()
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	desktop.minimize(id)
	mut root := overview_targets(mut desktop)
	button := overview_target(&desktop, action_window_overview)
	desktop.on_pointer_down(button.x + button.width / 2, button.y + button.height / 2)
	assert desktop.overview.active
	free_tree(root)
	root = overview_targets(mut desktop)
	index := desktop.window_index(id) or { panic('missing clicked window') }
	card := overview_target(&desktop, desktop.windows[index].id_preview)
	desktop.on_pointer_down(card.x + card.width / 2, card.y + card.height / 2)
	assert !desktop.overview.active
	assert desktop.focus == id
	assert !desktop.windows[index].minimized
	assert desktop.chrome_pointer_capture
	free_tree(root)
	desktop.open_window_overview()
	assert desktop.window_overview_pointer_down(window_overview_dismiss, .desktop)
	assert !desktop.overview.active
}

fn test_overview_workspace_buttons_refresh_cards_and_ignore_stale_window_ids() {
	mut desktop := overview_fixture()
	one := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	two := desktop.spawn('System', .system, 210, 110, 400, 260)
	desktop.open_window_overview()
	assert desktop.window_overview_pointer_down(window_overview_workspace_ids[1], .desktop)
	assert desktop.current_workspace == 1
	assert desktop.overview.active
	assert desktop.window_overview_count() == 0
	assert desktop.overview.selected_id == 0
	assert desktop.window_overview_pointer_down(window_overview_workspace_ids[0], .desktop)
	assert desktop.window_overview_count() == 2
	assert desktop.overview.selected_id == two
	index := desktop.window_index(two) or { panic('missing stale window') }
	action := desktop.windows[index].id_preview.clone()
	desktop.close_window(two)
	assert desktop.window_overview_pointer_down(action, .desktop)
	assert desktop.overview.active
	assert desktop.overview.selected_id == one
	assert desktop.focus == one
	unsafe { action.free() }
	desktop.close_window(one)
	desktop.reconcile_window_overview()
	assert desktop.overview.selected_id == 0
}

fn test_overview_pages_keep_every_window_reachable_with_bounded_layout() {
	mut desktop := Desktop{ canvas: Canvas{ width: 640, height: 480 } }
	for _ in 0 .. 25 {
		desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	}
	desktop.open_window_overview()
	layout := window_overview_layout(desktop.canvas.width, desktop.canvas.height)
	assert layout.capacity() > 0
	assert layout.width + layout.x <= desktop.canvas.width
	assert layout.height + layout.y <= desktop_usable_height(desktop.canvas.height)
	assert desktop.overview.page == 0
	desktop.step_window_overview(layout.capacity() - 1)
	assert desktop.window_overview_pointer_down(window_overview_next, .desktop)
	assert desktop.overview.page == 1
	assert desktop.window_overview_position(desktop.overview.selected_id) or { -1 } == layout.capacity()
	assert desktop.window_overview_pointer_down(window_overview_previous, .desktop)
	assert desktop.overview.page == 0
	mut visited := map[int]bool{}
	for _ in 0 .. 25 {
		visited[desktop.overview.selected_id] = true
		desktop.step_window_overview(1)
	}
	assert visited.len == 25
	for size in [320, 640, 1024] {
		checked := window_overview_layout(size, size * 3 / 4)
		assert checked.columns > 0 && checked.rows > 0
		assert checked.card_width > 0 && checked.card_height > 0
		assert window_overview_padding + window_overview_header_height +
			checked.rows * checked.card_height + (checked.rows - 1) * window_overview_gap <=
			checked.height - window_overview_footer_height - window_overview_padding
	}
}

fn test_overview_closes_other_compositor_overlays_and_preserves_focus_on_cancel() {
	mut desktop := overview_fixture()
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	desktop.toggle_quick_launch()
	assert desktop.switcher.active
	desktop.shortcut_order = default_shortcut_order()
	desktop.shortcut_order[0] = 1
	desktop.shortcut_order[1] = 0
	desktop.shortcut_press = ShortcutPress{ app_index: 0, start_slot: 0, dragging: true }
	desktop.open_window_overview()
	assert !desktop.switcher.active
	assert !desktop.start_menu_open
	assert !desktop.taskbar_preview.open
	assert desktop.tray.flyout == .none_
	assert desktop.shortcut_press.app_index == -1
	assert !desktop.shortcut_press.dragging
	assert desktop.shortcut_order[0] == 0
	assert desktop.shortcut_order[1] == 1
	assert desktop.overview.active
	assert desktop.take_window_overview_keys(key_window_overview) == ''
	assert !desktop.overview.active
	assert desktop.focus == id
}
