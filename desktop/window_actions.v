// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// The window menu and reversible keyboard move/resize. Modal state holds only
// geometry and a bounded protocol prefix; labels and selectors are literals.
module main

import ui2

const key_window_actions = '\x1b[32;3u'
const key_window_actions_legacy = '\x1b '
const window_actions_panel = 'window.actions.panel'
const window_actions_dismiss = 'window.actions.dismiss'
const window_actions_previous = 'window.actions.previous'
const window_actions_next = 'window.actions.next'
const window_actions_ids = ['window.actions.move', 'window.actions.resize', 'window.actions.minimize',
	'window.actions.maximize', 'window.actions.arrange', 'window.actions.workspace_1',
	'window.actions.workspace_2', 'window.actions.workspace_3', 'window.actions.workspace_4',
	'window.actions.close']
const window_actions_sequences = [key_window_actions, key_window_actions_legacy, key_window_overview,
	key_super_z, '\x1b[A', '\x1b[B', '\x1b[C', '\x1b[D', '\x1bOA', '\x1bOB', '\x1bOC', '\x1bOD',
	'\x1b[1;2A', '\x1b[1;2B', '\x1b[1;2C', '\x1b[1;2D', '\x1b[Z']
const window_actions_width = 270
const window_actions_row_height = 28
const window_actions_header_height = 36
const window_actions_footer_height = 28
const window_actions_padding = 8

enum WindowActionMode {
	menu
	move
	resize
}

struct WindowActionFrame {
	x              int
	y              int
	width          int
	height         int
	restore_x      int
	restore_y      int
	restore_width  int
	restore_height int
	maximized      bool
	snap           WindowSnap
}

struct WindowActions {
mut:
	active      bool
	mode        WindowActionMode
	window_id   int
	selected    int
	page        int
	original    WindowActionFrame
	pending     [32]u8
	pending_len int
}

struct WindowActionsBounds {
	x      int
	y      int
	width  int
	height int
	rows   int
	valid  bool
}

fn window_action_frame(window &Window) WindowActionFrame {
	return WindowActionFrame{
		x:              window.x
		y:              window.y
		width:          window.width
		height:         window.height
		restore_x:      window.restore_x
		restore_y:      window.restore_y
		restore_width:  window.restore_width
		restore_height: window.restore_height
		maximized:      window.maximized
		snap:           window.snap
	}
}

fn (d &Desktop) window_actions_anchor_valid() bool {
	index := d.window_index(d.window_actions.window_id) or { return false }
	return d.windows[index].workspace == d.current_workspace && !d.windows[index].minimized
}

// A replacement modal, workspace change or click-away cancels manipulation.
// Restore the stable anchor's metadata without raising it or stealing focus.
fn (mut d Desktop) close_window_actions() {
	if !d.window_actions.active {
		return
	}
	if d.window_actions.mode != .menu {
		if index := d.window_index(d.window_actions.window_id) {
			frame := d.window_actions.original
			d.windows[index].x = frame.x
			d.windows[index].y = frame.y
			d.windows[index].width = frame.width
			d.windows[index].height = frame.height
			d.windows[index].restore_x = frame.restore_x
			d.windows[index].restore_y = frame.restore_y
			d.windows[index].restore_width = frame.restore_width
			d.windows[index].restore_height = frame.restore_height
			d.windows[index].maximized = frame.maximized
			d.windows[index].snap = frame.snap
		}
	}
	d.window_actions.active = false
	d.window_actions.mode = .menu
	d.window_actions.pending_len = 0
	d.set_hover('')
	d.dirty = true
}

