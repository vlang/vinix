// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn glass_test_desktop(scale int) Desktop {
	mut desktop := Desktop{
		canvas: new_scaled_canvas(640, 480, 640 * scale, 480 * scale, scale)
		fonts:  load_fonts_for_scale(scale)
	}
	desktop.tray.preferences_loaded = true
	desktop.settings.theme = .windows7
	// A fixed time: nothing a comparison renders may tick in between.
	desktop.update_taskbar_clock_at(1_760_000_000)
	return desktop
}

fn glass_test_full_frame(mut desktop Desktop) {
	tree := desktop.build_tree()
	// As render_desktop_frame, without the files of a home these tests lack.
	desktop.render_clipped(tree, desktop.damage_clip(desktop.canvas_damage()), false)
	free_tree(tree)
	desktop.dirty = false
}

// glass_test_partial_frames composes what has been damaged the way the main
// loop does, frame after frame until no glass asks for another, and says how
// many frames that took.
fn glass_test_partial_frames(mut desktop Desktop) int {
	mut frames := 0
	for desktop.frame_damage.valid() {
		mut damage := desktop.frame_damage
		desktop.frame_damage = FrameDamage{}
		damage.align_to_glass()
		tree := desktop.build_tree()
		desktop.render_partial_frame(tree, mut damage, false)
		free_tree(tree)
		frames++
		assert frames < 8, 'glass keeps asking for another frame'
	}
	return frames
}

fn glass_test_pixels(desktop &Desktop) []u32 {
	count := desktop.canvas.stride * desktop.canvas.physical_height
	mut pixels := []u32{len: count}
	unsafe { vmemcpy(pixels.data, desktop.canvas.pixels, count * 4) }
	return pixels
}

// glass_test_same reports the first pixel two pictures of the canvas differ
// at, as a failed assertion a person can find on the screen.
fn glass_test_same(desktop &Desktop, partial []u32, full []u32) {
	assert partial.len == full.len
	for index in 0 .. partial.len {
		if partial[index] != full[index] {
			x := index % desktop.canvas.stride / desktop.canvas.scale
			y := index / desktop.canvas.stride / desktop.canvas.scale
			assert false, 'partial frame differs from a full one at ${x},${y}: ${partial[index].hex()} for ${full[index].hex()}'
		}
	}
}

