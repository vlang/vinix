// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Persistent desktop shortcut order and drag/drop gesture state.
module main

const shortcut_order_filename = '.vinix-shortcut-order'
const shortcut_drag_threshold = 6
const shortcut_order_file_limit = 4096

struct ShortcutPress {
mut:
	app_index  int = -1
	start_slot int = -1
	start_x    int
	start_y    int
	dragging   bool
}

fn default_shortcut_order() []int {
	mut order := []int{len: available_apps.len}
	for index in 0 .. available_apps.len {
		order[index] = index
	}
	return order
}

fn shortcut_order_contains(order []int, value int) bool {
	for entry in order {
		if entry == value {
			return true
		}
	}
	return false
}

fn normalize_shortcut_order(order []int) []int {
	mut normalized := []int{cap: available_apps.len}
	for entry in order {
		if entry >= 0 && entry < available_apps.len && !shortcut_order_contains(normalized, entry) {
			normalized << entry
		}
	}
	for index in 0 .. available_apps.len {
		if !shortcut_order_contains(normalized, index) {
			normalized << index
		}
	}
	return normalized
}

fn shortcut_app_index_named(name string) int {
	for index in 0 .. available_apps.len {
		if available_apps[index].process_name == name {
			return index
		}
	}
	return -1
}

fn shortcut_order_path(home string) string {
	return '${home}/${shortcut_order_filename}'
}

fn load_shortcut_order(home string) []int {
	path := shortcut_order_path(home)
	info := desktop_stat(path) or {
		unsafe { path.free() }
		return default_shortcut_order()
	}
	if info.size == 0 || info.size > u64(shortcut_order_file_limit) {
		unsafe { path.free() }
		return default_shortcut_order()
	}
	mut buffer := []u8{len: int(info.size)}
	got := desktop_read_file(path, buffer.data, info.size)
	unsafe { path.free() }
	if got <= 0 {
		unsafe { buffer.free() }
		return default_shortcut_order()
	}

	mut parsed := []int{cap: available_apps.len}
	mut start := 0
	for offset := 0; offset <= int(got); offset++ {
		if offset < int(got) && buffer[offset] != `\n` {
			continue
		}
		mut end := offset
		if end > start && buffer[end - 1] == `\r` {
			end--
		}
		if end > start {
			name := unsafe { tos(&u8(buffer.data) + start, end - start) }
			index := shortcut_app_index_named(name)
			if index >= 0 && !shortcut_order_contains(parsed, index) {
				parsed << index
			}
		}
		start = offset + 1
	}
	normalized := normalize_shortcut_order(parsed)
	unsafe {
		parsed.free()
		buffer.free()
	}
	return normalized
}

fn save_shortcut_order(home string, order []int) bool {
	normalized := normalize_shortcut_order(order)
	defer { unsafe { normalized.free() } }
	mut bytes := []u8{cap: available_apps.len * 24}
	defer { unsafe { bytes.free() } }
	for index in normalized {
		name := available_apps[index].process_name
		for ch in name {
			bytes << ch
		}
		bytes << `\n`
	}
	path := shortcut_order_path(home)
	defer { unsafe { path.free() } }
	mut data := voidptr(unsafe { nil })
	if bytes.len > 0 {
		data = bytes.data
	}
	return desktop_write_file(path, data, u64(bytes.len))
}

fn (mut d Desktop) ensure_shortcut_order() {
	if d.shortcut_order.len == available_apps.len {
		return
	}
	if d.shortcut_order.cap > 0 {
		unsafe { d.shortcut_order.free() }
	}
	d.shortcut_order = default_shortcut_order()
}

fn (d &Desktop) shortcut_app_at_slot(slot int) int {
	if slot < 0 || slot >= available_apps.len {
		return -1
	}
	if d.shortcut_order.len == available_apps.len {
		index := d.shortcut_order[slot]
		if index >= 0 && index < available_apps.len {
			return index
		}
	}
	return slot
}

