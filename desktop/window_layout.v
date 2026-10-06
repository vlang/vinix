// SPDX-License-Identifier: GPL-2.0-or-later
// A visible alternative to dragging into edges or memorizing tiling chords.
module main

import ui2

const key_super_z = '\x1b[122;9u'
const action_window_layout_prefix = 'layout.'
const window_layout_panel_id = 'layout.panel'
const window_layout_actions = ['layout.maximize', 'layout.left', 'layout.right', 'layout.restore',
	'layout.top_left', 'layout.top_right', 'layout.bottom_left', 'layout.bottom_right']
const window_layout_labels = ['window.layout.maximize', 'window.layout.left', 'window.layout.right',
	'window.layout.restore', 'window.layout.top_left', 'window.layout.top_right',
	'window.layout.bottom_left', 'window.layout.bottom_right']
const window_layout_columns = 4
const window_layout_width = 464
const window_layout_height = 246
const window_layout_padding = 12
const window_layout_gap = 8

struct WindowLayout {
mut:
	active    bool
	window_id int
	selected  int
}

fn window_layout_placement(index int) WindowPlacement {
	return match index {
		0 { WindowPlacement{ maximize: true } }
		1 { WindowPlacement{ snap: .left } }
		2 { WindowPlacement{ snap: .right } }
		4 { WindowPlacement{ snap: .top_left } }
		5 { WindowPlacement{ snap: .top_right } }
		6 { WindowPlacement{ snap: .bottom_left } }
		7 { WindowPlacement{ snap: .bottom_right } }
		else { WindowPlacement{} }
	}
}

fn (d &Desktop) window_layout_anchor_valid() bool {
	index := d.window_index(d.window_layout.window_id) or { return false }
	return d.windows[index].workspace == d.current_workspace && !d.windows[index].minimized
}

fn (mut d Desktop) open_window_layout(id int) {
	index := d.window_index(id) or { return }
	if d.windows[index].workspace != d.current_workspace || d.windows[index].minimized {
		return
	}
	if d.window_layout.active && d.window_layout.window_id == id {
		d.close_window_layout()
		return
	}
	d.close_window_snap_assist()
	d.close_window_actions()
	d.switcher_close()
	d.close_window_overview()
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
	current := d.window_index(id) or { return }
	mut selected := 0
	if d.windows[current].maximized {
		selected = 3
	} else if d.windows[current].snap != .none_ {
		for choice in 0 .. window_layout_actions.len {
			if window_layout_placement(choice).snap == d.windows[current].snap {
				selected = choice
				break
			}
		}
	}
	d.window_layout = WindowLayout{ active: true, window_id: id, selected: selected }
	d.set_hover('')
	d.dirty = true
}

fn (mut d Desktop) close_window_layout() {
	if !d.window_layout.active {
		return
	}
	d.window_layout = WindowLayout{}
	d.set_hover('')
	d.dirty = true
}

// The maximize button exposes layouts to pointer users as well as Super+Z.
// Its matching release is swallowed by the input loop, even after selection
// or click-away has already closed the chooser.
fn (mut d Desktop) window_layout_right_down(x int, y int) bool {
	if d.window_overlay_active() || d.switcher.active || d.start_menu_open {
		d.close_window_layout()
		d.close_window_overview()
		d.switcher_close()
		d.close_start_menu()
		d.window_layout_right_release = true
		return true
	}
	action, world := d.hit_action_world(x, y)
	if world != .desktop || !action.starts_with('win.') || !action.ends_with('.maximize') {
		return false
	}
	for window in d.windows {
		if window.id_maximize == action {
			d.open_window_layout(window.id)
			d.window_layout_right_release = true
			return true
		}
	}
	return false
}