fn (mut d Desktop) open_window_actions(id int) {
	index := d.window_index(id) or { return }
	if d.windows[index].workspace != d.current_workspace || d.windows[index].minimized {
		return
	}
	if d.window_actions.active && d.window_actions.window_id == id {
		d.close_window_actions()
		return
	}
	d.close_window_actions()
	d.close_window_snap_assist()
	d.close_window_layout()
	d.close_window_overview()
	d.switcher_close()
	d.close_start_menu()
	d.close_create_context_menu()
	d.close_taskbar_preview()
	d.close_tray_flyout()
	d.hide_tooltip()
	d.end_peek()
	d.clear_taskbar_press()
	if d.shortcut_press.dragging {
		d.restore_shortcut_drag()
	}
	d.shortcut_press = ShortcutPress{}
	d.drag = Drag{}
	d.drag_damage = DamageRect{}
	d.cancel_window_overlay_app_pointer()
	d.chrome_pointer_capture = false
	d.raise(id)
	d.window_actions.active = true
	d.window_actions.mode = .menu
	d.window_actions.window_id = id
	d.window_actions.selected = 0
	d.window_actions.page = 0
	d.set_hover('')
	d.dirty = true
}

fn (mut d Desktop) window_actions_right_down(x int, y int) bool {
	if d.window_actions.active {
		d.close_window_actions()
		d.window_layout_right_release = true
		return true
	}
	action, world := d.hit_action_world(x, y)
	if world != .desktop {
		return false
	}
	for window in d.windows {
		if window.id_titlebar == action {
			d.open_window_actions(window.id)
			if d.window_actions.active {
				// The input loop uses this shared right-release capture for
				// window menus even after a choice has closed the panel.
				d.window_layout_right_release = true
				return true
			}
			return false
		}
	}
	return false
}

fn (d &Desktop) window_actions_bounds() WindowActionsBounds {
	index := d.window_index(d.window_actions.window_id) or { return WindowActionsBounds{} }
	window := d.windows[index]
	available_height := desktop_usable_height(d.canvas.height) - 16
	width := if d.canvas.width - 16 < window_actions_width {
		d.canvas.width - 16
	} else {
		window_actions_width
	}
	mut rows := (available_height - window_actions_header_height - window_actions_footer_height -
		2 * window_actions_padding) / window_actions_row_height
	if rows < 1 { rows = 1 }
	if rows > window_actions_ids.len { rows = window_actions_ids.len }
	height := window_actions_header_height + rows * window_actions_row_height +
		window_actions_footer_height + 2 * window_actions_padding
	mut x := window.x + 8
	mut y := window.y + d.theme().title_height + 4
	if x + width > d.canvas.width - 8 { x = d.canvas.width - width - 8 }
	if x < 8 { x = 8 }
	if y + height > desktop_usable_height(d.canvas.height) - 8 {
		y = desktop_usable_height(d.canvas.height) - height - 8
	}
	if y < 8 { y = 8 }
	return WindowActionsBounds{
		x:      x
		y:      y
		width:  width
		height: height
		rows:   rows
		valid:  width > 0 && available_height >= height
	}
}

fn (mut d Desktop) begin_window_action_geometry(mode WindowActionMode) {
	if !d.window_actions.active || !d.window_actions_anchor_valid()
		|| d.window_actions.mode != .menu || mode == .menu {
		return
	}
	index := d.window_index(d.window_actions.window_id) or { return }
	d.window_actions.original = window_action_frame(&d.windows[index])
	if d.windows[index].maximized || d.windows[index].snap != .none_ {
		d.restore_window(d.window_actions.window_id)
	}
	d.window_actions.mode = mode
	d.set_hover('')
	d.dirty = true
}

