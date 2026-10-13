// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn luna_test_desktop(scale int) Desktop {
	mut desktop := Desktop{
		canvas: new_scaled_canvas(640, 480, 640 * scale, 480 * scale, scale)
		fonts:  load_fonts_for_scale(scale)
	}
	desktop.tray.preferences_loaded = true
	desktop.settings.theme = .windows_xp
	// A fixed time: nothing a comparison renders may tick in between.
	desktop.update_taskbar_clock_at(1_760_000_000)
	return desktop
}

fn luna_test_full_frame(mut desktop Desktop) {
	tree := desktop.build_tree()
	// As render_desktop_frame, without the files of a home these tests lack.
	desktop.render_clipped(tree, desktop.damage_clip(desktop.canvas_damage()), false)
	free_tree(tree)
	desktop.dirty = false
}

fn luna_test_partial_frame(mut desktop Desktop, x int, y int, w int, h int) {
	tree := desktop.build_tree()
	desktop.render_clipped(tree, desktop.damage_clip(DamageRect{
		x:     x
		y:     y
		w:     w
		h:     h
		valid: true
	}), false)
	free_tree(tree)
}

fn luna_test_pixels(desktop &Desktop) []u32 {
	count := desktop.canvas.stride * desktop.canvas.physical_height
	mut pixels := []u32{len: count}
	unsafe { vmemcpy(pixels.data, desktop.canvas.pixels, count * 4) }
	return pixels
}

fn luna_test_same(desktop &Desktop, partial []u32, full []u32) {
	assert partial.len == full.len
	for index in 0 .. partial.len {
		if partial[index] != full[index] {
			x := index % desktop.canvas.stride / desktop.canvas.scale
			y := index / desktop.canvas.stride / desktop.canvas.scale
			assert false, 'partial frame differs from a full one at ${x},${y}: ${partial[index].hex()} for ${full[index].hex()}'
		}
	}
}

// luna_test_pixel is the canvas at a logical point.
fn luna_test_pixel(desktop &Desktop, x int, y int) u32 {
	return desktop.canvas.logical_pixel(x, y)
}

fn luna_test_child(frame &ui2.Element, suffix string) ui2.Element {
	for child in frame.children {
		if child.id.ends_with(suffix) {
			return child
		}
		for grandchild in child.children {
			if grandchild.id.ends_with(suffix) {
				return grandchild
			}
		}
	}
	panic('no ${suffix} in the window')
}

fn test_windows_xp_frame_has_windows_xp_measurements() {
	assert theme_windows_xp.chrome == .luna
	assert !theme_windows_xp.glass
	assert theme_windows_xp.title_height == 30
	assert theme_windows_xp.frame_border == 4
	assert theme_windows_xp.button_look == .luna
	assert theme_windows_xp.shadow_alpha == 0
	assert theme_windows_xp.title_text_active == 0xffffff
	assert theme_windows_xp.title_bold

	mut desktop := luna_test_desktop(1)
	id := desktop.spawn('Welcome', .welcome, 100, 60, 400, 300)
	frame := desktop.window_element(0)
	body := luna_test_child(&frame, '.body')
	// Four pixels of frame beside and below the body, thirty above it.
	assert int(body.frame.x) == 4
	assert int(body.frame.y) == 30
	assert int(body.frame.width) == 400 - 8
	assert int(body.frame.height) == 300 - 30 - 4
	// The frame's element is square: only the upper corners are round, and
	// the renderer cuts those.
	assert int(frame.box.radius) == 0
	// Three 21-pixel squares two pixels apart, the last six from the edge and
	// all five from the top: minimise, maximise, close.
	minimize := luna_test_child(&frame, '.minimize')
	maximize := luna_test_child(&frame, '.maximize')
	close := luna_test_child(&frame, '.close')
	assert int(close.frame.x) == 400 - 6 - 21
	assert int(maximize.frame.x) == int(close.frame.x) - 23
	assert int(minimize.frame.x) == int(maximize.frame.x) - 23
	for button in [minimize, maximize, close] {
		assert int(button.frame.y) == 5
		assert int(button.frame.width) == 21 && int(button.frame.height) == 21
	}
	// The icon leads the title two pixels inside the body's edge.
	title := luna_test_child(&frame, '.title')
	assert int(title.frame.x) == 4 + 2 + 16 + 4
	assert title.text_style.color == 0xffffff && title.text_style.bold
	free_tree(frame)

	// Maximized, the frame's sides and bottom are off the screen.
	desktop.toggle_maximize(id)
	maximized := desktop.window_element(0)
	wide := luna_test_child(&maximized, '.body')
	assert int(wide.frame.x) == 0
	assert int(wide.frame.width) == 640
	assert int(wide.frame.height) == 480 - taskbar_height - 30
	free_tree(maximized)
}

