// SPDX-License-Identifier: GPL-2.0-or-later
// Window-manager side of desktop scaling. Kept separate from scale.v so the
// Settings unit tests can stage scale policy without the whole compositor.
module main

fn desktop_rescale_coordinate(value int, old_extent int, new_extent int) int {
	if old_extent <= 0 || old_extent == new_extent {
		return value
	}
	return int(i64(value) * i64(new_extent) / i64(old_extent))
}

fn desktop_usable_height(screen_height int) int {
	usable := screen_height - taskbar_height
	if usable >= default_title_height {
		return usable
	}
	return screen_height
}

fn desktop_clamp_scaled_position(x int, y int, width int, height int, screen_width int, screen_height int) (int, int) {
	mut next_x := x
	mut next_y := y
	margin := 60
	if width >= screen_width {
		next_x = 0
	} else {
		max_x := screen_width - margin
		if next_x > max_x {
			next_x = max_x
		}
		if next_x + width < margin {
			next_x = margin - width
		}
	}

	usable_height := desktop_usable_height(screen_height)
	if height >= usable_height {
		next_y = 0
	} else {
		max_y := usable_height - default_title_height
		if next_y < 0 {
			next_y = 0
		}
		if next_y > max_y {
			next_y = max_y
		}
	}
	return next_x, next_y
}

// Settings changes only the requested global. The main loop applies it here,
// between input and tree construction, so one frame never mixes coordinate
// spaces. Windows retain their logical sizes (therefore doubling physically at
// 200%) while their positions track the same place on the panel.
fn (mut d Desktop) apply_requested_scale() {
	target := desktop_requested_scale()
	if !desktop_scale_valid(target) {
		desktop_restore_requested_scale()
		return
	}
	if target == desktop_current_scale() {
		return
	}

	old_width := d.canvas.width
	old_height := d.canvas.height
	new_width, new_height := desktop_scaled_physical_extents(target)
	if new_width <= 0 || new_height <= 0 {
		desktop_restore_requested_scale()
		return
	}

	old_pixels := d.canvas.pixels
	d.canvas = new_canvas(new_width, new_height)
	unsafe { free(voidptr(old_pixels)) }

	d.pointer_x = desktop_rescale_coordinate(d.pointer_x, old_width, new_width)
	d.pointer_y = desktop_rescale_coordinate(d.pointer_y, old_height, new_height)
	if d.pointer_x < 0 {
		d.pointer_x = 0
	} else if d.pointer_x >= new_width {
		d.pointer_x = new_width - 1
	}
	if d.pointer_y < 0 {
		d.pointer_y = 0
	} else if d.pointer_y >= new_height {
		d.pointer_y = new_height - 1
	}

	for i := 0; i < d.windows.len; i++ {
		d.windows[i].x = desktop_rescale_coordinate(d.windows[i].x, old_width, new_width)
		d.windows[i].y = desktop_rescale_coordinate(d.windows[i].y, old_height, new_height)
		d.windows[i].restore_x = desktop_rescale_coordinate(d.windows[i].restore_x, old_width,
			new_width)
		d.windows[i].restore_y = desktop_rescale_coordinate(d.windows[i].restore_y, old_height,
			new_height)

		restore_x, restore_y := desktop_clamp_scaled_position(d.windows[i].restore_x,
			d.windows[i].restore_y, d.windows[i].restore_width, d.windows[i].restore_height,
			new_width, new_height)
		d.windows[i].restore_x = restore_x
		d.windows[i].restore_y = restore_y

		if d.windows[i].maximized {
			d.windows[i].x = 0
			d.windows[i].y = 0
			d.windows[i].width = new_width
			d.windows[i].height = desktop_usable_height(new_height)
		} else {
			window_x, window_y := desktop_clamp_scaled_position(d.windows[i].x, d.windows[i].y,
				d.windows[i].width, d.windows[i].height, new_width, new_height)
			d.windows[i].x = window_x
			d.windows[i].y = window_y
		}
	}

	// Hit regions are coordinates from the old render pass. Never route a click
	// through them after the logical screen changes.
	d.targets.clear()
	d.hover = ''
	d.drag = Drag{}
	desktop_commit_scale(target)
	d.dirty = true
}
