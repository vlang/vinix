// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn activity_layout_positive(element ui2.Element, width int, height int) {
	for child in element.children {
		assert child.frame.width > 0 && child.frame.height > 0
		assert child.frame.x >= 0 && child.frame.y >= 0
		assert child.frame.x + child.frame.width <= width
		assert child.frame.y + child.frame.height <= height
	}
}

fn activity_layout_disjoint(elements []ui2.Element) {
	for left_index, left in elements {
		for right_index, right in elements {
			if right_index <= left_index { continue }
			assert left.frame.x + left.frame.width <= right.frame.x
				|| right.frame.x + right.frame.width <= left.frame.x
				|| left.frame.y + left.frame.height <= right.frame.y
				|| right.frame.y + right.frame.height <= left.frame.y
		}
	}
}

fn test_activity_toolbar_controls_fit_and_do_not_overlap_at_minimum_width() {
	mut app := ActivityApp{}
	defer { app.close_app() }
	for width in [180, 240, 400, 480, 900] {
		for focused in [false, true] {
			app.search_focused = focused
			tree := app.build(ui2.rect(0, 0, width, 360))!
			mut controls := []ui2.Element{}
			for child in tree.children {
				if child.id == '' || child.frame.y >= activity_toolbar_height { continue }
				assert child.frame.width > 0 && child.frame.height > 0
				assert child.frame.x >= 0 && child.frame.x + child.frame.width <= width
				assert child.frame.y + child.frame.height <= activity_toolbar_height
				controls << child
			}
			activity_layout_disjoint(controls)
			unsafe { controls.free() }
			kill := activity_views_element(tree, activity_action_kill) or { panic('missing kill') }
			assert kill.text == '' && kill.image_path == 'builtin:close'
			inspect := activity_views_element(tree, activity_action_inspect) or { panic('missing inspect') }
			assert inspect.text == 'i'
			assert activity_views_element(tree, activity_action_pause) != none
			assert activity_views_element(tree, activity_action_interval) != none
			assert activity_views_element(tree, activity_action_search) != none
			free_tree(tree)
		}
	}
}

fn test_activity_search_activation_from_other_panes_edits_process_filter() {
	mut app := ActivityApp{}
	defer { app.close_app() }
	for view in [ActivityView.resources, .gpu, .energy, .startup] {
		app.view = view
		app.inspector_open = true
		app.panel_scroll = 100
		app.handle(activity_action_search)!
		assert app.view == .processes && !app.inspector_open && app.panel_scroll == 0
		assert app.search_focused
		app.key_input('x')
	}
	assert app.monitor.query.len == 4
	for byte in app.monitor.query { assert byte == `x` }
	app.handle(activity_action_search_done)!
	assert !app.search_focused
	tree := app.build(ui2.rect(0, 0, 180, 360))!
	assert activity_views_element(tree, 'activity.view.next') != none
	free_tree(tree)
}

fn activity_layout_startup() ActivityStartup {
	mut model := ActivityStartup{ loaded: true, language: desktop_language }
	for index, _ in available_apps {
		if index >= model.actions.len { break }
		number := index.str()
		model.actions[index] = 'activity.startup.toggle.${number}'
		unsafe { number.free() }
	}
	return model
}

fn test_activity_startup_short_and_narrow_layout_keeps_a_renderable_row() {
	mut model := activity_layout_startup()
	defer { model.free() }
	for width in [180, 240, 400, 900] {
		for height in [132, 150, 240] {
			tree := model.build(width, height)
			activity_layout_positive(tree, width, height)
			activity_layout_disjoint(tree.children)
			assert activity_views_element(tree, model.actions[0]) != none
			free_tree(tree)
		}
	}
}

fn test_activity_sensor_graphs_reserve_space_for_totals_and_notes() {
	mut energy := ActivityEnergy{}
	mut gpu := ActivityGpu{ available: true }
	mut resources := ActivityResources{ cpu_count: 4, io_available: true }
	defer { energy.free(); gpu.free(); resources.free() }
	for width in [180, 900] {
		for height in [220, 240, 300, 360] {
			energy_tree := energy.build(width, height)
			activity_layout_positive(energy_tree, width, height)
			activity_layout_disjoint(energy_tree.children)
			free_tree(energy_tree)
			gpu_tree := gpu.build(width, height)
			activity_layout_positive(gpu_tree, width, height)
			activity_layout_disjoint(gpu_tree.children)
			free_tree(gpu_tree)
			for tab in [ActivityResourceTab.cpu, .memory, .disk, .network] {
				resources.tab = tab
				tree := resources.build(width, height)
				activity_layout_positive(tree, width, height)
				activity_layout_disjoint(tree.children)
				free_tree(tree)
			}
		}
	}
}

