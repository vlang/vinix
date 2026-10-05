// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Dragging taskbar buttons to reorder them, as the Windows 7 taskbar allows.
//
// Pinned buttons keep their order in the pins file. Buttons for unpinned
// windows are ordered by each window's task rank, which starts as its id and
// is exchanged between windows as buttons move. Each kind reorders among its
// own kind, so a running program cannot silently become a pin by being
// dropped between two of them.
module main

const taskbar_drag_threshold = 6

struct TaskbarPress {
mut:
	active bool
	// The button's action and stable key at press time, both owned.
	action    string
	key       string
	pinned    bool
	app_index int = -1
	start_x   int
	start_y   int
	// Where along the button the pointer grabbed it, so a dragged button does
	// not jump to put its edge under the cursor.
	grab_offset int
	dragging    bool
	// A pinned program that is not running launches when the click completes,
	// so a press that turns into a drag does not start it.
	launch_on_release bool
}

fn taskbar_entry_action(action string) bool {
	return action.starts_with('task.') || action.starts_with(taskbar_pin_action_prefix)
}

fn (mut d Desktop) clear_taskbar_press() {
	if d.taskbar_press.action.len > 0 {
		unsafe { d.taskbar_press.action.free() }
	}
	if d.taskbar_press.key.len > 0 {
		unsafe { d.taskbar_press.key.free() }
	}
	d.taskbar_press = TaskbarPress{}
}

fn (d &Desktop) hit_target_named(action string) ?HitTarget {
	for i := d.targets.len - 1; i >= 0; i-- {
		if d.targets[i].world == .desktop && d.targets[i].action_id == action {
			return d.targets[i]
		}
	}
	return none
}

fn (mut d Desktop) begin_taskbar_press(action string, x int, y int, launch_on_release bool) {
	entry := d.taskbar_entry_for_action(action) or { return }
	d.clear_taskbar_press()
	mut grab := 0
	if target := d.hit_target_named(action) {
		grab = x - target.x
	}
	d.taskbar_press = TaskbarPress{
		active:            true
		action:            action.clone()
		key:               entry.key.clone()
		pinned:            entry.pinned
		app_index:         entry.app_index
		start_x:           x
		start_y:           y
		grab_offset:       grab
		launch_on_release: launch_on_release
	}
}

// taskbar_entry_under finds the button whose slot is under `x` in the current
// order. It is worked out from the layout rather than from the last frame's
// hit targets, so asking twice between two frames gives the same answer.
fn (d &Desktop) taskbar_entry_under(x int) ?TaskbarEntry {
	entries := d.taskbar_entries()
	defer { unsafe { entries.free() } }
	if entries.len == 0 {
		return none
	}
	layout := d.taskbar_layout(entries.len)
	stride := layout.item_width + taskbar_item_gap
	if stride <= 0 {
		return none
	}
	mut fits := (layout.entries_right - layout.entries_left + taskbar_item_gap) / stride
	if fits > entries.len {
		fits = entries.len
	}
	if fits <= 0 {
		return none
	}
	mut left := layout.entries_left
	if d.theme().dock {
		// A dock is centred, so its buttons start wherever the panel does.
		for index, entry in entries {
			if entry.key == d.taskbar_press.key {
				continue
			}
			if target := d.hit_target_named(entry.id) {
				left = target.x - index * stride
			}
			break
		}
	}
	mut slot := (x - left) / stride
	if x < left {
		slot = 0
	}
	if slot >= fits {
		slot = fits - 1
	}
	return entries[slot]
}

fn (mut d Desktop) update_taskbar_drag(x int, y int) {
	if !d.taskbar_press.active {
		return
	}
	if !d.taskbar_press.dragging {
		if abs_int(x - d.taskbar_press.start_x) < taskbar_drag_threshold
			&& abs_int(y - d.taskbar_press.start_y) < taskbar_drag_threshold {
			return
		}
		d.taskbar_press.dragging = true
		d.close_taskbar_preview()
	}
	d.dirty = true
	target := d.taskbar_entry_under(x) or { return }
	if target.pinned != d.taskbar_press.pinned || target.key == d.taskbar_press.key {
		return
	}
	d.move_taskbar_entry(d.taskbar_press.key, target.key, d.taskbar_press.pinned)
}

