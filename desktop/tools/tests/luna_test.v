// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn luna_test_desktop(scale int) Desktop {
	mut desktop := Desktop{
		settings: Settings{ taskbar_show_overview: true, taskbar_show_workspaces: true }
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
	assert int(wide.frame.height) == 480 - classic_taskbar_height - 30
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
		settings: Settings{ taskbar_show_overview: true, taskbar_show_workspaces: true }
		canvas: new_canvas(1024, 600)
		fonts:  load_fonts_for_scale(1)
	}
	desktop.tray.preferences_loaded = true
	desktop.settings.theme = .windows_xp
	desktop.update_taskbar_clock_at(1_760_000_000)
	id := desktop.spawn('Welcome', .welcome, 100, 60, 300, 220)
	luna_test_full_frame(mut desktop)
	top := 600 - classic_taskbar_height
	layout := desktop.taskbar_layout(1)
	// Between the last task button and the pager the bar is its own gradient.
	free_x := layout.workspace_x - 3
	for row in [0, 5, 20, classic_taskbar_height - 1] {
		assert luna_test_pixel(&desktop, free_x, top + row) == luna_gradient(luna_bar, row, classic_taskbar_height)
	}
	// The notification area and the clock sit in the lighter panel, which
	// begins with its dark line.
	tray_x := layout.status_right - layout.status_width - taskbar_item_gap
	assert luna_test_pixel(&desktop, tray_x, top + 20) == luna_tray_edge
	assert luna_test_pixel(&desktop, tray_x + 3, top + 2) == luna_gradient(luna_tray, 2, classic_taskbar_height)
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
		settings: Settings{ taskbar_show_overview: true, taskbar_show_workspaces: true }
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
		top := 600 - classic_taskbar_height
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

		// The reference starts with the columns, without a user banner.
		assert luna_test_pixel(&desktop, 0, y) == behind
		assert luna_test_pixel(&desktop, width - 1, y) == luna_test_pixel(&desktop, width + 2, y)
		assert height == luna_menu_height

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
		shut := desktop.hit_target_named(action_start_power) or { panic('no Turn Off Computer') }
		logoff := desktop.hit_target_named(action_start_logoff) or { panic('no Log Off') }
		assert shut.y >= top - luna_menu_foot_rows && shut.y + shut.height <= top
		assert shut.x + shut.width == width - 8
		assert logoff.x + logoff.width < shut.x && logoff.y == shut.y
		red := luna_test_pixel(&desktop, shut.x + 6 + 3, shut.y + shut.height / 2)
		assert luna_test_red(red) > luna_test_green(red) + 0x40
		assert luna_test_red(red) > luna_test_blue(red) + 0x40
		gold := luna_test_pixel(&desktop, logoff.x + 6 + 3, logoff.y + logoff.height / 2)
		assert luna_test_red(gold) > luna_test_blue(gold) + 0x60
		assert luna_test_green(gold) > luna_test_blue(gold) + 0x40
		assert desktop.hit_target_named(action_start_sleep) == none
		assert desktop.hit_target_named(action_start_restart) == none

		// A program's row is the whole width of its column, and under the
		// pointer it is the selection's blue.
		first := desktop.hit_action(60, body_y + 4 + 19)
		assert first in app_start_actions
		row := desktop.hit_target_named(first) or { panic('no program row') }
		assert row.x == 1 + 7 && row.y == body_y + 4 && row.height == luna_menu_program_height
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
		desktop.set_hover(action_start_power)
		luna_test_full_frame(mut desktop)
		assert luna_test_pixel(&desktop, shut.x + shut.width - 3, shut.y + 3) == luna_menu_foot_hover
		desktop.set_hover('')

		// The first group of places is bold dark blue and the rest plain; All
		// Programs in bold before its green arrow rather than a typed one.
		tree := desktop.build_tree()
		menu := luna_test_find(&tree, action_start_panel) or { panic('no Start menu') }
		assert int(menu.box.radius) == 0
		assert luna_test_find(&menu, 'start.user.name') == none
		assert luna_test_find(&menu, 'start.user.badge') == none
		documents := luna_test_labelled(&menu, tr('start.xp.documents')) or { panic('no Documents') }
		assert documents.text_style.bold && documents.text_style.color == luna_menu_places_text
		system := luna_test_labelled(&menu, tr('start.xp.control_panel')) or { panic('no Control Panel') }
		assert !system.text_style.bold && system.text_style.color == luna_menu_places_text
		all := luna_test_labelled(&menu, 'All Programs') or { panic('no All Programs') }
		assert all.text_style.bold
		assert luna_test_labelled(&menu, tr('start.all_programs')) == none
		assert luna_test_pictured(&menu, 'builtin:luna_arrow')
		assert luna_test_pictured(&menu, 'builtin:luna_power')
		assert luna_test_pictured(&menu, 'builtin:luna_logoff')
		assert !luna_test_pictured(&menu, 'builtin:luna_sleep')
		internet := luna_test_labelled(&menu, tr('start.xp.internet')) or { panic('no Internet') }
		assert internet.text_style.bold
		assert luna_test_labelled(&menu, 'Mozilla Firefox') != none
		mut previous_y := 0.0
		for link in luna_menu_links {
			target := desktop.hit_target_named(link.action) or { panic('missing XP destination: ' + link.action) }
			assert target.y > previous_y && target.y + target.height < shut.y
			if link.action == action_start_defaults {
				line1 := luna_test_find(&menu, 'start.defaults.line1') or { panic('no first defaults line') }
				line2 := luna_test_find(&menu, 'start.defaults.line2') or { panic('no second defaults line') }
				assert line1.text + ' ' + line2.text == tr(link.key)
				assert line1.frame.y + line1.frame.height <= line2.frame.y
			} else {
				assert luna_test_labelled(&menu, tr(link.key)) != none
			}
			previous_y = target.y
		}
		for action in [action_start_files, action_start_system, action_start_terminal, action_start_activity] {
			assert desktop.hit_target_named(action) == none
		}
		arrow_x := 1 + int(all.frame.x) + int(all.frame.width) + 4
		free_tree(tree)
		lit := desktop.hit_target_named(action_start_all) or { panic('no All Programs row') }
		arrow := luna_test_pixel(&desktop, arrow_x + 2, lit.y + lit.height / 2)
		assert luna_test_green(arrow) > luna_test_red(arrow) + 0x30
		assert luna_test_green(arrow) > luna_test_blue(arrow) + 0x30

		// Pins stay bold above a rule, and Turn Off Computer offers Sleep on
		// machines that support it.
		desktop.start_pins = [2]
		desktop.idle.sleep_available = true
		desktop.handle_start_action(action_start_power)
		luna_test_full_frame(mut desktop)
		pinned_tree := desktop.build_tree()
		pinned_menu := luna_test_find(&pinned_tree, action_start_panel) or { panic('no Start menu') }
		pinned := luna_test_labelled(&pinned_menu, app_title_text(available_apps[2].title)) or {
			panic('no pinned program')
		}
		assert pinned.text_style.bold
		assert luna_test_find(&pinned_menu, 'start.pins.rule') != none
		assert luna_test_pictured(&pinned_menu, 'builtin:luna_sleep')
		free_tree(pinned_tree)
		sleep := desktop.hit_target_named(action_start_sleep) or { panic('no Sleep') }
		again := desktop.hit_target_named(action_start_restart) or { panic('no Restart') }
		assert sleep.y > again.y && sleep.x == again.x && sleep.x > 0
		yellow := luna_test_pixel(&desktop, sleep.x + 6, sleep.y + 8)
		assert luna_test_red(yellow) > luna_test_blue(yellow) + 0x60
		assert luna_test_green(yellow) > luna_test_blue(yellow) + 0x40
	}
}