fn (mut d Desktop) step_window_action_geometry(dx int, dy int, precise bool) {
	if !d.window_actions_anchor_valid() {
		d.close_window_actions()
		return
	}
	index := d.window_index(d.window_actions.window_id) or { return }
	step := if precise { 1 } else { 10 }
	if d.window_actions.mode == .move {
		d.windows[index].x += dx * step
		d.windows[index].y += dy * step
		d.clamp_drag_to_screen(index)
	} else if d.window_actions.mode == .resize {
		min_height := d.theme().title_height + window_min_body_height
		mut width := d.windows[index].width + dx * step
		mut height := d.windows[index].height + dy * step
		if width < window_min_width { width = window_min_width }
		if height < min_height { height = min_height }
		max_width := d.canvas.width - d.windows[index].x
		max_height := desktop_usable_height(d.canvas.height) - d.windows[index].y
		if max_width >= window_min_width && width > max_width { width = max_width }
		if max_height >= min_height && height > max_height { height = max_height }
		d.windows[index].width = width
		d.windows[index].height = height
	}
	d.dirty = true
}

fn (mut d Desktop) accept_window_action_geometry() {
	if !d.window_actions.active || d.window_actions.mode == .menu {
		return
	}
	if !d.window_actions_anchor_valid() {
		d.close_window_actions()
		return
	}
	index := d.window_index(d.window_actions.window_id) or { return }
	d.remember_restore_frame(index)
	// End the modal after committing; the ordinary close method cancels.
	d.window_actions.mode = .menu
	d.close_window_actions()
}

fn (mut d Desktop) apply_window_action(choice int) {
	if !d.window_actions.active || !d.window_actions_anchor_valid() {
		d.close_window_actions()
		return
	}
	if choice < 0 || choice >= window_actions_ids.len {
		return
	}
	id := d.window_actions.window_id
	if choice == 0 || choice == 1 {
		d.begin_window_action_geometry(if choice == 0 { .move } else { .resize })
		return
	}
	d.close_window_actions()
	match choice {
		2 { d.minimize(id) }
		3 {
			index := d.window_index(id) or { return }
			if d.windows[index].maximized || d.windows[index].snap != .none_ {
				d.restore_window(id)
			} else {
				d.maximize(id)
			}
		}
		4 { d.open_window_layout(id) }
		5, 6, 7, 8 { d.move_window_to_workspace(id, choice - 5) }
		9 { d.close_window(id) }
		else {}
	}
}

fn (mut d Desktop) step_window_actions(step int) {
	d.window_actions.selected = (d.window_actions.selected + step % window_actions_ids.len +
		window_actions_ids.len) % window_actions_ids.len
	bounds := d.window_actions_bounds()
	d.window_actions.page = d.window_actions.selected / bounds.rows
	d.dirty = true
}

fn (mut d Desktop) page_window_actions(direction int) {
	bounds := d.window_actions_bounds()
	pages := (window_actions_ids.len + bounds.rows - 1) / bounds.rows
	if pages <= 1 {
		return
	}
	page := (d.window_actions.page + direction + pages) % pages
	d.window_actions.selected = page * bounds.rows
	d.window_actions.page = page
	d.dirty = true
}

fn (mut d Desktop) window_actions_pointer_down(action string, world ActionWorld) bool {
	if !d.window_actions.active {
		return false
	}
	if !d.window_actions_anchor_valid() || world != .desktop {
		d.close_window_actions()
		return true
	}
	if d.window_actions.mode != .menu {
		if action != window_actions_panel {
			d.close_window_actions()
		}
		return true
	}
	for choice, id in window_actions_ids {
		if action == id {
			d.apply_window_action(choice)
			return true
		}
	}
	if action == window_actions_previous || action == window_actions_next {
		d.page_window_actions(if action == window_actions_previous { -1 } else { 1 })
	} else if action != window_actions_panel {
		d.close_window_actions()
	}
	return true
}

