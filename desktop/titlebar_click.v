// SPDX-License-Identifier: GPL-2.0-or-later
module main

// A double click is deliberately a small, fixed gesture here. Vinix does not
// have a system-wide mouse preference yet, so keep the timing and movement
// allowance beside the recogniser that consumes them.
const titlebar_double_click_interval_ms = u64(500)
const titlebar_double_click_slop = 5

// TitlebarClick retains no strings or tree nodes: the compositor has no garbage
// collector, and all a second press needs is the window, place, time, and frame
// the first press started from.
struct TitlebarClick {
	window_id     int
	x             int
	y             int
	window_x      int
	window_y      int
	window_width  int
	window_height int
	maximized     bool
	at_ms         u64
}

fn titlebar_action_window_id(action string) ?int {
	if !action.starts_with('win.') {
		return none
	}
	rest := action[4..]
	dot := rest.index('.') or { return none }
	if rest[dot + 1..] != 'titlebar' {
		return none
	}
	id := rest[..dot].int()
	if id <= 0 {
		return none
	}
	return id
}

fn titlebar_click_matches(previous TitlebarClick, id int, x int, y int, now_ms u64) bool {
	if previous.window_id != id || previous.at_ms == ~u64(0) || now_ms == ~u64(0)
		|| now_ms < previous.at_ms {
		return false
	}
	if now_ms - previous.at_ms > titlebar_double_click_interval_ms {
		return false
	}
	return x >= previous.x - titlebar_double_click_slop
		&& x <= previous.x + titlebar_double_click_slop
		&& y >= previous.y - titlebar_double_click_slop
		&& y <= previous.y + titlebar_double_click_slop
}

// titlebar_pointer_down_at sits in front of the ordinary single-click handler.
// The first press remains exactly the same focus/drag operation it was before;
// a matching second press performs the same toggle as the maximise button.
// Restoring the frame captured at the first press also cancels tiny drag jitter
// between the two clicks, so a double click on a maximised title bar restores
// rather than immediately maximising again.
fn (mut d Desktop) titlebar_pointer_down_at(previous TitlebarClick, x int, y int, now_ms u64) TitlebarClick {
	action := d.hit_action(x, y)
	id := titlebar_action_window_id(action) or {
		d.on_pointer_down(x, y)
		return TitlebarClick{}
	}
	index := d.window_index(id) or {
		d.on_pointer_down(x, y)
		return TitlebarClick{}
	}

	if titlebar_click_matches(previous, id, x, y, now_ms) {
		// A title-bar press begins a drag immediately. If the pointer shifted a
		// pixel or two before release, put the window back where the first press
		// found it before applying the maximise button's exact toggle semantics.
		d.drag = Drag{}
		d.windows[index].x = previous.window_x
		d.windows[index].y = previous.window_y
		d.windows[index].width = previous.window_width
		d.windows[index].height = previous.window_height
		d.windows[index].maximized = previous.maximized
		d.hover = action
		d.dirty = true
		d.toggle_maximize(id)
		return TitlebarClick{}
	}

	next := TitlebarClick{
		window_id: id
		x: x
		y: y
		window_x: d.windows[index].x
		window_y: d.windows[index].y
		window_width: d.windows[index].width
		window_height: d.windows[index].height
		maximized: d.windows[index].maximized
		at_ms: now_ms
	}
	d.on_pointer_down(x, y)
	return next
}