fn glass_test_child(frame &ui2.Element, suffix string) ui2.Element {
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

fn test_windows7_frame_has_windows7_measurements() {
	assert theme_windows7.glass
	assert theme_windows7.title_height == 30
	assert theme_windows7.frame_border == 8
	assert theme_windows7.window_radius == 7
	assert theme_windows7.button_look == .aero
	assert aero_caption_width == 103
	assert aero_caption_height == 19
	assert glass_colors.len == 16
	assert glass_colors[0].color == 0x74b8fc
	assert glass_colors[15].color == 0xfbfbfb

	mut desktop := glass_test_desktop(1)
	id := desktop.spawn('Welcome', .welcome, 100, 60, 400, 300)
	frame := desktop.window_element(0)
	body := glass_test_child(&frame, '.body')
	// Eight pixels of glass beside and below the body, thirty above it.
	assert int(body.frame.x) == 8
	assert int(body.frame.y) == 30
	assert int(body.frame.width) == 400 - 16
	assert int(body.frame.height) == 300 - 30 - 8
	assert int(frame.box.radius) == 7
	// The caption group ends six pixels inside the frame and starts under its
	// top line: minimise, maximise, then the wide close.
	minimize := glass_test_child(&frame, '.minimize')
	maximize := glass_test_child(&frame, '.maximize')
	close := glass_test_child(&frame, '.close')
	assert int(minimize.frame.x) == 400 - 6 - 103
	assert int(minimize.frame.width) == 28
	assert int(maximize.frame.x) == int(minimize.frame.x) + 28
	assert int(maximize.frame.width) == 27
	assert int(close.frame.x) == int(maximize.frame.x) + 27
	assert int(close.frame.width) == 48
	assert int(close.frame.x + close.frame.width) == 400 - 6
	assert int(close.frame.y) == 1
	assert int(close.frame.height) == 19
	free_tree(frame)

	// Maximized, the frame's sides and bottom are off the screen.
	desktop.toggle_maximize(id)
	maximized := desktop.window_element(0)
	wide := glass_test_child(&maximized, '.body')
	assert int(wide.frame.x) == 0
	assert int(wide.frame.width) == 640
	assert int(wide.frame.height) == 480 - classic_taskbar_height - 30
	assert int(maximized.box.radius) == 0
	free_tree(maximized)
}

fn test_windows7_caption_buttons_are_hit_before_the_resize_edge() {
	for side in [ButtonSide.right, ButtonSide.left] {
		mut desktop := glass_test_desktop(1)
		desktop.settings.button_side = side
		id := desktop.spawn('Welcome', .welcome, 100, 60, 400, 300)
		glass_test_full_frame(mut desktop)
		close_x := if side == .right { 100 + 400 - 6 - 24 } else { 100 + 6 + 24 }
		minimize_x := if side == .right { 100 + 400 - 6 - 103 + 14 } else { 100 + 6 + 103 - 14 }
		// The frame's top line still resizes; every row under it is the button's.
		assert desktop.hit_action(close_x, 60) == 'win.${id}.resize_n'
		assert desktop.hit_action(close_x, 61) == 'win.${id}.close'
		assert desktop.hit_action(close_x, 79) == 'win.${id}.close'
		assert desktop.hit_action(minimize_x, 62) == 'win.${id}.minimize'
		assert desktop.hit_action(close_x, 82) == 'win.${id}.titlebar'
		// All eight pixels of glass at the sides and the bottom resize.
		assert desktop.hit_action(100 + 7, 200) == 'win.${id}.resize_w'
		assert desktop.hit_action(100 + 400 - 8, 200) == 'win.${id}.resize_e'
		assert desktop.hit_action(300, 60 + 300 - 8) == 'win.${id}.resize_s'
		assert desktop.hit_action(100 + 8, 200) == 'win.${id}.body'
		assert desktop.hit_action(300, 60 + 3) == 'win.${id}.resize_n'
	}
}

fn test_glass_partial_frame_of_unchanged_backdrop_changes_nothing() {
	for scale in [1, 2] {
		mut desktop := glass_test_desktop(scale)
		desktop.spawn('System', .system, 40, 40, 360, 260)
		desktop.spawn('Notes', .notes, 220, 150, 300, 220)
		glass_test_full_frame(mut desktop)
		before := glass_test_pixels(&desktop)
		// The clock ticking repaints the taskbar and nothing behind it.
		desktop.damage_taskbar()
		desktop.add_frame_damage(250, 140, 97, 61)
		assert glass_test_partial_frames(mut desktop) == 1
		assert !desktop.dirty
		after := glass_test_pixels(&desktop)
		glass_test_same(&desktop, after, before)
	}
}

fn test_glass_follows_a_change_behind_it_past_the_damaged_area() {
	for scale in [1, 2] {
		mut desktop := glass_test_desktop(scale)
		// The window's title and its left side cross the first shortcut.
		desktop.spawn('Welcome', .welcome, 60, 40, 300, 220)
		glass_test_full_frame(mut desktop)
		shortcut := desktop.hit_action(30, 30)
		assert shortcut.starts_with('shortcut.')
		// Hovering the shortcut puts a dark panel under it: only its own
		// rectangle is damaged, but the glass over and beside it shows the
		// panel blurred well past that rectangle.
		desktop.set_hover(shortcut)
		assert desktop.damage_hover_change('', shortcut)
		assert glass_test_partial_frames(mut desktop) == 2
		assert !desktop.dirty
		partial := glass_test_pixels(&desktop)
		glass_test_full_frame(mut desktop)
		full := glass_test_pixels(&desktop)
		glass_test_same(&desktop, partial, full)
	}
}

fn test_glass_window_dragged_in_a_partial_frame_matches_a_full_frame() {
	for scale in [1, 2] {
		mut desktop := glass_test_desktop(scale)
		desktop.spawn('System', .system, 60, 50, 320, 240)
		id := desktop.spawn('Notes', .notes, 200, 130, 280, 200)
		glass_test_full_frame(mut desktop)
		index := desktop.window_index(id) or { panic('missing window') }
		for step in [[37, 23], [-90, 14], [5, -61]] {
			old_x := desktop.windows[index].x
			old_y := desktop.windows[index].y
			desktop.windows[index].x += step[0]
			desktop.windows[index].y += step[1]
			desktop.add_drag_damage(old_x, old_y, desktop.windows[index].x, desktop.windows[index].y,
				0, 0, 0, 0, desktop.windows[index].width, desktop.windows[index].height)
			desktop.frame_damage.add(desktop.drag_damage)
			desktop.drag_damage = DamageRect{}
			glass_test_partial_frames(mut desktop)
			// The drag's damage reaches as far as the glass looks, so the
			// moved window's backdrop is whole without another frame.
			assert !desktop.dirty
			partial := glass_test_pixels(&desktop)
			glass_test_full_frame(mut desktop)
			full := glass_test_pixels(&desktop)
			glass_test_same(&desktop, partial, full)
		}
	}
}

fn test_glass_backdrop_made_in_a_partial_frame_asks_for_a_full_one() {
	mut desktop := glass_test_desktop(1)
	desktop.spawn('Welcome', .welcome, 100, 60, 300, 220)
	glass_test_full_frame(mut desktop)
	// A window that appears with only part of the screen repainted cannot see
	// everything its glass shows.
	desktop.spawn('Notes', .notes, 240, 160, 280, 200)
	desktop.dirty = false
	desktop.add_frame_damage(240, 160, 280, 200)
	glass_test_partial_frames(mut desktop)
	assert desktop.dirty
}

fn test_more_glass_surfaces_than_backdrops_stay_quiet() {
	mut desktop := glass_test_desktop(1)
	for i in 0 .. glass_slot_count + 4 {
		desktop.spawn('Notes', .notes, 20 + i * 14, 10 + i * 9, 180, 130)
	}
	glass_test_full_frame(mut desktop)
	mut taken := 0
	for slot in desktop.glass.slots {
		if slot.raw != unsafe { nil } {
			taken++
		}
	}
	assert taken == glass_slot_count
	// The windows left without a backdrop are painted flat, and a partial
	// frame over them neither takes another window's nor asks for a whole
	// frame: either would repeat for as long as they are all open.
	// The damage takes whole shortcuts: a builtin glyph cut by a clip samples
	// its background from outside it.
	before := glass_test_pixels(&desktop)
	desktop.add_frame_damage(288, 182, 264, 240)
	assert glass_test_partial_frames(mut desktop) == 1
	assert !desktop.dirty
	glass_test_same(&desktop, glass_test_pixels(&desktop), before)
	glass_test_full_frame(mut desktop)
	glass_test_same(&desktop, glass_test_pixels(&desktop), before)
}

fn test_glass_ignores_a_shade_nobody_can_see() {
	assert !glass_cell_differs(0x808080, 0x808080)
	assert !glass_cell_differs(0x808080, 0x82807e)
	assert glass_cell_differs(0x808080, 0x838080)
	assert glass_cell_differs(0x808080, 0x80807d)
	for scale in [1, 2] {
		mut desktop := glass_test_desktop(scale)
		// The window's shadow falls on the corner of a shortcut whose glyph
		// samples the canvas there. A partial frame that cuts the glyph paints
		// its holes a shade darker than the whole frame did; the glass above
		// neither blurs again for that nor asks for another frame.
		desktop.spawn('Notes', .notes, 314, 199, 180, 130)
		glass_test_full_frame(mut desktop)
		desktop.add_frame_damage(300, 200, 300, 200)
		assert glass_test_partial_frames(mut desktop) == 1
		assert !desktop.dirty
	}
}

fn test_glass_is_given_back_under_another_theme() {
	mut desktop := glass_test_desktop(1)
	desktop.spawn('Welcome', .welcome, 100, 60, 300, 220)
	glass_test_full_frame(mut desktop)
	assert desktop.glass.allocated
	desktop.settings.theme = .default_
	glass_test_full_frame(mut desktop)
	assert !desktop.glass.allocated
	assert !desktop.glass.active
	for slot in desktop.glass.slots {
		assert slot.raw == unsafe { nil }
		assert slot.blurred == unsafe { nil }
	}
}

fn test_glass_tint_follows_the_chosen_colour() {
	mut desktop := glass_test_desktop(1)
	// Sky is Windows 7's 8% colour, 43% afterglow and 49% blur.
	sky := desktop.glass_tint(true)
	assert sky.blur == 49 * 256 / 100
	assert sky.base == glass_scale_color(0x74b8fc, 8)
	assert sky.glow == glass_scale_color(0x74b8fc, 43)
	// An unfocused window keeps less of the colour and lets more through.
	pale := desktop.glass_tint(false)
	assert pale.blur > sky.blur
	assert pale.veil > 0
	// A strong colour takes the blur's share.
	desktop.settings.glass_color = 7
	ruby := desktop.glass_tint(true)
	assert ruby.blur < sky.blur
	assert (ruby.base >> 16) & 0xff > (ruby.base & 0xff)
	// A colour that is not one of the sixteen falls back to the first.
	desktop.settings.glass_color = 99
	assert desktop.glass_tint(true).base == sky.base
}

fn test_application_pointer_is_measured_from_the_body_inside_the_frame() {
	mut desktop := glass_test_desktop(1)
	id := desktop.spawn('Welcome', .welcome, 100, 60, 400, 300)
	index := desktop.window_index(id) or { panic('missing window') }
	assert desktop.window_border(&desktop.windows[index]) == 8
	desktop.toggle_maximize(id)
	assert desktop.window_border(&desktop.windows[index]) == 0
	desktop.settings.theme = .macos
	desktop.toggle_maximize(id)
	assert desktop.window_border(&desktop.windows[index]) == 0
}