fn (d &Desktop) shortcut_slot_for_app(app_index int) int {
	if app_index < 0 || app_index >= available_apps.len {
		return -1
	}
	if d.shortcut_order.len == available_apps.len {
		for slot, index in d.shortcut_order {
			if index == app_index {
				return slot
			}
		}
	}
	return app_index
}

fn shortcut_slot_at(x int, y int, screen_height int) ?int {
	if available_apps.len == 0 || x < shortcut_left || y < shortcut_top
		|| y >= screen_height - taskbar_height {
		return none
	}
	rows := shortcut_rows_for_height(screen_height)
	cell_width := shortcut_width + shortcut_gap
	cell_height := shortcut_height + shortcut_gap
	column := (x - shortcut_left) / cell_width
	row := (y - shortcut_top) / cell_height
	if column < 0 || row < 0 || row >= rows {
		return none
	}
	max_column := (available_apps.len - 1) / rows
	if column > max_column {
		return none
	}
	mut slot := column * rows + row
	if slot >= available_apps.len {
		slot = available_apps.len - 1
	}
	return slot
}

fn (mut d Desktop) begin_shortcut_press(action string, x int, y int) bool {
	if !action.starts_with(action_shortcut_prefix) {
		return false
	}
	app_index := action[action_shortcut_prefix.len..].int()
	if app_index < 0 || app_index >= available_apps.len {
		return false
	}
	d.ensure_shortcut_order()
	d.shortcut_press = ShortcutPress{
		app_index:  app_index
		start_slot: d.shortcut_slot_for_app(app_index)
		start_x:    x
		start_y:    y
	}
	d.dirty = true
	return true
}

fn (mut d Desktop) update_shortcut_drag(x int, y int) {
	if d.shortcut_press.app_index < 0 {
		return
	}
	if !d.shortcut_press.dragging {
		if abs_int(x - d.shortcut_press.start_x) < shortcut_drag_threshold
			&& abs_int(y - d.shortcut_press.start_y) < shortcut_drag_threshold {
			return
		}
		d.shortcut_press.dragging = true
	}
	target := shortcut_slot_at(x, y, d.canvas.height) or { return }
	from := d.shortcut_slot_for_app(d.shortcut_press.app_index)
	if from < 0 || target == from {
		return
	}
	d.ensure_shortcut_order()
	app_index := d.shortcut_order[from]
	d.shortcut_order.delete(from)
	d.shortcut_order.insert(target, app_index)
	d.dirty = true
}

fn (mut d Desktop) restore_shortcut_drag() {
	from := d.shortcut_slot_for_app(d.shortcut_press.app_index)
	to := d.shortcut_press.start_slot
	if from < 0 || to < 0 || to >= d.shortcut_order.len || from == to {
		return
	}
	app_index := d.shortcut_order[from]
	d.shortcut_order.delete(from)
	d.shortcut_order.insert(to, app_index)
	d.dirty = true
}

fn (mut d Desktop) finish_shortcut_press_in(home string, release_action string, x int, y int) ?int {
	if d.shortcut_press.app_index < 0 {
		return none
	}
	// pump_pointer installs the packet's released button level before handling
	// its coordinates. Fold the release position into the gesture here so a
	// coalesced final move and button-up cannot be mistaken for a click.
	d.update_shortcut_drag(x, y)
	app_index := d.shortcut_press.app_index
	dragged := d.shortcut_press.dragging
	valid_drop := release_action.starts_with(action_shortcut_prefix)
	if dragged && !valid_drop {
		d.restore_shortcut_drag()
	}
	d.shortcut_press = ShortcutPress{}
	if dragged {
		if valid_drop && !save_shortcut_order(home, d.shortcut_order) {
			eprintln('vinix-desktop: could not save desktop shortcut order')
		}
		d.dirty = true
		return none
	}
	if app_index < app_shortcut_actions.len && release_action == app_shortcut_actions[app_index] {
		return app_index
	}
	return none
}

fn (mut d Desktop) finish_shortcut_press(release_action string, x int, y int) ?int {
	return d.finish_shortcut_press_in(desktop_home, release_action, x, y)
}
