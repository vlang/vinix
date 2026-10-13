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

// A screen wide enough for the bar's buttons, and tall enough for the menu.
fn luna_menu_test_desktop(scale int) Desktop {
	mut desktop := Desktop{
		canvas: new_scaled_canvas(1024, 600, 1024 * scale, 600 * scale, scale)
		fonts:  load_fonts_for_scale(scale)
	}
	desktop.tray.preferences_loaded = true
	desktop.settings.theme = .windows_xp
	desktop.update_taskbar_clock_at(1_760_000_000)
	return desktop
}

// luna_test_find is the element of this tree with this id.
fn luna_test_find(root &ui2.Element, id string) ?ui2.Element {
	for child in root.children {
		if child.id == id {
			return child
		}
		if found := luna_test_find(&child, id) {
			return found
		}
	}
	return none
}

// luna_test_labelled is the first element of this tree showing this text.
fn luna_test_labelled(root &ui2.Element, text string) ?ui2.Element {
	for child in root.children {
		if child.text == text {
			return child
		}
		if found := luna_test_labelled(&child, text) {
			return found
		}
	}
	return none
}

fn luna_test_pictured(root &ui2.Element, image string) bool {
	for child in root.children {
		if child.image_path == image || luna_test_pictured(&child, image) {
			return true
		}
	}
	return false
}

fn luna_test_red(color u32) int {
	return int((color >> 16) & 0xff)
}

fn luna_test_green(color u32) int {
	return int((color >> 8) & 0xff)
}

fn luna_test_blue(color u32) int {
	return int(color & 0xff)
}