fn (mut d Desktop) apply_window_layout(choice int) {
	if !d.window_layout.active || !d.window_layout_anchor_valid() {
		d.close_window_layout()
		return
	}
	if choice < 0 || choice >= window_layout_actions.len {
		return
	}
	id := d.window_layout.window_id
	d.close_window_layout()
	if choice == 3 {
		index := d.window_index(id) or { return }
		if d.windows[index].maximized || d.windows[index].snap != .none_ {
			d.restore_window(id)
		}
		return
	}
	placement := window_layout_placement(choice)
	if placement.maximize {
		d.maximize(id)
	} else {
		d.snap_window(id, placement.snap)
		d.open_window_snap_assist(id)
	}
}

fn (mut d Desktop) handle_window_layout_action(action string) bool {
	if !d.window_layout.active || !action.starts_with(action_window_layout_prefix) {
		return false
	}
	for choice, id in window_layout_actions {
		if action == id {
			d.apply_window_layout(choice)
			return true
		}
	}
	// The panel's gaps consume a press so it cannot reach a window behind it.
	return action == window_layout_panel_id
}

fn (mut d Desktop) step_window_layout(step int) {
	count := window_layout_actions.len
	d.window_layout.selected = ((d.window_layout.selected + step) % count + count) % count
	d.dirty = true
}

// This runs before the app switcher so the arrangement chooser owns ordinary
// arrows, Enter and Escape, and Super+Z can replace another desktop overlay.
fn (mut d Desktop) take_window_layout_keys(keys string) string {
	if d.window_layout.active && !d.window_layout_anchor_valid() {
		d.close_window_layout()
	}
	if !d.window_layout.active && keys.index_u8(0x1b) < 0 {
		return keys
	}
	mut kept := []u8{cap: keys.len}
	mut owned_input := d.window_layout.active
	mut i := 0
	for i < keys.len {
		chord := match_at(keys, i, key_super_z)
		if chord > seq_none {
			was_active := d.window_layout.active
			d.open_window_layout(d.focus)
			owned_input = owned_input || was_active || d.window_layout.active
			i += chord
			continue
		}
		if !d.window_layout.active {
			if !owned_input {
				kept << keys[i]
			}
			i++
			continue
		}
		mut step := 0
		if i + 2 < keys.len && keys[i] == 0x1b && (keys[i + 1] == `[` || keys[i + 1] == `O`) {
			step = match keys[i + 2] {
				`A` { -window_layout_columns }
				`B` { window_layout_columns }
				`C` { 1 }
				`D` { -1 }
				else { 0 }
			}
		}
		if step != 0 {
			d.step_window_layout(step)
			i += 3
			continue
		}
		if keys[i] == `\r` || keys[i] == `\n` {
			d.apply_window_layout(d.window_layout.selected)
		} else if keys[i] == 0x1b {
			// Modifier-release packets and other CSI chords belong to the
			// modal chooser, too. Releasing Super must leave it open.
			if i + 1 < keys.len && keys[i + 1] == `[` {
				mut end := i + 2
				for end < keys.len && !(keys[end] >= 0x40 && keys[end] <= 0x7e) {
					end++
				}
				i = if end < keys.len { end + 1 } else { keys.len }
				continue
			}
			d.close_window_layout()
		}
		// The chooser owns the rest of this console batch, including queued
		// typing after dismissal, so covered applications receive no surprise
		// suffix when Enter or Escape closes the panel.
		i++
	}
	if kept.len == keys.len {
		unsafe { kept.free() }
		return keys
	}
	if kept.len == 0 {
		unsafe { kept.free() }
		return ''
	}
	result := kept.bytestr()
	unsafe { kept.free() }
	return result
}

fn (d &Desktop) window_layout_bounds() DamageRect {
	index := d.window_index(d.window_layout.window_id) or { return DamageRect{} }
	window := d.windows[index]
	width := if d.canvas.width - 24 < window_layout_width {
		d.canvas.width - 24
	} else {
		window_layout_width
	}
	height := if desktop_usable_height(d.canvas.height) - 24 < window_layout_height {
		desktop_usable_height(d.canvas.height) - 24
	} else {
		window_layout_height
	}
	mut x := window.x + window.width - width
	mut y := window.y + d.theme().title_height + 8
	if x + width > d.canvas.width - 12 { x = d.canvas.width - width - 12 }
	if x < 12 { x = 12 }
	if y + height > desktop_usable_height(d.canvas.height) - 12 {
		y = desktop_usable_height(d.canvas.height) - height - 12
	}
	if y < 12 { y = 12 }
	return DamageRect{ x: x, y: y, w: width, h: height, valid: width > 0 && height > 0 }
}

