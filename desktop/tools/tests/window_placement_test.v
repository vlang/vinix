// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn placement_test_titlebar(mut desktop Desktop, id int) {
	index := desktop.window_index(id) or { panic('missing placement window') }
	window := desktop.windows[index]
	desktop.targets.clear()
	desktop.targets << HitTarget{
		action_id: window.id_titlebar
		x:         window.x
		y:         window.y
		width:     window.width
		height:    desktop.theme().title_height
	}
}

fn placement_test_drag(mut desktop Desktop, id int, x int, y int) {
	placement_test_titlebar(mut desktop, id)
	index := desktop.window_index(id) or { panic('missing placement window') }
	window := desktop.windows[index]
	press_x := window.x + window.width / 2
	press_y := window.y + desktop.theme().title_height / 2
	desktop.on_pointer_move(press_x, press_y)
	desktop.on_pointer_down(press_x, press_y)
	desktop.buttons = button_left
	desktop.on_pointer_move(x, y)
	desktop.buttons = 0
	desktop.on_pointer_up(x, y)
}

fn test_pointer_placement_targets_corners_edges_and_work_area() {
	assert window_placement_at(0, 0, 801, 601).snap == .top_left
	assert window_placement_at(800, 0, 801, 601).snap == .top_right
	assert window_placement_at(0, 600, 801, 601).snap == .bottom_left
	assert window_placement_at(800, 600, 801, 601).snap == .bottom_right
	assert window_placement_at(0, 300, 801, 601).snap == .left
	assert window_placement_at(800, 300, 801, 601).snap == .right
	assert window_placement_at(400, 0, 801, 601).maximize
	assert window_placement_at(40, 0, 801, 601).snap == .top_left
	assert window_placement_at(760, 0, 801, 601).snap == .top_right
	bottom := desktop_usable_height(601) - 1
	assert window_placement_at(40, bottom, 801, 601).snap == .bottom_left
	assert window_placement_at(760, bottom, 801, 601).snap == .bottom_right
	assert window_placement_at(400, bottom, 801, 601).snap == .none_
	assert !window_placement_at(400, bottom, 801, 601).maximize
	// One pixel in from a side, away from a corner, continues a free drag.
	assert window_placement_at(1, 300, 801, 601).snap == .none_
	assert window_placement_at(799, 300, 801, 601).snap == .none_
	assert !window_placement_frame(window_placement_at(0, 0, 0, 0), 0, 0).valid
}

fn test_pointer_quarter_tiling_preserves_normal_size_and_covers_odd_work_area() {
	mut desktop := Desktop{ canvas: Canvas{ width: 801, height: 601 } }
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	for snap in [WindowSnap.top_left, .top_right, .bottom_left, .bottom_right] {
		x := if snap in [.top_right, .bottom_right] { 800 } else { 0 }
		y := if snap in [.bottom_left, .bottom_right] { 600 } else { 0 }
		placement_test_drag(mut desktop, id, x, y)
		index := desktop.window_index(id) or { panic('missing quarter-tiled window') }
		window := desktop.windows[index]
		frame := window_placement_frame(WindowPlacement{ snap: snap }, 801, 601)
		assert window.snap == snap
		assert !window.maximized
		assert window.x == frame.x
		assert window.y == frame.y
		assert window.width == frame.w
		assert window.height == frame.h
		assert window.restore_width == 400
		assert window.restore_height == 260
		assert window.x + window.width <= 801
		assert window.y + window.height <= desktop_usable_height(601)
	}
	// Moving to the top center maximizes, preserving the same normal frame.
	placement_test_drag(mut desktop, id, 400, 0)
	mut index := desktop.window_index(id) or { panic('missing maximized window') }
	assert desktop.windows[index].maximized
	assert desktop.windows[index].restore_width == 400
	assert desktop.windows[index].restore_height == 260
	placement_test_drag(mut desktop, id, 500, 160)
	index = desktop.window_index(id) or { panic('missing restored window') }
	assert !desktop.windows[index].maximized
	assert desktop.windows[index].snap == .none_
	assert desktop.windows[index].width == 400
	assert desktop.windows[index].height == 260
}

fn test_placement_preview_follows_target_without_intercepting_pointer() {
	mut desktop := Desktop{ canvas: Canvas{ width: 801, height: 601 } }
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	placement_test_titlebar(mut desktop, id)
	desktop.on_pointer_down(320, 90)
	desktop.buttons = button_left
	desktop.on_pointer_move(0, 300)
	preview := desktop.window_placement_element() or { panic('missing half placement preview') }
	assert preview.id == window_placement_preview_id
	assert preview.frame.x == 6
	assert preview.frame.y == 6
	assert preview.frame.width == 388
	assert preview.frame.height == desktop_usable_height(601) - 12
	assert !preview.clickable
	assert !preview.draggable
	assert preview.action_id == ''
	assert preview.children.len == 0
	targets := desktop.targets.len
	desktop.record_target(&preview, int(preview.frame.x), int(preview.frame.y),
		int(preview.frame.width), int(preview.frame.height))
	assert desktop.targets.len == targets
	assert damage_contains(desktop.drag_damage, desktop.canvas_damage())
	desktop.drag_damage = DamageRect{}
	desktop.on_pointer_move(0, 0)
	quarter := desktop.window_placement_element() or { panic('missing quarter placement preview') }
	assert quarter.frame.height == desktop_usable_height(601) / 2 - 12
	assert damage_contains(desktop.drag_damage, desktop.canvas_damage())
	desktop.drag_damage = DamageRect{}
	desktop.on_pointer_move(1, 300)
	if _ := desktop.window_placement_element() {
		assert false, 'placement preview must disappear inside the desktop'
	}
	assert damage_contains(desktop.drag_damage, desktop.canvas_damage())
	desktop.buttons = 0
	desktop.on_pointer_up(1, 300)
	if _ := desktop.window_placement_element() {
		assert false, 'release must clear placement preview'
	}
}