fn test_windows_xp_start_button_is_green_in_the_corner() {
	for scale in [1, 2] {
		mut desktop := luna_menu_test_desktop(scale)
		luna_test_full_frame(mut desktop)
		top := 600 - classic_taskbar_height
		middle := top + classic_taskbar_height / 2
		start := desktop.hit_target_named(action_start_toggle) or { panic('no Start button') }
		// The whole height of the bar from the screen's corner, as wide as its
		// mark and its word need.
		assert start.x == 0 && start.y == top && start.height == classic_taskbar_height
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
			luna_test_pixel(&desktop, 0, top + classic_taskbar_height - 2)] {
			assert luna_test_green(corner) > luna_test_red(corner) + 0x30
			assert luna_test_green(corner) > luna_test_blue(corner) + 0x30
		}
		assert luna_test_pixel(&desktop, start.width - 1, top) == luna_gradient(luna_bar, 0, classic_taskbar_height)
		assert luna_test_pixel(&desktop, start.width - 1, top + classic_taskbar_height - 1) == luna_gradient(luna_bar,
			classic_taskbar_height - 1, classic_taskbar_height)
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
			assert plain.height < classic_taskbar_height
			assert !desktop.start_menu_luna()
			own := desktop.start_menu_rect()
			assert int(own.x) > 0 && int(own.width) == start_menu_preferred_width
			assert desktop.start_menu_pane_height() == int(own.height) - 14
			assert desktop.start_menu_search_y(400) == 400 - start_menu_search_height - 8
		}
		desktop.settings.theme = .windows_xp
	}
}