fn test_windows_xp_start_menu_is_laid_out_as_windows_xps() {
	for scale in [1, 2] {
		mut desktop := luna_menu_test_desktop(scale)
		desktop.spawn('Welcome', .welcome, 520, 60, 300, 220)
		luna_test_full_frame(mut desktop)
		top := 600 - taskbar_height
		rect := desktop.start_menu_rect()
		y := int(rect.y)
		width := int(rect.width)
		height := int(rect.height)
		// It rises from the Start button, in the screen's corner.
		assert int(rect.x) == 0
		assert width == luna_menu_width
		assert y + height == top
		behind := luna_test_pixel(&desktop, 0, y)
		desktop.toggle_start_menu()
		luna_test_full_frame(mut desktop)

		// The blue header, its upper corners cut round, and the orange line
		// under it, which fades out toward the far end.
		assert luna_test_pixel(&desktop, width - 20, y + 10) == luna_gradient(luna_menu_header, 10,
			luna_menu_header_rows)
		assert luna_test_pixel(&desktop, 0, y) == behind
		assert luna_test_pixel(&desktop, width - 1, y) == luna_test_pixel(&desktop, width + 2, y)
		orange := luna_test_pixel(&desktop, width * 3 / 10, y + luna_menu_header_rows)
		assert luna_test_red(orange) > 0xe0 && luna_test_blue(orange) < 0x60
		faded := luna_test_pixel(&desktop, width - 2, y + luna_menu_header_rows)
		assert luna_test_blue(faded) > luna_test_red(faded)

		// The white column of programs and the pale blue one of places, with
		// the menu's own line down each side of them.
		body_y := y + luna_menu_header_rows + luna_menu_line_rows
		body_height := luna_menu_pane_height(height)
		assert body_y + body_height == top - luna_menu_foot_rows
		assert desktop.start_menu_pane_height() == body_height
		assert luna_test_pixel(&desktop, 3, body_y + 3) == luna_menu_pane
		assert luna_test_pixel(&desktop, width - 3, body_y + body_height - 3) == luna_menu_places
		assert luna_test_pixel(&desktop, 1 + luna_menu_left_width, body_y + 20) == luna_menu_places_edge
		assert luna_test_pixel(&desktop, 0, body_y + 20) == luna_menu_edge
		assert luna_test_pixel(&desktop, width - 1, body_y + 20) == luna_menu_edge
		// The blue foot.
		assert luna_test_pixel(&desktop, 30, top - 20) == luna_gradient(luna_menu_foot, luna_menu_foot_rows - 20,
			luna_menu_foot_rows)

		// The session buttons run leftward from the foot's right end, each with
		// its coloured square.
		shut := desktop.hit_target_named(action_start_shutdown) or { panic('no Shut down') }
		restart := desktop.hit_target_named(action_start_restart) or { panic('no Restart') }
		assert shut.y >= top - luna_menu_foot_rows && shut.y + shut.height <= top
		assert shut.x + shut.width == width - 8
		assert restart.x + restart.width < shut.x && restart.y == shut.y
		red := luna_test_pixel(&desktop, shut.x + 6 + 3, shut.y + shut.height / 2)
		assert luna_test_red(red) > luna_test_green(red) + 0x40
		assert luna_test_red(red) > luna_test_blue(red) + 0x40
		green := luna_test_pixel(&desktop, restart.x + 6 + 3, restart.y + restart.height / 2)
		assert luna_test_green(green) > luna_test_red(green) + 0x30
		assert luna_test_green(green) > luna_test_blue(green) + 0x30
		assert desktop.hit_target_named(action_start_sleep) == none

		// A program's row is the whole width of its column, and under the
		// pointer it is the selection's blue.
		first := desktop.hit_action(60, body_y + 9 + 19)
		assert first in app_start_actions
		row := desktop.hit_target_named(first) or { panic('no program row') }
		assert row.x == 1 + 7 && row.y == body_y + 9 && row.height == 38
		assert luna_test_pixel(&desktop, row.x + 2, row.y + 19) == luna_menu_pane
		place := desktop.hit_target_named(action_start_documents) or { panic('no Documents') }
		assert place.x > luna_menu_left_width && place.x + place.width < width
		assert luna_test_pixel(&desktop, place.x + 2, place.y + place.height / 2) == luna_menu_places
		desktop.set_hover(first)
		luna_test_full_frame(mut desktop)
		assert luna_test_pixel(&desktop, row.x + 2, row.y + 19) == luna_menu_select
		desktop.set_hover(action_start_documents)
		luna_test_full_frame(mut desktop)
		assert luna_test_pixel(&desktop, row.x + 2, row.y + 19) == luna_menu_pane
		assert luna_test_pixel(&desktop, place.x + 2, place.y + place.height / 2) == luna_menu_select
		desktop.set_hover(action_start_shutdown)
		luna_test_full_frame(mut desktop)
		assert luna_test_pixel(&desktop, shut.x + shut.width - 3, shut.y + 3) == luna_menu_foot_hover
		desktop.set_hover('')

		// What the rows say: the user's name in white on the header, the first
		// group of places in bold dark blue and the rest plain, and All
		// Programs in bold before its green arrow rather than a typed one.
		tree := desktop.build_tree()
		menu := luna_test_find(&tree, action_start_panel) or { panic('no Start menu') }
		assert int(menu.box.radius) == 0
		name := luna_test_find(&menu, 'start.user.name') or { panic('no user name') }
		assert name.text_style.color == 0xffffff && name.text_style.bold && name.text_style.shadow
		documents := luna_test_labelled(&menu, tr('start.documents')) or { panic('no Documents') }
		assert documents.text_style.bold && documents.text_style.color == luna_menu_places_text
		system := luna_test_labelled(&menu, tr('window.system')) or { panic('no System') }
		assert !system.text_style.bold && system.text_style.color == luna_menu_places_text
		all := luna_test_labelled(&menu, 'All Programs') or { panic('no All Programs') }
		assert all.text_style.bold
		assert luna_test_labelled(&menu, tr('start.all_programs')) == none
		assert luna_test_pictured(&menu, 'builtin:luna_arrow')
		assert luna_test_pictured(&menu, 'builtin:luna_power')
		assert luna_test_pictured(&menu, 'builtin:luna_restart')
		assert !luna_test_pictured(&menu, 'builtin:luna_sleep')
		// Nothing is pinned, so no program is in bold.
		firefox := luna_test_labelled(&menu, app_title_text(available_apps[1].title)) or {
			panic('no Firefox')
		}
		assert !firefox.text_style.bold
		arrow_x := 1 + int(all.frame.x) + int(all.frame.width) + 4
		free_tree(tree)
		lit := desktop.hit_target_named(action_start_all) or { panic('no All Programs row') }
		arrow := luna_test_pixel(&desktop, arrow_x + 2, lit.y + lit.height / 2)
		assert luna_test_green(arrow) > luna_test_red(arrow) + 0x30
		assert luna_test_green(arrow) > luna_test_blue(arrow) + 0x30

		// What is pinned is in bold, above a rule; a machine that can sleep
		// has a third session button, before the other two.
		desktop.start_pins = [2]
		desktop.idle.sleep_available = true
		luna_test_full_frame(mut desktop)
		pinned_tree := desktop.build_tree()
		pinned_menu := luna_test_find(&pinned_tree, action_start_panel) or { panic('no Start menu') }
		pinned := luna_test_labelled(&pinned_menu, app_title_text(available_apps[2].title)) or {
			panic('no pinned program')
		}
		assert pinned.text_style.bold
		unpinned := luna_test_labelled(&pinned_menu, app_title_text(available_apps[1].title)) or {
			panic('no Firefox')
		}
		assert !unpinned.text_style.bold
		assert luna_test_find(&pinned_menu, 'start.pins.rule') != none
		assert luna_test_pictured(&pinned_menu, 'builtin:luna_sleep')
		free_tree(pinned_tree)
		sleep := desktop.hit_target_named(action_start_sleep) or { panic('no Sleep') }
		again := desktop.hit_target_named(action_start_restart) or { panic('no Restart') }
		assert sleep.x + sleep.width < again.x && sleep.x > 0
		yellow := luna_test_pixel(&desktop, sleep.x + 6 + 3, sleep.y + sleep.height / 2)
		assert luna_test_red(yellow) > luna_test_blue(yellow) + 0x60
		assert luna_test_green(yellow) > luna_test_blue(yellow) + 0x40
	}
}