fn test_placement_preview_requires_titlebar_movement_and_held_button() {
	mut desktop := Desktop{ canvas: Canvas{ width: 800, height: 600 } }
	id := desktop.spawn('Welcome', .welcome, 120, 0, 400, 260)
	desktop.drag = Drag{ kind: .move, window_id: id, maximize_on_release: true }
	desktop.buttons = button_left
	if _ := desktop.window_placement_element() {
		assert false, 'a titlebar click must not show a placement preview'
	}
	desktop.drag.moved = true
	desktop.buttons = 0
	if _ := desktop.window_placement_element() {
		assert false, 'an unheld gesture must not show a placement preview'
	}
	desktop.buttons = button_left
	desktop.drag.kind = .resize
	if _ := desktop.window_placement_element() {
		assert false, 'a resize must not show a placement preview'
	}
}

fn test_release_wrap_keeps_half_maximize_and_corner_targets() {
	assert window_placement_on_release(WindowPlacement{ snap: .left }, 799, 300, 800,
		600).snap == .left
	assert window_placement_on_release(WindowPlacement{ snap: .right }, 0, 300, 800,
		600).snap == .right
	assert window_placement_on_release(WindowPlacement{ maximize: true }, 400, 599, 800,
		600).maximize
	assert window_placement_on_release(WindowPlacement{ snap: .top_left }, 799, 599,
		800, 600).snap == .top_left
	assert window_placement_on_release(WindowPlacement{ snap: .bottom_right }, 0, 0,
		800, 600).snap == .bottom_right
	assert window_placement_on_release(WindowPlacement{ snap: .left }, 1, 300, 800,
		600).snap == .none_
	assert window_placement_on_release(WindowPlacement{ maximize: true }, 400, 1, 800,
		600).snap == .none_
}

fn test_button_level_corner_release_keeps_the_held_target_after_wrap() {
	mut desktop := Desktop{ canvas: Canvas{ width: 800, height: 600 } }
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	placement_test_titlebar(mut desktop, id)
	desktop.on_pointer_move(320, 90)
	desktop.on_pointer_down(320, 90)
	desktop.buttons = button_left
	desktop.on_pointer_move(0, 0)
	assert desktop.drag.snap_on_release == .top_left
	desktop.buttons = 0
	desktop.on_pointer_move(799, 599)
	index := desktop.window_index(id) or { panic('missing wrapped corner window') }
	assert desktop.windows[index].snap == .top_left
	assert !desktop.windows[index].maximized
	assert desktop.windows[index].x == 0
	assert desktop.windows[index].y == 0
	assert desktop.windows[index].width == 400
	assert desktop.windows[index].height == desktop_usable_height(600) / 2
	assert desktop.drag.kind == .none_
}

fn test_placement_preview_is_painted_over_windows_and_below_taskbar() {
	mut desktop := Desktop{ canvas: Canvas{ width: 800, height: 600 } }
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	desktop.buttons = button_left
	desktop.drag = Drag{ kind: .move, window_id: id, moved: true, snap_on_release: .left }
	root := desktop.build_tree()
	mut window_order := -1
	mut preview_order := -1
	mut taskbar_order := -1
	for i, child in root.children {
		if child.id == 'win.${id}' {
			window_order = i
		} else if child.id == window_placement_preview_id {
			preview_order = i
		} else if child.id == 'taskbar' {
			taskbar_order = i
		}
	}
	assert window_order >= 0
	assert preview_order > window_order
	assert taskbar_order > preview_order
	free_tree(root)
}

fn test_drag_preview_does_not_pollute_retained_window_thumbnails() {
	mut desktop := Desktop{ canvas: new_canvas(800, 600) }
	defer { unsafe { free(desktop.canvas.pixels) } }
	background := u32(0xabcdef)
	desktop.canvas.fill_rect(0, 0, 800, 600, background)
	id := desktop.spawn('Welcome', .welcome, 120, 80, 400, 260)
	index := desktop.window_index(id) or { panic('missing thumbnail window') }
	desktop.windows[index].thumbnail = []u32{len: 4, init: 0x010203}
	desktop.windows[index].thumbnail_width = 2
	desktop.windows[index].thumbnail_height = 2
	desktop.windows[index].thumbnail_scale = 1
	defer { desktop.release_window_thumbnail(index) }
	desktop.drag = Drag{kind: .move, window_id: id, moved: true, snap_on_release: .left}
	desktop.capture_window_thumbnails()
	assert desktop.windows[index].thumbnail.len == 4
	assert desktop.windows[index].thumbnail[0] == 0x010203
	desktop.drag = Drag{}
	desktop.capture_window_thumbnails()
	assert desktop.windows[index].thumbnail.len > 4
	assert desktop.windows[index].thumbnail[0] == background
}