fn test_other_themes_keep_their_original_start_destinations() {
	for kind in [ThemeKind.default_, .macos, .windows7] {
		mut desktop := luna_menu_test_desktop(1)
		desktop.settings.theme = kind
		desktop.toggle_start_menu()
		luna_test_full_frame(mut desktop)
		for action in [action_start_files, action_start_documents, action_start_recent,
			action_start_settings, action_start_system, action_start_terminal, action_start_activity,
			action_start_welcome, action_start_shutdown, action_start_restart] {
			assert desktop.hit_target_named(action) != none, 'missing original destination: ' + action
		}
		assert desktop.hit_target_named(action_start_logoff) == none
		assert desktop.hit_target_named(action_start_power) == none
		desktop.close_start_menu()
	}
}

fn test_xp_destinations_are_translated_with_complete_glyphs_and_footer_bounds() {
	mut desktop := luna_menu_test_desktop(1)
	defer { set_desktop_language(.en) }
	for language in desktop_languages {
		set_desktop_language(language)
		for link in luna_menu_links {
			assert link.key in desktop_translations[language.code()]
			for r in tr(link.key).runes() {
				if r == ` ` { continue }
				for face in desktop.fonts {
					glyph := face.glyph_for(u32(r))
					assert glyph.width > 0 && glyph.height > 0, language.code() + ': missing XP glyph'
				}
			}
		}
		for key in ['start.xp.turn_off', 'start.xp.log_off', 'start.xp.internet'] {
			assert key in desktop_translations[language.code()]
		}
		begin_frame_elements()
		menu := desktop.start_menu_element()
		power := luna_test_find(&menu, action_start_power) or { panic('no Turn Off Computer') }
		logoff := luna_test_find(&menu, action_start_logoff) or { panic('no Log Off') }
		assert logoff.frame.x >= 0
		assert logoff.frame.x + logoff.frame.width < power.frame.x
		assert power.frame.x + power.frame.width < menu.frame.width
		free_tree(menu)
	}
}