fn test_windows_xp_start_button_is_green_in_the_corner() {
	for scale in [1, 2] {
		mut desktop := luna_menu_test_desktop(scale)
		luna_test_full_frame(mut desktop)
		top := 600 - taskbar_height
		middle := top + taskbar_height / 2
		start := desktop.hit_target_named(action_start_toggle) or { panic('no Start button') }
		// The whole height of the bar from the screen's corner, as wide as its
		// mark and its word need.
		assert start.x == 0 && start.y == top && start.height == taskbar_height
		assert start.width == desktop.luna_start_width()
		assert start.width > start_button_width
		tree := desktop.build_tree()
		button := luna_test_find(&tree, action_start_toggle) or { panic('no Start button') }
		assert button.text == tr('start.button') && button.text == 'start'
		assert button.text_style.bold
		free_tree(tree)
		// Green, square where it meets the screen's edge and round at its
		// other end, where the bar shows in the corners.
		rest := luna_test_pixel(&desktop, 3, middle)
		for corner in [luna_test_pixel(&desktop, 0, top + 1), rest,
			luna_test_pixel(&desktop, 0, top + taskbar_height - 2)] {
			assert luna_test_green(corner) > luna_test_red(corner) + 0x30
			assert luna_test_green(corner) > luna_test_blue(corner) + 0x30
		}
		assert luna_test_pixel(&desktop, start.width - 1, top) == luna_gradient(luna_bar, 0, taskbar_height)
		assert luna_test_pixel(&desktop, start.width - 1, top + taskbar_height - 1) == luna_gradient(luna_bar,
			taskbar_height - 1, taskbar_height)
		// Its mark and its word are white.
		mut white := 0
		for x in 0 .. start.width {
			if luna_test_pixel(&desktop, x, middle) == 0xffffff {
				white++
			}
		}
		assert white > 6
		// The next button on the bar starts after it.
		next := desktop.hit_action(start.width + 8 + 2, middle)
		assert next.len > 0 && next != action_start_toggle
		assert desktop.hit_action(start.width - 14, middle) == action_start_toggle

		// Brighter under the pointer, and darker, pressed in, while its menu
		// is open -- which rises from it.
		desktop.set_hover(action_start_toggle)
		luna_test_full_frame(mut desktop)
		hot := luna_test_pixel(&desktop, 3, middle)
		desktop.set_hover('')
		desktop.toggle_start_menu()
		luna_test_full_frame(mut desktop)
		held := luna_test_pixel(&desktop, 3, middle)
		assert luna_test_green(hot) > luna_test_green(rest)
		assert luna_test_green(held) < luna_test_green(rest)
		rect := desktop.start_menu_rect()
		assert int(rect.x) == start.x && int(rect.y + rect.height) == start.y
		desktop.close_start_menu()

		// The other themes keep their own button and their own menu.
		for kind in [ThemeKind.default_, ThemeKind.windows7] {
			desktop.settings.theme = kind
			luna_test_full_frame(mut desktop)
			plain := desktop.hit_target_named(action_start_toggle) or { panic('no Start button') }
			assert plain.x > 0 && plain.width == start_button_width
			assert plain.height < taskbar_height
			assert !desktop.start_menu_luna()
			own := desktop.start_menu_rect()
			assert int(own.x) > 0 && int(own.width) == start_menu_preferred_width
			assert desktop.start_menu_pane_height() == int(own.height) - 14
			assert desktop.start_menu_search_y(400) == 400 - start_menu_search_height - 8
		}
		desktop.settings.theme = .windows_xp
	}
}