fn test_activity_short_panel_viewport_can_reach_startup_controls() {
	mut app := ActivityApp{ view: .startup, startup: activity_layout_startup() }
	defer { app.close_app() }
	tree := app.build(ui2.rect(0, 0, 180, 96))!
	assert app.panel_height == 28 && app.panel_content_height == 150
	assert activity_views_element(tree, 'activity.panel.viewport') != none
	assert activity_views_element(tree, 'activity.panel.scrollbar') != none
	free_tree(tree)
	app.pointer_event(.scroll, .no_button, -100, 80, 80, 180, 96)
	assert app.panel_scroll == app.panel_content_height - app.panel_height
	app.key_input('\x1b[H')
	assert app.panel_scroll == 0
	app.pointer_event(.down, .left, 0, 175, 69, 180, 96)
	assert app.panel_dragging
	app.pointer_event(.move, .no_button, 0, 175, 95, 180, 96)
	assert app.panel_scroll > 0
	app.pointer_event(.up, .left, 0, 175, 95, 180, 96)
	assert !app.panel_dragging
	// Each action has a scroll position that puts its entire target on screen.
	for action in [app.startup.actions[0], 'activity.startup.up', 'activity.startup.down'] {
		app.panel_scroll = 0
		initial := app.build(ui2.rect(0, 0, 180, 96))!
		button := activity_views_element(initial, action) or { panic('missing startup action') }
		app.panel_scroll = int(button.frame.y)
		app.clamp_panel_scroll()
		assert int(button.frame.y) - app.panel_scroll >= 0
		assert int(button.frame.y + button.frame.height) - app.panel_scroll <= app.panel_height
		free_tree(initial)
	}
}

fn test_activity_minimum_process_body_has_a_visible_row_and_bounded_columns_menu() {
	mut app := ActivityApp{
		monitor: ActivityMonitor{
			rows: [ActivityRow{ pid: 900000, select_action: 'activity.select.900000' }]
			visible: [ActivityVisible{ index: 0 }]
		}
	}
	defer { app.close_app() }
	tree := app.build(ui2.rect(0, 0, 180, 96))!
	row := activity_views_element(tree, 'activity.select.900000') or { panic('missing row') }
	assert row.frame.y == activity_toolbar_height
	assert row.frame.y + row.frame.height <= 96
	free_tree(tree)
	app.columns_open = true
	menu_tree := app.build(ui2.rect(0, 0, 180, 360))!
	menu := activity_views_element(menu_tree, 'activity.columns.menu') or { panic('missing columns menu') }
	assert menu.frame.x >= 0 && menu.frame.x + menu.frame.width <= 180
	activity_layout_positive(menu, int(menu.frame.width), int(menu.frame.height))
	free_tree(menu_tree)
	app.monitor.selected_pid = 900000
	app.kill_failed = true
	error_tree := app.build(ui2.rect(0, 0, 180, 96))!
	mut visible_error := false
	for child in error_tree.children {
		if child.text == tr('activity.error.kill') {
			visible_error = child.frame.y >= activity_toolbar_height && child.frame.y + child.frame.height <= 96
		}
	}
	assert visible_error
	assert activity_views_element(error_tree, 'activity.columns.menu') != none
	free_tree(error_tree)
}

fn test_activity_columns_popup_bounds_and_pagination_reach_every_choice() {
	mut app := ActivityApp{ columns_open: true }
	defer { app.close_app() }
	for width in [180, 400, 900] {
		for height in [96, 132, 200, 360] {
			tree := app.build(ui2.rect(0, 0, width, height))!
			menu := activity_views_element(tree, 'activity.columns.menu') or { panic('missing columns menu') }
			assert menu.frame.x >= 0 && menu.frame.x + menu.frame.width <= width
			assert menu.frame.y + menu.frame.height <= height
			activity_layout_positive(menu, int(menu.frame.width), int(menu.frame.height))
			activity_layout_disjoint(menu.children)
			free_tree(tree)
		}
	}
	initial := app.build(ui2.rect(0, 0, 180, 96))!
	assert app.columns_visible == 1
	free_tree(initial)
	app.key_input('\x1b[F')
	assert app.columns_scroll == 7
	last := app.build(ui2.rect(0, 0, 180, 96))!
	assert activity_views_element(last, activity_column_toggle(.state)) != none
	assert activity_views_element(last, 'activity.columns.up') != none
	free_tree(last)
	app.handle(activity_column_toggle(.state))!
	assert app.monitor.columns & activity_column_bit(.state) != 0
	app.pointer_event(.scroll, .no_button, 100, 40, 75, 180, 96)
	assert app.columns_scroll == 0
	for _ in 0 .. 7 { app.handle('activity.columns.down')! }
	assert app.columns_scroll == 7
}