fn window_layout_symbol(choice int, x int, y int, width int, height int) ui2.Element {
	mut marks := frame_elements(1)
	frame := if choice == 3 {
		DamageRect{ x: width / 4, y: height / 4, w: width / 2, h: height / 2, valid: true }
	} else {
		window_placement_frame(window_layout_placement(choice), width, height + taskbar_height)
	}
	marks << ui2.view('', ui2.rect(f64(frame.x + 2), f64(frame.y + 2),
		f64(frame.w - 4), f64(frame.h - 4)), ui2.BoxStyle{ bg: app_accent, radius: 2 }, [])
	return ui2.view('', ui2.rect(f64(x), f64(y), f64(width), f64(height)), ui2.BoxStyle{
		bg:            app_surface
		radius:        3
		border_color:  body_muted
		border_left:   1
		border_right:  1
		border_top:    1
		border_bottom: 1
	}, marks)
}

fn (mut d Desktop) window_layout_element() ?ui2.Element {
	if !d.window_layout.active {
		return none
	}
	if !d.window_layout_anchor_valid() {
		d.close_window_layout()
		return none
	}
	frame := d.window_layout_bounds()
	if !frame.valid { return none }
	mut children := frame_elements(10)
	children << ui2.label('', tr('window.layout.title'), ui2.rect(12, 10, f64(frame.w - 24), 24),
		ui2.TextStyle{ color: body_heading, size: 15, bold: true })
	compact := frame.h < 200
	if !compact {
		children << ui2.label('', tr('window.layout.hint'), ui2.rect(12, 34, f64(frame.w - 24), 18),
			ui2.TextStyle{ color: body_muted, size: 11 })
	}
	top := if compact { 40 } else { 64 }
	tile_width := (frame.w - 2 * window_layout_padding - 3 * window_layout_gap) / window_layout_columns
	tile_height := (frame.h - top - window_layout_padding - window_layout_gap) / 2
	if tile_width < 16 || tile_height < 24 {
		return ui2.clickable_view(window_layout_panel_id, ui2.rect(f64(frame.x), f64(frame.y),
			f64(frame.w), f64(frame.h)), ui2.BoxStyle{ bg: body_panel, radius: 8 }, children)
	}
	show_symbols := tile_width >= 64 && tile_height >= 68
	for choice, action in window_layout_actions {
		x := window_layout_padding + choice % window_layout_columns * (tile_width + window_layout_gap)
		y := top + choice / window_layout_columns * (tile_height + window_layout_gap)
		mut content := frame_elements(2)
		if show_symbols {
			content << window_layout_symbol(choice, (tile_width - 56) / 2, 8, 56, 36)
		}
		label_y := if show_symbols { tile_height - 27 } else { (tile_height - 22) / 2 }
		content << ui2.label('', tr(window_layout_labels[choice]),
			ui2.rect(2, f64(label_y), f64(tile_width - 4), 22),
			ui2.TextStyle{ color: body_text, size: if tile_width < 80 { 10 } else { 11 }, align: .center })
		selected := choice == d.window_layout.selected
		children << ui2.clickable_view(action, ui2.rect(f64(x), f64(y), f64(tile_width),
			f64(tile_height)), ui2.BoxStyle{
			bg:            if selected || d.hover == action {
				quick_launch_hover
			} else {
				app_surface
			}
			radius:        6
			border_color:  if selected { app_accent } else { body_rule }
			border_left:   1
			border_right:  1
			border_top:    1
			border_bottom: 1
		}, content)
	}
	return ui2.clickable_view(window_layout_panel_id, ui2.rect(f64(frame.x), f64(frame.y),
		f64(frame.w), f64(frame.h)), ui2.BoxStyle{ bg: body_panel, radius: 8 }, children)
}