fn (mut d Desktop) window_actions_sequence(sequence string) {
	if sequence == key_window_actions || sequence == key_window_actions_legacy {
		d.open_window_actions(d.focus)
		return
	}
	if !d.window_actions.active {
		return
	}
	if sequence == key_window_overview || sequence == key_super_z {
		id := d.window_actions.window_id
		d.close_window_actions()
		if sequence == key_window_overview {
			d.open_window_overview()
		} else {
			d.open_window_layout(id)
		}
		return
	}
	mut dx := 0
	mut dy := 0
	mut precise := false
	match sequence {
		'\x1b[A', '\x1bOA' { dy = -1 }
		'\x1b[B', '\x1bOB' { dy = 1 }
		'\x1b[C', '\x1bOC' { dx = 1 }
		'\x1b[D', '\x1bOD' { dx = -1 }
		'\x1b[1;2A' {
			dy = -1
			precise = true
		}
		'\x1b[1;2B' {
			dy = 1
			precise = true
		}
		'\x1b[1;2C' {
			dx = 1
			precise = true
		}
		'\x1b[1;2D' {
			dx = -1
			precise = true
		}
		'\x1b[Z' { dy = -1 }
		else {}
	}
	if d.window_actions.mode == .menu {
		if dy != 0 { d.step_window_actions(dy) }
		if dx != 0 { d.page_window_actions(dx) }
	} else if dx != 0 || dy != 0 {
		d.step_window_action_geometry(dx, dy, precise)
	}
}

// Borrow unmodified batches, allocate only when a chord was removed or a
// retained prefix must be released, and free every temporary byte buffer.
fn (mut d Desktop) take_window_actions_keys(keys string) string {
	if d.window_actions.active && !d.window_actions_anchor_valid() {
		d.close_window_actions()
		// Even a stale modal owns its already queued input for this batch.
		return ''
	}
	if keys.len == 0 {
		length := d.window_actions.pending_len
		if length == 0 { return keys }
		d.window_actions.pending_len = 0
		if d.window_actions.active {
			if length == 1 { d.close_window_actions() }
			return ''
		}
		mut released := []u8{cap: length}
		for i in 0 .. length { released << d.window_actions.pending[i] }
		result := released.bytestr()
		unsafe { released.free() }
		return result
	}
	if !d.window_actions.active && d.window_actions.pending_len == 0 && keys.index_u8(0x1b) < 0 {
		return keys
	}
	mut kept := []u8{cap: keys.len + d.window_actions.pending_len}
	mut owned_input := d.window_actions.active
	for ch in keys {
		if d.window_actions.pending_len > 0 || ch == 0x1b {
			d.window_actions.pending[d.window_actions.pending_len] = ch
			d.window_actions.pending_len++
			sequence := unsafe { tos(&d.window_actions.pending[0], d.window_actions.pending_len) }
			mut partial := sequence.len == 1
			mut matched := false
			for candidate in window_actions_sequences {
				result := match_at(sequence, 0, candidate)
				if result > seq_none {
					matched = true
					d.window_actions.pending_len = 0
					if candidate == key_window_actions || candidate == key_window_actions_legacy
						|| d.window_actions.active {
						d.window_actions_sequence(candidate)
						owned_input = true
					} else if !owned_input {
						for byte in sequence { kept << byte }
					}
					break
				}
				if result == seq_partial { partial = true }
			}
			if !matched && !partial {
				if !owned_input {
					for byte in sequence { kept << byte }
				} else if d.window_actions.active && d.window_actions.pending_len == 2
					&& ch != `[` && ch != `O` {
					d.close_window_actions()
				}
				d.window_actions.pending_len = 0
			}
			continue
		}
		if !owned_input {
			kept << ch
		} else if d.window_actions.active {
			if ch == 13 || ch == 10 {
				if d.window_actions.mode == .menu {
					d.apply_window_action(d.window_actions.selected)
				} else {
					d.accept_window_action_geometry()
				}
			} else if ch == 9 && d.window_actions.mode == .menu {
				d.step_window_actions(1)
			}
		}
	}
	if kept.len == 0 {
		unsafe { kept.free() }
		return ''
	}
	if !owned_input && d.window_actions.pending_len == 0 && kept.len == keys.len {
		unsafe { kept.free() }
		return keys
	}
	result := kept.bytestr()
	unsafe { kept.free() }
	return result
}

