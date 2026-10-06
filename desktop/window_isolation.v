// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module main

// Three deliberate horizontal reversals in one short gesture. Small pointer
// jitter, slow positioning and vertical drags never hide another window.
const window_shake_stroke = 32
const window_shake_vertical_slop = 48
const window_shake_interval_ms = i64(1000)

struct WindowShake {
mut:
	started   i64
	extreme_x int
	origin_y  int
	direction int
	reversals int
	fired     bool
}

fn new_window_shake(x int, y int, now i64) WindowShake {
	return WindowShake{
		started: now
		extreme_x: x
		origin_y: y
	}
}

fn (mut shake WindowShake) sample(x int, y int, now i64) bool {
	if shake.fired {
		return false
	}
	if now < shake.started || now - shake.started > window_shake_interval_ms
		|| y < shake.origin_y - window_shake_vertical_slop
		|| y > shake.origin_y + window_shake_vertical_slop {
		shake = new_window_shake(x, y, now)
		return false
	}
	if shake.direction == 0 {
		if x >= shake.extreme_x + window_shake_stroke {
			shake.direction = 1
			shake.extreme_x = x
		} else if x <= shake.extreme_x - window_shake_stroke {
			shake.direction = -1
			shake.extreme_x = x
		}
		return false
	}
	if (shake.direction > 0 && x > shake.extreme_x)
		|| (shake.direction < 0 && x < shake.extreme_x) {
		shake.extreme_x = x
	} else if (shake.direction > 0 && x <= shake.extreme_x - window_shake_stroke)
		|| (shake.direction < 0 && x >= shake.extreme_x + window_shake_stroke) {
		shake.direction = -shake.direction
		shake.extreme_x = x
		shake.reversals++
		if shake.reversals >= 3 {
			shake.fired = true
			return true
		}
	}
	return false
}

// Restoration ownership lives on each window. This uses no per-gesture array,
// and independent workspaces retain independent Hide Others sessions.
struct WindowIsolation {
mut:
	active bool
}

fn (mut d Desktop) restore_isolated_windows() {
	if !d.window_isolation[d.current_workspace].active {
		return
	}
	for i in 0 .. d.windows.len {
		if d.windows[i].workspace == d.current_workspace && d.windows[i].hidden_by_isolation {
			d.windows[i].hidden_by_isolation = false
			d.windows[i].minimized = false
		}
	}
	d.window_isolation[d.current_workspace].active = false
	// Preserve the focused window and painting order; otherwise use the most
	// recently raised restored window when no visible window holds focus.
	if d.focus == 0 {
		d.focus_top_window_in_current_workspace()
	}
	d.isolation_changed()
}

fn (mut d Desktop) toggle_window_isolation(id int) {
	index := d.window_index(id) or { return }
	if d.windows[index].workspace != d.current_workspace || d.windows[index].minimized {
		return
	}
	if d.window_isolation[d.current_workspace].active {
		d.restore_isolated_windows()
		return
	}
	mut hidden := false
	for i in 0 .. d.windows.len {
		if d.windows[i].id != id && d.windows[i].workspace == d.current_workspace
			&& !d.windows[i].minimized {
			d.windows[i].hidden_by_isolation = true
			d.windows[i].minimized = true
			hidden = true
		}
	}
	if hidden {
		d.window_isolation[d.current_workspace].active = true
		d.focus = id
		d.isolation_changed()
	}
}

fn (mut d Desktop) isolation_changed() {
	d.end_peek()
	d.close_taskbar_preview()
	if d.drag.kind == .move {
		// A partial moving-window repaint cannot reveal windows elsewhere.
		d.add_damage_rect(0, 0, d.canvas.width, d.canvas.height)
	}
	d.dirty = true
}