fn test_windows_xp_title_is_blue_and_its_window_casts_no_shadow() {
	for scale in [1, 2] {
		mut desktop := luna_test_desktop(scale)
		desktop.spawn('Notes', .notes, 200, 200, 300, 200)
		desktop.spawn('Welcome', .welcome, 100, 60, 300, 220)
		luna_test_full_frame(mut desktop)
		assert !desktop.glass.allocated
		// The focused window's bar runs through the gradient's blues, with the
		// dark foot just above the body.
		assert luna_test_pixel(&desktop, 250, 60 + 12) == luna_gradient(luna_title_active, 12, 30)
		assert luna_test_pixel(&desktop, 250, 60 + 29) == 0x003092
		blue := luna_test_pixel(&desktop, 250, 60 + 12)
		assert blue & 0xff > 0xd0 && (blue >> 16) & 0xff < 0x20
		// The unfocused one's is the pale blue.
		assert luna_test_pixel(&desktop, 420, 200 + 12) == luna_gradient(luna_title_inactive, 12, 30)
		// The upper corners are cut round: the pixel in the corner is what was
		// behind the window, and the lower corners are the frame's.
		assert luna_test_pixel(&desktop, 100, 60) != luna_title_edge
		assert luna_test_pixel(&desktop, 399, 60) != luna_title_edge
		assert luna_test_pixel(&desktop, 250, 60) == luna_title_edge
		assert luna_test_pixel(&desktop, 100, 279) == luna_frame_right[0]
		assert luna_test_pixel(&desktop, 399, 279) == luna_frame_right[0]
		// The frame is four columns of blue; the body starts after them.
		for column in 0 .. 4 {
			assert luna_test_pixel(&desktop, 100 + column, 150) == luna_frame_left[column]
			assert luna_test_pixel(&desktop, 399 - column, 150) == luna_frame_right[column]
		}
		assert luna_test_pixel(&desktop, 104, 100) == theme_windows_xp.window_body
		// No shadow: a pixel beside the frame is the wallpaper's own row.
		assert luna_test_pixel(&desktop, 98, 200) == luna_test_pixel(&desktop, 630, 200)
		// The close button is red, the other two blue, inside a white line.
		close_x := 100 + 300 - 6 - 21
		assert luna_test_pixel(&desktop, close_x + 10, 60 + 5) == 0xffffff
		red := luna_test_pixel(&desktop, close_x + 17, 60 + 5 + 17)
		assert (red >> 16) & 0xff > 0xb0 && red & 0xff < 0x40
		face := luna_test_pixel(&desktop, close_x - 23 + 17, 60 + 5 + 17)
		assert face & 0xff > 0xc0 && (face >> 16) & 0xff < 0x40
	}
}

fn test_windows_xp_caption_buttons_and_frame_are_hit() {
	for side in [ButtonSide.right, ButtonSide.left] {
		mut desktop := luna_test_desktop(1)
		desktop.settings.button_side = side
		id := desktop.spawn('Welcome', .welcome, 100, 60, 400, 300)
		luna_test_full_frame(mut desktop)
		close_x := if side == .right { 100 + 400 - 6 - 11 } else { 100 + 6 + 10 }
		assert desktop.hit_action(close_x, 60 + 5) == 'win.${id}.close'
		assert desktop.hit_action(close_x, 60 + 25) == 'win.${id}.close'
		assert desktop.hit_action(close_x, 60 + 27) == 'win.${id}.titlebar'
		// The rows above the buttons resize.
		assert desktop.hit_action(300, 60 + 2) == 'win.${id}.resize_n'
		assert desktop.hit_action(300, 60 + 15) == 'win.${id}.titlebar'
		// So does all of the frame at the sides and the bottom.
		assert desktop.hit_action(100 + 3, 200) == 'win.${id}.resize_w'
		assert desktop.hit_action(100 + 400 - 4, 200) == 'win.${id}.resize_e'
		assert desktop.hit_action(300, 60 + 300 - 4) == 'win.${id}.resize_s'
		assert desktop.hit_action(100 + 5, 200) == 'win.${id}.body'
	}
}