fn test_windows_xp_start_menu_shows_its_search_field_only_when_searching() {
	mut desktop := luna_menu_test_desktop(1)
	desktop.toggle_start_menu()
	luna_test_full_frame(mut desktop)
	rect := desktop.start_menu_rect()
	pane := desktop.start_menu_pane_height()
	bottom := int(rect.y) + luna_menu_header_rows + luna_menu_line_rows + pane
	shown := pane - start_menu_search_height - 8
	// Windows XP's menu has no search field: All Programs ends the column, and
	// Search is one of the places.
	assert desktop.start_menu_search_y(pane) == pane
	assert desktop.hit_action(40, bottom - 20) == action_start_all
	find := desktop.hit_target_named(action_start_search) or { panic('no Search') }
	assert find.x > luna_menu_left_width

	// Typing brings the field out, under what it finds.
	desktop.start_menu_key_input('c')
	luna_test_full_frame(mut desktop)
	assert desktop.start_menu_search_y(pane) == shown
	assert desktop.hit_action(40, bottom - 20) == action_start_search
	assert luna_test_pixel(&desktop, luna_menu_left_width - 12, bottom - 12) == luna_menu_search
	page := desktop.start_menu_current_page()
	assert page.rows_bottom <= shown - 5
	first := desktop.hit_action(60, int(rect.y) + luna_menu_header_rows + luna_menu_line_rows + 12)
	assert first in app_start_actions

	// It stays while the query is edited, and goes when the menu is clicked
	// somewhere else.
	desktop.start_menu_key_input('\x7f')
	assert desktop.start_menu_query.len == 0
	assert desktop.start_menu_search_y(pane) == shown
	desktop.handle_start_action(action_start_panel)
	luna_test_full_frame(mut desktop)
	assert desktop.start_menu_search_y(pane) == pane
	assert desktop.hit_action(40, bottom - 20) == action_start_all

	// Search, among the places, brings it out with nothing typed; All Programs
	// moves up to make room.
	desktop.handle_start_action(action_start_search)
	luna_test_full_frame(mut desktop)
	assert desktop.start_menu_search_y(pane) == shown
	assert desktop.hit_action(40, bottom - 20) == action_start_search
	all := desktop.hit_target_named(action_start_all) or { panic('no All Programs') }
	assert all.y + all.height <= bottom - start_menu_search_height - 8

	// Every program, a page at a time, uses the room the field leaves.
	desktop.handle_start_action(action_start_all)
	assert desktop.start_menu_search_y(pane) == pane
	luna_test_full_frame(mut desktop)
	listed := desktop.start_menu_current_page()
	assert listed.capacity > 0 && listed.rows_bottom <= pane
	assert desktop.hit_target_named(action_start_back) != none
}

fn test_windows_xp_start_menu_partial_frames_match_full_ones() {
	for scale in [1, 2] {
		mut desktop := luna_menu_test_desktop(scale)
		desktop.spawn('Welcome', .welcome, 300, 80, 300, 220)
		desktop.start_pins = [2]
		desktop.toggle_start_menu()
		desktop.set_hover(action_start_documents)
		luna_test_full_frame(mut desktop)
		before := luna_test_pixels(&desktop)
		top := 600 - taskbar_height
		y := int(desktop.start_menu_rect().y)
		// The header's corner and the line under it, the two columns, the
		// menu's edge over a window, and the foot with the Start button.
		for area in [[0, y - 4, 90, 100], [100, y + 50, 200, 40], [200, y + 200, 120, 90],
			[400, y + 30, 80, 300], [0, top - 60, 300, 60 + taskbar_height],
			[luna_menu_width - 150, top - 44, 200, 50]] {
			luna_test_partial_frame(mut desktop, area[0], area[1], area[2], area[3])
			luna_test_same(&desktop, luna_test_pixels(&desktop), before)
		}

		// The Start button lit by the pointer in a partial frame.
		desktop.close_start_menu()
		luna_test_full_frame(mut desktop)
		desktop.set_hover(action_start_toggle)
		assert desktop.damage_hover_change('', action_start_toggle)
		hover := desktop.frame_damage
		desktop.frame_damage = FrameDamage{}
		assert hover.count > 0
		for i in 0 .. hover.count {
			luna_test_partial_frame(mut desktop, hover.rects[i].x, hover.rects[i].y, hover.rects[i].w,
				hover.rects[i].h)
		}
		lit := luna_test_pixels(&desktop)
		luna_test_full_frame(mut desktop)
		luna_test_same(&desktop, lit, luna_test_pixels(&desktop))
	}
}