// move_taskbar_entry puts the button `from` where `to` is now, shifting the
// buttons between them by one, the way a dragged list item settles.
fn (mut d Desktop) move_taskbar_entry(from string, to string, pinned bool) {
	entries := d.taskbar_entries()
	defer { unsafe { entries.free() } }
	mut order := []int{cap: entries.len}
	defer { unsafe { order.free() } }
	mut from_slot := -1
	mut to_slot := -1
	for index, entry in entries {
		if entry.pinned != pinned {
			continue
		}
		if entry.key == from {
			from_slot = order.len
		}
		if entry.key == to {
			to_slot = order.len
		}
		order << index
	}
	if from_slot < 0 || to_slot < 0 || from_slot == to_slot {
		return
	}
	moved := order[from_slot]
	order.delete(from_slot)
	order.insert(to_slot, moved)
	if pinned {
		for slot, index in order {
			d.pinned_apps[slot] = entries[index].app_index
		}
		d.dirty = true
		return
	}
	// Collect the ranks the affected windows hold, then deal them back out in
	// the new button order. The set of ranks is unchanged, so windows on other
	// workspaces keep their places.
	mut windows := []int{cap: d.windows.len}
	defer { unsafe { windows.free() } }
	for index in order {
		ids := d.taskbar_entry_window_ids(entries[index])
		for id in ids {
			if window_index := d.window_index(id) {
				windows << window_index
			}
		}
		unsafe { ids.free() }
	}
	mut ranks := []int{cap: windows.len}
	defer { unsafe { ranks.free() } }
	for window_index in windows {
		ranks << d.windows[window_index].task_rank
	}
	ranks.sort()
	for slot, window_index in windows {
		d.windows[window_index].task_rank = ranks[slot]
	}
	d.dirty = true
}

// taskbar_entry_window_ids lists the windows a button stands for, in taskbar
// order. A pinned button covers every window of its program; a combined
// button every window sharing its title on this workspace.
fn (d &Desktop) taskbar_entry_window_ids(entry TaskbarEntry) []int {
	mut ids := []int{cap: 4}
	mut last_rank := min_i32_rank
	for {
		mut found := -1
		for i, window in d.windows {
			if window.task_rank <= last_rank {
				continue
			}
			belongs := if entry.pinned {
				window.factory_index == entry.app_index
			} else if entry.key == window.id_task {
				true
			} else {
				d.settings.taskbar_mode == .combined && window.workspace == d.current_workspace
					&& window.title == entry.key && !d.taskbar_is_pinned(window.factory_index)
			}
			if !belongs {
				continue
			}
			if found < 0 || window.task_rank < d.windows[found].task_rank {
				found = i
			}
		}
		if found < 0 {
			break
		}
		last_rank = d.windows[found].task_rank
		ids << d.windows[found].id
	}
	return ids
}

// finish_taskbar_press returns the program to launch when a press on a
// closed pin completes as a click. A completed drag saves the pins' order.
fn (mut d Desktop) finish_taskbar_press_in(home string, release_action string, x int, y int) ?int {
	if !d.taskbar_press.active {
		return none
	}
	d.update_taskbar_drag(x, y)
	dragged := d.taskbar_press.dragging
	pinned := d.taskbar_press.pinned
	launch := d.taskbar_press.launch_on_release && release_action == d.taskbar_press.action
	app_index := d.taskbar_press.app_index
	d.clear_taskbar_press()
	d.dirty = true
	if dragged {
		if pinned && !save_taskbar_pins(home, d.pinned_apps) {
			eprintln('vinix-desktop: could not save taskbar pin order')
		}
		return none
	}
	if launch {
		return app_index
	}
	return none
}