fn test_windows_xp_session_choices_and_run_dispatch_from_pointer_targets() {
	mut desktop := luna_menu_test_desktop(1)
	desktop.running = true
	desktop.toggle_start_menu()
	for action in [action_start_power, action_start_panel, action_start_run] {
		luna_test_full_frame(mut desktop)
		target := desktop.hit_target_named(action) or { panic('missing action: ' + action) }
		// Empty space near the columns' edge belongs to the panel.
		x := if action == action_start_panel { target.x + 2 } else { target.x + target.width / 2 }
		y := if action == action_start_panel { target.y + 3 } else { target.y + target.height / 2 }
		desktop.on_pointer_down(x, y)
		desktop.on_pointer_up(x, y)
		if action == action_start_power {
			assert desktop.start_menu_open && desktop.start_menu_power_open && desktop.running
			luna_test_full_frame(mut desktop)
			assert desktop.hit_target_named(action_start_shutdown) != none
			assert desktop.hit_target_named(action_start_restart) != none
		} else if action == action_start_panel {
			assert desktop.start_menu_open && !desktop.start_menu_power_open
		} else {
			assert !desktop.start_menu_open && desktop.switcher.quick_launch
		}
	}
	desktop.switcher_close()
	desktop.toggle_start_menu()
	luna_test_full_frame(mut desktop)
	logoff := desktop.hit_target_named(action_start_logoff) or { panic('no Log Off') }
	desktop.on_pointer_down(logoff.x + 8, logoff.y + 8)
	desktop.on_pointer_up(logoff.x + 8, logoff.y + 8)
	assert !desktop.start_menu_open && !desktop.running
	assert desktop.power == .keep_running
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
		top := 600 - classic_taskbar_height
		y := int(desktop.start_menu_rect().y)
		// The top corner and frame, the two columns, the
		// menu's edge over a window, and the foot with the Start button.
		for area in [[0, y - 4, 90, 100], [100, y + 50, 200, 40], [200, y + 200, 120, 90],
			[400, y + 30, 80, 300], [0, top - 60, 300, 60 + classic_taskbar_height],
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

fn test_windows_xp_task_buttons_are_raised_with_an_icon_and_a_title() {
	for scale in [1, 2] {
		mut desktop := luna_menu_test_desktop(scale)
		first := desktop.spawn('Welcome', .welcome, 100, 60, 300, 220)
		second := desktop.spawn('Notes', .notes, 200, 150, 300, 200)
		luna_test_full_frame(mut desktop)
		top := 600 - classic_taskbar_height
		raised := desktop.hit_target_named('task.${first}') or { panic('no task button') }
		pressed := desktop.hit_target_named('task.${second}') or { panic('no task button') }
		// Nearly the height of the bar, in its middle, one after the other.
		assert raised.height == luna_task_height && pressed.height == luna_task_height
		assert raised.y == top + (classic_taskbar_height - luna_task_height) / 2
		assert pressed.x == raised.x + raised.width + taskbar_item_gap
		// A button is the window's icon and then its title, in plain type. A
		// window with no icon of its own has the mark its title bar has.
		tree := desktop.build_tree()
		button := luna_test_find(&tree, 'task.${first}') or { panic('no task button') }
		assert button.text == 'Welcome' && button.image_path == 'builtin:window'
		assert button.text_style.size == luna_task_text_size && !button.text_style.bold
		assert button.text_style.color == 0xffffff
		free_tree(tree)
		mut marked := 0
		for x in raised.x + luna_task_inset .. raised.x + luna_task_inset + luna_task_icon {
			if luna_test_pixel(&desktop, x, raised.y + raised.height / 2) == 0xffffff {
				marked++
			}
		}
		assert marked > 0

		// Raised: its own blue through the middle, lighter toward the top and
		// darker toward the bottom, with round corners the bar shows in.
		x := raised.x + raised.width - 8
		middle := raised.y + raised.height / 2
		assert luna_test_pixel(&desktop, x, middle) == luna_bar_button
		assert luna_test_pixel(&desktop, x, raised.y + 3) == luna_bar_face_color(luna_bar_button, 3,
			luna_task_height, false)
		assert luna_test_green(luna_test_pixel(&desktop, x, raised.y + 3)) > luna_test_green(luna_bar_button)
		assert luna_test_green(luna_test_pixel(&desktop, x, raised.y + raised.height - 4)) < luna_test_green(luna_bar_button)
		assert luna_test_pixel(&desktop, raised.x, raised.y) == luna_gradient(luna_bar, raised.y - top,
			classic_taskbar_height)
		// Pressed in, for the window in front: the other way about.
		px := pressed.x + pressed.width - 8
		assert luna_test_pixel(&desktop, px, middle) == luna_bar_button_pressed
		assert luna_test_green(luna_test_pixel(&desktop, px, pressed.y + 3)) < luna_test_green(luna_bar_button_pressed)
		assert luna_test_green(luna_test_pixel(&desktop, px, pressed.y + pressed.height - 4)) > luna_test_green(luna_bar_button_pressed)
		// Lighter under the pointer.
		desktop.set_hover('task.${first}')
		luna_test_full_frame(mut desktop)
		assert luna_test_pixel(&desktop, x, middle) == luna_bar_button_hover
		desktop.set_hover('')
	}
	// A button too short to shade is one colour, and the middle of any is.
	assert luna_bar_face_color(0x123456, 2, 6, false) == 0x123456
	assert luna_bar_face_color(0x123456, 17, 34, false) == 0x123456
	assert luna_bar_face_color(0x123456, 17, 34, true) == 0x123456
}

fn test_windows_xp_quick_launch_is_icons_alone() {
	mut desktop := luna_menu_test_desktop(1)
	desktop.pinned_apps = [0, 3]
	window := desktop.spawn('Welcome', .welcome, 100, 60, 300, 220)
	luna_test_full_frame(mut desktop)
	top := 600 - classic_taskbar_height
	layout := desktop.taskbar_layout(3)
	files := desktop.hit_target_named(taskbar_pin_actions[0]) or { panic('no pinned Files') }
	terminal := desktop.hit_target_named(taskbar_pin_actions[3]) or { panic('no pinned Terminal') }
	task := desktop.hit_target_named('task.${window}') or { panic('no task button') }
	// Two narrow slots, then the window's button with the room that is left.
	assert desktop.taskbar_quick_count() == 2
	assert files.width == luna_quick_side && files.height == luna_quick_side
	assert files.x == layout.entries_left + (luna_quick_width - luna_quick_side) / 2
	assert terminal.x == files.x + luna_quick_width + taskbar_item_gap
	assert task.x == layout.entries_left + 2 * (luna_quick_width + taskbar_item_gap)
	assert task.width == layout.item_width && task.width == taskbar_item_width
	assert task.height == luna_task_height
	// What is in Quick Launch has no name on the bar and no box at rest.
	tree := desktop.build_tree()
	quick := luna_test_find(&tree, taskbar_pin_actions[0]) or { panic('no pinned Files') }
	assert quick.text.len == 0 && quick.box.transparent
	assert luna_test_pictured(&tree, available_apps[0].icon)
	assert luna_test_pictured(&tree, available_apps[3].icon)
	free_tree(tree)
	corner := luna_gradient(luna_bar, files.y + 1 - top, classic_taskbar_height)
	assert luna_test_pixel(&desktop, files.x + 1, files.y + 1) == corner
	// Under the pointer it is in a raised square.
	desktop.set_hover(taskbar_pin_actions[0])
	luna_test_full_frame(mut desktop)
	assert luna_test_pixel(&desktop, files.x + 2, files.y + files.height / 2) == luna_bar_button_hover
	desktop.set_hover('')
	luna_test_full_frame(mut desktop)

	// Dragging finds each slot where the bar draws it, narrow or wide.
	for x in [0, files.x + 3, files.x + luna_quick_width - 1] {
		under := desktop.taskbar_entry_under(x) or { panic('no entry under the pointer') }
		assert under.key == taskbar_pin_actions[0]
	}
	second := desktop.taskbar_entry_under(terminal.x + 3) or { panic('no entry under the pointer') }
	assert second.key == taskbar_pin_actions[3]
	for x in [task.x, task.x + task.width / 2, task.x + task.width + 300] {
		under := desktop.taskbar_entry_under(x) or { panic('no entry under the pointer') }
		assert under.id == 'task.${window}'
	}

	// Once it has a window, a pinned program is a button like any other.
	index := desktop.window_index(window) or { panic('missing window') }
	desktop.windows[index].factory_index = 0
	assert desktop.taskbar_quick_count() == 1
	luna_test_full_frame(mut desktop)
	running := desktop.hit_target_named(taskbar_pin_actions[0]) or { panic('no pinned Files') }
	idle := desktop.hit_target_named(taskbar_pin_actions[3]) or { panic('no pinned Terminal') }
	assert running.x == layout.entries_left && running.height == luna_task_height
	assert running.width == desktop.taskbar_layout(2).item_width
	assert idle.x == running.x + running.width + taskbar_item_gap + (luna_quick_width - luna_quick_side) / 2
	assert idle.width == luna_quick_side

	// The other themes give every entry one width.
	assert desktop.taskbar_slot_width(true, 0, 168) == luna_quick_width
	assert desktop.taskbar_slot_width(true, 1, 168) == 168
	assert desktop.taskbar_slot_width(false, 0, 168) == 168
	for kind in [ThemeKind.default_, ThemeKind.windows7, ThemeKind.macos] {
		desktop.settings.theme = kind
		assert desktop.taskbar_quick_count() == 0
		assert desktop.taskbar_slot_width(true, 0, 168) == 168
	}
}

fn test_windows_xp_clock_is_small_plain_and_in_the_middle() {
	mut desktop := luna_menu_test_desktop(1)
	luna_test_full_frame(mut desktop)
	layout := desktop.taskbar_layout(0)
	tree := desktop.build_tree()
	time := luna_test_find(&tree, 'clock.time') or { panic('no clock') }
	date := luna_test_find(&tree, 'clock.date') or { panic('no date') }
	built := luna_test_find(&tree, 'build.time') or { panic('no build stamp') }
	// White and plain, the time over the date about the middle of the bar.
	assert time.text == desktop.taskbar_clock_time && date.text == desktop.taskbar_clock_date
	assert date.text.len > 0
	assert time.text_style.size == luna_clock_time_size && !time.text_style.bold
	assert date.text_style.size == luna_clock_date_size && !date.text_style.bold
	assert time.text_style.color == 0xffffff && date.text_style.color == 0xffffff
	assert int(time.frame.y) == (classic_taskbar_height - luna_clock_time_rows - luna_clock_date_rows) / 2
	assert int(date.frame.y) == int(time.frame.y) + luna_clock_time_rows
	assert !built.text_style.bold && built.text_style.size == luna_clock_time_size
	// Its box is what its type needs, at the end of the notification area.
	box := desktop.luna_clock_box()
	assert box > 0 && box < taskbar_clock_width
	assert desktop.taskbar_clock_box() == box && desktop.clock_text_width() == box
	assert int(time.frame.width) == box
	assert int(time.frame.x + time.frame.width) == layout.status_right
	assert desktop.taskbar_build_box() < taskbar_build_width
	assert int(built.frame.x + built.frame.width) + taskbar_item_gap == int(time.frame.x)
	free_tree(tree)

	// With no date on show the time is alone in the middle, as Windows XP
	// shows it, and its box is no wider than the time.
	desktop.settings.clock_show_date = false
	desktop.settings.clock_show_weekday = false
	desktop.settings.clock_show_seconds = false
	desktop.settings.clock_24_hour = false
	desktop.taskbar_clock_sampled = false
	desktop.update_taskbar_clock_at(1_760_000_000)
	alone_tree := desktop.build_tree()
	alone := luna_test_find(&alone_tree, 'clock.time') or { panic('no clock') }
	under := luna_test_find(&alone_tree, 'clock.date') or { panic('no date') }
	assert under.text.len == 0
	assert alone.text.ends_with('M')
	assert int(alone.frame.y) == (classic_taskbar_height - luna_clock_time_rows) / 2
	assert int(alone.frame.width) == desktop.luna_clock_box() && desktop.luna_clock_box() <= box
	free_tree(alone_tree)

	// A second input source has its badge between the build stamp and the
	// time, clear of both.
	desktop.settings.keyboard_layouts = 3
	luna_test_full_frame(mut desktop)
	badge_tree := desktop.build_tree()
	clock := luna_test_find(&badge_tree, 'clock.time') or { panic('no clock') }
	stamp := luna_test_find(&badge_tree, 'build.time') or { panic('no build stamp') }
	input := desktop.hit_target_named(action_tray_input) or { panic('no input badge') }
	assert input.x + input.width <= int(clock.frame.x)
	assert input.x >= int(stamp.frame.x + stamp.frame.width)
	free_tree(badge_tree)

	// The default bar only reserves its time; the classic themes keep both boxes.
	for kind in [ThemeKind.default_, ThemeKind.windows7, ThemeKind.macos] {
		desktop.settings.theme = kind
		assert desktop.taskbar_clock_box() == if kind == .default_ { compact_clock_width } else { taskbar_clock_width }
		assert desktop.taskbar_build_box() == if kind == .default_ { 0 } else { taskbar_build_width }
		assert !desktop.taskbar_luna()
	}
}

fn test_windows_xp_bar_boxes_only_what_is_pressed_or_under_the_pointer() {
	for scale in [1, 2] {
		mut desktop := luna_menu_test_desktop(scale)
		desktop.spawn('Welcome', .welcome, 100, 60, 300, 220)
		luna_test_full_frame(mut desktop)
		top := 600 - classic_taskbar_height
		tree := desktop.build_tree()
		overview := luna_test_find(&tree, action_window_overview) or { panic('no overview button') }
		current := luna_test_find(&tree, workspace_action_ids[0]) or { panic('no pager') }
		other := luna_test_find(&tree, workspace_action_ids[1]) or { panic('no pager') }
		// The overview and the workspaces not on show are an icon and numbers.
		assert overview.box.transparent && other.box.transparent && !current.box.transparent
		// The hidden icons come out of Windows XP's round button.
		assert luna_test_pictured(&tree, 'builtin:luna_chevron')
		assert !luna_test_pictured(&tree, 'builtin:chevron_up')
		free_tree(tree)
		beside := desktop.hit_target_named(workspace_action_ids[1]) or { panic('no pager') }
		assert luna_test_pixel(&desktop, beside.x + 1, beside.y + 1) == luna_gradient(luna_bar, beside.y +
			1 - top, classic_taskbar_height)
		shown := desktop.hit_target_named(workspace_action_ids[0]) or { panic('no pager') }
		assert luna_test_pixel(&desktop, shown.x + shown.width - 3, shown.y + shown.height / 2) == luna_bar_button_pressed
		grid := desktop.hit_target_named(action_window_overview) or { panic('no overview button') }
		assert luna_test_pixel(&desktop, grid.x + 1, grid.y + 1) == luna_gradient(luna_bar, grid.y +
			1 - top, classic_taskbar_height)

		// The round button: a blue disc, brighter under the pointer, with the
		// notification area's own blue outside it.
		chevron := desktop.hit_target_named(action_tray_overflow) or { panic('no hidden icons button') }
		center_x := chevron.x + chevron.width / 2
		center_y := chevron.y + chevron.height / 2
		disc := luna_test_pixel(&desktop, center_x + 4, center_y + 3)
		assert luna_test_blue(disc) > luna_test_red(disc) + 0x40
		assert luna_test_pixel(&desktop, chevron.x, chevron.y) == luna_gradient(luna_tray, chevron.y - top,
			classic_taskbar_height)
		desktop.set_hover(action_tray_overflow)
		luna_test_full_frame(mut desktop)
		lit := luna_test_pixel(&desktop, center_x + 4, center_y + 3)
		assert luna_test_red(lit) > luna_test_red(disc) && luna_test_green(lit) > luna_test_green(disc)
		desktop.set_hover(action_window_overview)
		luna_test_full_frame(mut desktop)
		assert luna_test_pixel(&desktop, grid.x + 2, grid.y + 4) == luna_bar_face_color(luna_bar_button_hover,
			4, grid.height, false)
		desktop.set_hover('')
	}
}

fn test_windows_xp_taskbar_partial_frames_match_full_ones() {
	for scale in [1, 2] {
		mut desktop := luna_menu_test_desktop(scale)
		desktop.pinned_apps = [0, 3]
		first := desktop.spawn('Welcome', .welcome, 100, 60, 300, 220)
		desktop.spawn('Notes', .notes, 200, 150, 300, 200)
		luna_test_full_frame(mut desktop)
		before := luna_test_pixels(&desktop)
		top := 600 - classic_taskbar_height
		// The Start button with Quick Launch, part of two buttons, the pager
		// with the notification area, and the whole bar.
		for area in [[0, top - 6, 200, classic_taskbar_height + 6], [230, top + 10, 220, 20],
			[640, top, 384, classic_taskbar_height], [0, top, 1024, classic_taskbar_height]] {
			luna_test_partial_frame(mut desktop, area[0], area[1], area[2], area[3])
			luna_test_same(&desktop, luna_test_pixels(&desktop), before)
		}
		// The pointer over each kind of thing on the bar, and off it again.
		for action in ['task.${first}', taskbar_pin_actions[0], action_tray_overflow,
			action_window_overview, workspace_action_ids[1]] {
			for lit in [action, ''] {
				old := if lit.len > 0 { '' } else { action }
				desktop.set_hover(lit)
				assert desktop.damage_hover_change(old, lit)
				hover := desktop.frame_damage
				desktop.frame_damage = FrameDamage{}
				assert hover.count > 0
				for i in 0 .. hover.count {
					luna_test_partial_frame(mut desktop, hover.rects[i].x, hover.rects[i].y,
						hover.rects[i].w, hover.rects[i].h)
				}
				partial := luna_test_pixels(&desktop)
				luna_test_full_frame(mut desktop)
				luna_test_same(&desktop, partial, luna_test_pixels(&desktop))
			}
		}
	}
}