fn (d &Desktop) window_action_label(choice int) string {
	if choice == 3 {
		index := d.window_index(d.window_actions.window_id) or { return '' }
		return tr(if d.windows[index].maximized || d.windows[index].snap != .none_ {
			'window.layout.restore'
		} else {
			'window.layout.maximize'
		})
	}
	return tr(window_actions_ids[choice])
}

fn (mut d Desktop) window_actions_element() ?ui2.Element {
	if !d.window_actions.active { return none }
	if !d.window_actions_anchor_valid() {
		d.close_window_actions()
		return none
	}
	mut panel := ui2.Element{}
	if d.window_actions.mode != .menu {
		width := if d.canvas.width - 16 < 660 { d.canvas.width - 16 } else { 660 }
		if width <= 0 { return none }
		mut children := frame_elements(2)
		moving := d.window_actions.mode == .move
		children << ui2.label('', tr(if moving {
			'window.actions.moving'
		} else {
			'window.actions.resizing'
		}),
			ui2.rect(12, 9, f64(width - 24), 22), ui2.TextStyle{ color: body_heading, size: 15, bold: true })
		children << ui2.label('', tr(if moving {
			'window.actions.move_hint'
		} else {
			'window.actions.resize_hint'
		}),
			ui2.rect(12, 34, f64(width - 24), 40), ui2.TextStyle{ color: body_muted, size: 11, lines: 2 })
		panel = ui2.clickable_view(window_actions_panel,
			ui2.rect(f64((d.canvas.width - width) / 2), 8, f64(width), 80),
			ui2.BoxStyle{ bg: body_panel, radius: 8 }, children)
	} else {
		bounds := d.window_actions_bounds()
		if !bounds.valid { return none }
		d.window_actions.page = d.window_actions.selected / bounds.rows
		mut children := frame_elements(bounds.rows + 3)
		children << ui2.label('', tr('window.actions.title'),
			ui2.rect(12, 8, f64(bounds.width - 24), 24),
			ui2.TextStyle{ color: body_heading, size: 15, bold: true })
		start := d.window_actions.page * bounds.rows
		for choice in start .. start + bounds.rows {
			if choice >= window_actions_ids.len { break }
			action := window_actions_ids[choice]
			selected := choice == d.window_actions.selected || d.hover == action
			children << ui2.button(action, d.window_action_label(choice),
				ui2.rect(window_actions_padding, f64(window_actions_header_height + window_actions_padding +
					(choice - start) * window_actions_row_height), f64(bounds.width - 2 * window_actions_padding),
					window_actions_row_height - 2),
				ui2.BoxStyle{ bg: if selected { quick_launch_hover } else { body_panel }, radius: 4 },
				ui2.TextStyle{ color: body_text, size: 12 })
		}
		if bounds.rows < window_actions_ids.len {
			footer_y := bounds.height - window_actions_footer_height
			children << ui2.button(window_actions_previous, tr('desktop.overview.previous'),
				ui2.rect(window_actions_padding, f64(footer_y), 94, 22),
				ui2.BoxStyle{ bg: quick_launch_hover, radius: 4 }, ui2.TextStyle{ color: body_text, size: 11 })
			children << ui2.button(window_actions_next, tr('desktop.overview.next'),
				ui2.rect(window_actions_padding + 100, f64(footer_y), 94, 22),
				ui2.BoxStyle{ bg: quick_launch_hover, radius: 4 }, ui2.TextStyle{ color: body_text, size: 11 })
		}
		panel = ui2.clickable_view(window_actions_panel,
			ui2.rect(f64(bounds.x), f64(bounds.y), f64(bounds.width), f64(bounds.height)),
			ui2.BoxStyle{ bg: body_panel, radius: 8 }, children)
	}
	return ui2.clickable_view(window_actions_dismiss,
		ui2.rect(0, 0, f64(d.canvas.width), f64(d.canvas.height)),
		ui2.BoxStyle{ transparent: true }, frame_child(panel))
}