fn test_windows_xp_partial_frames_match_full_frames() {
	for scale in [1, 2] {
		mut desktop := luna_test_desktop(scale)
		desktop.spawn('System', .system, 60, 50, 320, 240)
		id := desktop.spawn('Notes', .notes, 200, 130, 280, 200)
		luna_test_full_frame(mut desktop)
		before := luna_test_pixels(&desktop)
		// Repainting the taskbar, a window's corner and its caption buttons
		// changes nothing: Luna is the same picture however it is clipped.
		desktop.damage_taskbar()
		desktop.add_frame_damage(190, 120, 60, 50)
		desktop.add_frame_damage(400, 126, 90, 40)
		damage := desktop.frame_damage
		desktop.frame_damage = FrameDamage{}
		for i in 0 .. damage.count {
			luna_test_partial_frame(mut desktop, damage.rects[i].x, damage.rects[i].y, damage.rects[i].w,
				damage.rects[i].h)
		}
		assert !desktop.dirty && !desktop.frame_damage.valid()
		luna_test_same(&desktop, luna_test_pixels(&desktop), before)

		// A window dragged in a partial frame, with the damage the drag adds.
		index := desktop.window_index(id) or { panic('missing window') }
		old_x := desktop.windows[index].x
		old_y := desktop.windows[index].y
		desktop.windows[index].x += 41
		desktop.windows[index].y -= 27
		desktop.add_drag_damage(old_x, old_y, desktop.windows[index].x, desktop.windows[index].y,
			0, 0, 0, 0, desktop.windows[index].width, desktop.windows[index].height)
		drag := desktop.drag_damage
		desktop.drag_damage = DamageRect{}
		luna_test_partial_frame(mut desktop, drag.x, drag.y, drag.w, drag.h)
		assert !desktop.dirty
		partial := luna_test_pixels(&desktop)
		luna_test_full_frame(mut desktop)
		luna_test_same(&desktop, partial, luna_test_pixels(&desktop))

		// The pointer over the close button lights it, and only it.
		close := desktop.hit_action(desktop.windows[index].x + 280 - 6 - 11, desktop.windows[index].y + 12)
		assert close == 'win.${id}.close'
		desktop.set_hover(close)
		assert desktop.damage_hover_change('', close)
		hover := desktop.frame_damage
		desktop.frame_damage = FrameDamage{}
		for i in 0 .. hover.count {
			luna_test_partial_frame(mut desktop, hover.rects[i].x, hover.rects[i].y, hover.rects[i].w,
				hover.rects[i].h)
		}
		lit := luna_test_pixels(&desktop)
		luna_test_full_frame(mut desktop)
		luna_test_same(&desktop, lit, luna_test_pixels(&desktop))
	}
}

fn test_windows_xp_taskbar_is_the_blue_bar() {
	// Wide enough for the bar to have room for window buttons.
	mut desktop := Desktop{
		canvas: new_canvas(1024, 600)
		fonts:  load_fonts_for_scale(1)
	}
	desktop.tray.preferences_loaded = true
	desktop.settings.theme = .windows_xp
	desktop.update_taskbar_clock_at(1_760_000_000)
	id := desktop.spawn('Welcome', .welcome, 100, 60, 300, 220)
	luna_test_full_frame(mut desktop)
	top := 600 - taskbar_height
	layout := desktop.taskbar_layout(1)
	// Between the last task button and the pager the bar is its own gradient.
	free_x := layout.workspace_x - 3
	for row in [0, 5, 20, taskbar_height - 1] {
		assert luna_test_pixel(&desktop, free_x, top + row) == luna_gradient(luna_bar, row, taskbar_height)
	}
	// The notification area and the clock sit in the lighter panel, which
	// begins with its dark line.
	tray_x := layout.status_right - layout.status_width - taskbar_item_gap
	assert luna_test_pixel(&desktop, tray_x, top + 20) == luna_tray_edge
	assert luna_test_pixel(&desktop, tray_x + 3, top + 2) == luna_gradient(luna_tray, 2, taskbar_height)
	// The Start button is green, and the focused window's button is pressed in.
	start := desktop.hit_target_named(action_start_toggle) or { panic('no Start button') }
	green := luna_test_pixel(&desktop, start.x + 4, start.y + start.height / 2)
	assert (green >> 8) & 0xff > 0x80 && (green >> 16) & 0xff < 0x60 && green & 0xff < 0x60
	task := desktop.hit_target_named('task.${id}') or { panic('no task button') }
	assert luna_test_pixel(&desktop, task.x + task.width - 6, task.y + task.height / 2) == luna_bar_button_pressed
	// One that is not in front is raised.
	other := desktop.spawn('Notes', .notes, 200, 150, 300, 200)
	luna_test_full_frame(mut desktop)
	first := desktop.hit_target_named('task.${id}') or { panic('no task button') }
	assert luna_test_pixel(&desktop, first.x + first.width - 6, first.y + first.height / 2) == luna_bar_button
	second := desktop.hit_target_named('task.${other}') or { panic('no task button') }
	assert luna_test_pixel(&desktop, second.x + second.width - 6, second.y + second.height / 2) == luna_bar_button_pressed
}

fn test_luna_gradient_runs_through_its_stops() {
	assert luna_gradient(luna_title_active, 0, 30) == 0x0058ee
	assert luna_gradient(luna_title_active, 29, 30) == 0x003092
	assert luna_gradient(luna_bar, 0, 46) == 0x1f2f86
	assert luna_gradient(luna_bar, 45, 46) == 0x1941a5
	// A span of one row is the first stop, and positions past the end the last.
	assert luna_gradient(luna_title_active, 0, 1) == 0x0058ee
	assert luna_gradient(luna_title_active, 40, 30) == 0x003092
	// Between two stops the colour is between them.
	middle := luna_gradient([LunaStop{0, 0x000000}, LunaStop{1000, 0xfefefe}], 1, 3)
	assert middle == 0x7f7f7f || middle == 0x7e7e7e || middle == 0x808080
}
