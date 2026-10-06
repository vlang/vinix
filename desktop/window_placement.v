// SPDX-License-Identifier: GPL-2.0-or-later
// Pointer placement and its glass preview. Keyboard tiling shares the same
// WindowSnap states, including the four quarters of the usable desktop.
module main

import ui2

const window_placement_corner_extent = 64
const window_placement_preview_id = 'desktop.window-placement'
const window_placement_preview_alpha = u32(42)
const window_placement_preview_edge_alpha = u32(196)
const window_placement_preview_inset = 6

struct WindowPlacement {
	snap     WindowSnap
	maximize bool
}

// Only touching a boundary commits placement. Moving one pixel back inside
// the desktop is enough to cancel a preview and continue a free drag.
fn window_placement_at(x int, y int, screen_width int, screen_height int) WindowPlacement {
	if screen_width <= 0 || screen_height <= 0 {
		return WindowPlacement{}
	}
	usable_height := desktop_usable_height(screen_height)
	corner_width := if screen_width / 4 < window_placement_corner_extent {
		screen_width / 4
	} else {
		window_placement_corner_extent
	}
	corner_height := if usable_height / 4 < window_placement_corner_extent {
		usable_height / 4
	} else {
		window_placement_corner_extent
	}
	left := x <= 0
	right := x >= screen_width - 1
	top := y <= 0
	bottom := y >= usable_height - 1
	near_left := x < corner_width
	near_right := x >= screen_width - corner_width
	near_top := y < corner_height
	near_bottom := y >= usable_height - corner_height
	if (left && near_top) || (top && near_left) {
		return WindowPlacement{ snap: .top_left }
	}
	if (right && near_top) || (top && near_right) {
		return WindowPlacement{ snap: .top_right }
	}
	// The bottom corners belong to the work area above the taskbar, so they
	// are reachable without dragging the title bar under the bar itself.
	if (left && near_bottom) || (bottom && near_left) {
		return WindowPlacement{ snap: .bottom_left }
	}
	if (right && near_bottom) || (bottom && near_right) {
		return WindowPlacement{ snap: .bottom_right }
	}
	if top {
		return WindowPlacement{ maximize: true }
	}
	if left {
		return WindowPlacement{ snap: .left }
	}
	if right {
		return WindowPlacement{ snap: .right }
	}
	return WindowPlacement{}
}

// Some absolute-pointer backends wrap an edge-crossing button-up packet to
// the opposite boundary. Keep the placement seen while the button was held
// in that case; an ordinary release inside the desktop still cancels it.
fn window_placement_on_release(held WindowPlacement, x int, y int, screen_width int,
	screen_height int) WindowPlacement {
	if held.maximize && y >= screen_height - 1 {
		return held
	}
	left := held.snap in [.left, .top_left, .bottom_left]
	right := held.snap in [.right, .top_right, .bottom_right]
	top := held.snap in [.top_left, .top_right]
	bottom := held.snap in [.bottom_left, .bottom_right]
	if (left && x >= screen_width - 1) || (right && x <= 0)
		|| (top && y >= screen_height - 1) || (bottom && y <= 0) {
		return held
	}
	return window_placement_at(x, y, screen_width, screen_height)
}

// This frame matches apply_snap_geometry, including the remainder on odd
// display sizes, and is also the full-size frame for a maximize preview.
fn window_placement_frame(placement WindowPlacement, screen_width int, screen_height int) DamageRect {
	if screen_width <= 0 || screen_height <= 0
		|| (!placement.maximize && placement.snap == .none_) {
		return DamageRect{}
	}
	usable_height := desktop_usable_height(screen_height)
	if placement.maximize {
		return DamageRect{ x: 0, y: 0, w: screen_width, h: usable_height, valid: true }
	}
	half_width := screen_width / 2
	half_height := usable_height / 2
	right := placement.snap in [.right, .top_right, .bottom_right]
	top := placement.snap in [.top_left, .top_right]
	bottom := placement.snap in [.bottom_left, .bottom_right]
	return DamageRect{
		x:     if right { half_width } else { 0 }
		y:     if bottom { half_height } else { 0 }
		w:     if right { screen_width - half_width } else { half_width }
		h:     if top {
			half_height
		} else if bottom {
			usable_height - half_height
		} else {
			usable_height
		}
		valid: true
	}
}

fn (mut d Desktop) update_window_placement(x int, y int) {
	if d.drag.kind != .move {
		return
	}
	placement := window_placement_at(x, y, d.canvas.width, d.canvas.height)
	if placement.snap == d.drag.snap_on_release
		&& placement.maximize == d.drag.maximize_on_release {
		return
	}
	d.drag.snap_on_release = placement.snap
	d.drag.maximize_on_release = placement.maximize
	// A preview can cover pixels well outside the moving window. Include its
	// previous and new footprints in the drag's partial repaint; a whole
	// canvas region keeps transitions between quarters and maximize simple.
	d.add_damage_rect(0, 0, d.canvas.width, d.canvas.height)
	d.dirty = true
}

fn (mut d Desktop) finish_window_placement(x int, y int) {
	if d.drag.kind != .move || !d.drag.moved {
		return
	}
	held := WindowPlacement{
		snap:     d.drag.snap_on_release
		maximize: d.drag.maximize_on_release
	}
	placement := window_placement_on_release(held, x, y, d.canvas.width, d.canvas.height)
	if placement.maximize {
		d.maximize(d.drag.window_id)
	} else if placement.snap != .none_ {
		d.snap_window(d.drag.window_id, placement.snap)
	}
}

fn (d &Desktop) window_placement_element() ?ui2.Element {
	if d.drag.kind != .move || !d.drag.moved || d.buttons & button_left == 0 {
		return none
	}
	frame := window_placement_frame(WindowPlacement{
		snap:     d.drag.snap_on_release
		maximize: d.drag.maximize_on_release
	}, d.canvas.width, d.canvas.height)
	if !frame.valid || frame.w <= 2 * window_placement_preview_inset
		|| frame.h <= 2 * window_placement_preview_inset {
		return none
	}
	// A plain view paints glass but contributes no hit target. Its ID and
	// style are literals, and it needs no per-frame child array or strings.
	return ui2.Element{
		kind:  .view
		id:    window_placement_preview_id
		frame: ui2.rect(f64(frame.x + window_placement_preview_inset),
			f64(frame.y + window_placement_preview_inset),
			f64(frame.w - 2 * window_placement_preview_inset),
			f64(frame.h - 2 * window_placement_preview_inset))
		box:   ui2.BoxStyle{ bg: app_accent, radius: 8 }
	}
}
