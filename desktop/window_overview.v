// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// A persistent, paged overview of the current workspace. Cards borrow each
// window's retained thumbnail and cached selectors, rather than rendering
// applications again or formatting strings while the pointer moves.
module main

import ui2

const action_window_overview = 'taskbar.overview'
const window_overview_button_width = 28
const window_overview_panel = 'overview.panel'
const window_overview_dismiss = 'overview.dismiss'
const window_overview_previous = 'overview.previous'
const window_overview_next = 'overview.next'
const window_overview_workspace_ids = ['overview.workspace.0', 'overview.workspace.1',
	'overview.workspace.2', 'overview.workspace.3']
const key_window_overview = '\x1b[1;13A'
const window_overview_sequences = [key_window_overview, '\x1b[A', '\x1b[B', '\x1b[C', '\x1b[D',
	'\x1bOA', '\x1bOB', '\x1bOC', '\x1bOD', '\x1b[Z']
const window_overview_margin = 20
const window_overview_padding = 16
const window_overview_gap = 12
const window_overview_card_width = 224
const window_overview_card_height = 174
const window_overview_header_height = 62
const window_overview_footer_height = 38

struct WindowOverview {
mut:
	active      bool
	selected_id int
	page        int
	// Escape sequences may straddle console reads. A fixed buffer retains
	// their prefix without allocating or exposing half a shortcut to an app.
	pending     [16]u8
	pending_len int
}

struct WindowOverviewLayout {
	x           int
	y           int
	width       int
	height      int
	columns     int
	rows        int
	card_width  int
	card_height int
}

fn (layout WindowOverviewLayout) capacity() int {
	return layout.columns * layout.rows
}

fn window_overview_layout(screen_width int, screen_height int) WindowOverviewLayout {
	usable := desktop_usable_height(screen_height)
	margin := if usable < 300 { 8 } else { window_overview_margin }
	x := if screen_width > 2 * margin { margin } else { 0 }
	y := if usable > 2 * margin { margin } else { 0 }
	width := if screen_width - 2 * x > 0 { screen_width - 2 * x } else { 1 }
	height := if usable - 2 * y > 0 { usable - 2 * y } else { 1 }
	inner_width := if width > 2 * window_overview_padding {
		width - 2 * window_overview_padding
	} else {
		1
	}
	inner_height := height - 2 * window_overview_padding - window_overview_header_height -
		window_overview_footer_height
	mut columns := (inner_width + window_overview_gap) / (window_overview_card_width + window_overview_gap)
	if columns < 1 {
		columns = 1
	}
	card_width := (inner_width - (columns - 1) * window_overview_gap) / columns
	card_height := if inner_height < window_overview_card_height {
		if inner_height > 0 { inner_height } else { 1 }
	} else {
		window_overview_card_height
	}
	mut rows := (inner_height + window_overview_gap) / (card_height + window_overview_gap)
	if rows < 1 {
		rows = 1
	}
	return WindowOverviewLayout{
		x:           x
		y:           y
		width:       width
		height:      height
		columns:     columns
		rows:        rows
		card_width:  card_width
		card_height: card_height
	}
}

// Queries use painting order directly. Stable window IDs make a selected or
// clicked card safe when a process exits while the overview is open.
fn (d &Desktop) window_overview_count() int {
	return d.workspace_window_count(d.current_workspace)
}

fn (d &Desktop) window_overview_id_at(position int) ?int {
	if position < 0 {
		return none
	}
	mut slot := 0
	for i := d.windows.len - 1; i >= 0; i-- {
		if d.windows[i].workspace != d.current_workspace {
			continue
		}
		if slot == position {
			return d.windows[i].id
		}
		slot++
	}
	return none
}

fn (d &Desktop) window_overview_position(id int) ?int {
	mut slot := 0
	for i := d.windows.len - 1; i >= 0; i-- {
		if d.windows[i].workspace != d.current_workspace {
			continue
		}
		if d.windows[i].id == id {
			return slot
		}
		slot++
	}
	return none
}

fn (mut d Desktop) reconcile_window_overview() {
	if !d.overview.active {
		return
	}
	position := d.window_overview_position(d.overview.selected_id) or {
		d.overview.selected_id = d.window_overview_id_at(0) or { 0 }
		0
	}
	layout := window_overview_layout(d.canvas.width, d.canvas.height)
	d.overview.page = position / layout.capacity()
}

// Cancel a raw application's held gestures before a modal takes input.
// The real device level stays intact until its later release, which the modal
// consumes. Forwarding the cancellation uses the original captured window.
fn (mut d Desktop) cancel_window_overlay_app_pointer() {
	if d.pointer_capture == 0 {
		return
	}
	buttons := d.buttons
	capture := d.pointer_capture
	for slot in 0 .. 4 {
		flag := match slot {
			0 { button_left }
			1 { button_right }
			2 { button_middle }
			else { button_back }
		}
		if buttons & flag == 0 {
			continue
		}
		button := match slot {
			0 { AppPointerButton.left }
			1 { AppPointerButton.right }
			2 { AppPointerButton.middle }
			else { AppPointerButton.back }
		}
		d.buttons &= ~flag
		d.pointer_capture = capture
		d.forward_pointer_to_window(d.pointer_x, d.pointer_y, .up, button, 0)
	}
	d.buttons = buttons
	d.pointer_capture = 0
}

fn (mut d Desktop) open_window_overview() {
	d.close_window_layout()
	d.switcher_close()
	if d.start_menu_open {
		d.close_start_menu()
	}
	d.close_create_context_menu()
	d.close_taskbar_preview()
	d.end_peek()
	d.hide_tooltip()
	d.close_tray_flyout()
	d.clear_taskbar_press()
	if d.shortcut_press.dragging {
		d.restore_shortcut_drag()
	}
	d.shortcut_press = ShortcutPress{}
	d.drag = Drag{}
	d.drag_damage = DamageRect{}
	d.cancel_window_overlay_app_pointer()
	d.chrome_pointer_capture = false
	d.overview.active = true
	d.overview.selected_id = if d.window_overview_position(d.focus) != none {
		d.focus
	} else {
		d.window_overview_id_at(0) or { 0 }
	}
	d.reconcile_window_overview()
	d.set_hover('')
	d.dirty = true
}

fn (mut d Desktop) close_window_overview() {
	if !d.overview.active {
		return
	}
	d.overview.active = false
	d.overview.pending_len = 0
	d.set_hover('')
	d.dirty = true
}

fn (mut d Desktop) toggle_window_overview() {
	if d.overview.active {
		d.close_window_overview()
	} else {
		d.open_window_overview()
	}
}

fn (mut d Desktop) step_window_overview(step int) {
	d.reconcile_window_overview()
	count := d.window_overview_count()
	if count == 0 {
		return
	}
	position := d.window_overview_position(d.overview.selected_id) or { 0 }
	next := (position + step % count + count) % count
	d.overview.selected_id = d.window_overview_id_at(next) or { return }
	d.reconcile_window_overview()
	d.dirty = true
}

fn (mut d Desktop) commit_window_overview(id int) {
	if d.window_overview_position(id) == none {
		// The clicked window exited or moved after its last rendered card.
		d.reconcile_window_overview()
		d.dirty = true
		return
	}
	d.close_window_overview()
	d.activate(id)
}

fn (mut d Desktop) page_window_overview(direction int) {
	d.reconcile_window_overview()
	layout := window_overview_layout(d.canvas.width, d.canvas.height)
	count := d.window_overview_count()
	pages := (count + layout.capacity() - 1) / layout.capacity()
	if pages <= 1 {
		return
	}
	page := (d.overview.page + direction + pages) % pages
	d.overview.selected_id = d.window_overview_id_at(page * layout.capacity()) or { return }
	d.reconcile_window_overview()
	d.dirty = true
}

// The overview owns every primary click while open. Clicking its backdrop
// dismisses it without delivering the same press to the covered application.
fn (mut d Desktop) window_overview_pointer_down(action string, world ActionWorld) bool {
	if !d.overview.active {
		return false
	}
	if world != .desktop {
		d.close_window_overview()
		return true
	}
	if action.starts_with(taskbar_preview_prefix) {
		d.commit_window_overview(preview_window_id(action))
		return true
	}
	for workspace, id in window_overview_workspace_ids {
		if action == id {
			if workspace != d.current_workspace {
				d.switch_workspace(workspace)
				d.open_window_overview()
			}
			return true
		}
	}
	if action == window_overview_previous || action == window_overview_next {
		d.page_window_overview(if action == window_overview_previous { -1 } else { 1 })
		return true
	}
	if action != window_overview_panel {
		d.close_window_overview()
	}
	return true
}

fn (mut d Desktop) window_overview_sequence(sequence string) {
	if sequence == key_window_overview {
		d.toggle_window_overview()
		return
	}
	if !d.overview.active {
		return
	}
	layout := window_overview_layout(d.canvas.width, d.canvas.height)
	match sequence {
		'\x1b[A', '\x1bOA' { d.step_window_overview(-layout.columns) }
		'\x1b[B', '\x1bOB' { d.step_window_overview(layout.columns) }
		'\x1b[C', '\x1bOC' { d.step_window_overview(1) }
		'\x1b[D', '\x1bOD', '\x1b[Z' { d.step_window_overview(-1) }
		else {}
	}
}

// Inactive overview handling passes unrelated input through. Active handling
// consumes typing, modifier releases and navigation, including keys queued
// after dismissal, so one console batch cannot type into a covered window.
fn (mut d Desktop) take_window_overview_keys(keys string) string {
	if keys.len == 0 {
		if d.overview.pending_len == 0 {
			return keys
		}
		length := d.overview.pending_len
		d.overview.pending_len = 0
		if d.overview.active {
			if length == 1 {
				d.close_window_overview()
			}
			return ''
		}
		mut released := []u8{cap: length}
		for i in 0 .. length {
			released << d.overview.pending[i]
		}
		result := released.bytestr()
		unsafe { released.free() }
		return result
	}
	if !d.overview.active && d.overview.pending_len == 0 && keys.index_u8(0x1b) < 0 {
		return keys
	}
	mut kept := []u8{cap: keys.len + d.overview.pending_len}
	mut owned_input := d.overview.active
	for ch in keys {
		if d.overview.pending_len > 0 || ch == 0x1b {
			d.overview.pending[d.overview.pending_len] = ch
			d.overview.pending_len++
			sequence := unsafe { tos(&d.overview.pending[0], d.overview.pending_len) }
			// match_at deliberately treats a lone Escape as an ordinary key.
			// Here it is also the first byte of the chord currently being read.
			mut partial := sequence.len == 1
			mut matched := false
			for candidate in window_overview_sequences {
				result := match_at(sequence, 0, candidate)
				if result > seq_none {
					matched = true
					d.overview.pending_len = 0
					was_active := d.overview.active
					if candidate == key_window_overview || was_active {
						d.window_overview_sequence(candidate)
						owned_input = true
					} else if !owned_input {
						for byte in sequence {
							kept << byte
						}
					}
					break
				}
				if result == seq_partial {
					partial = true
				}
			}
			if !matched && !partial {
				if !owned_input {
					for byte in sequence {
						kept << byte
					}
				} else if d.overview.active && d.overview.pending_len == 2
					&& ch != `[` && ch != `O` {
					d.close_window_overview()
				}
				d.overview.pending_len = 0
			}
			continue
		}
		if !owned_input {
			kept << ch
		} else if d.overview.active {
			if ch == 13 || ch == 10 {
				d.reconcile_window_overview()
				d.commit_window_overview(d.overview.selected_id)
			} else if ch == 9 {
				d.step_window_overview(1)
			}
		}
	}
	if kept.len == 0 {
		unsafe { kept.free() }
		return ''
	}
	if !owned_input && d.overview.pending_len == 0 && kept.len == keys.len {
		unsafe { kept.free() }
		return keys
	}
	result := kept.bytestr()
	unsafe { kept.free() }
	return result
}

fn (d &Desktop) window_overview_card(index int, x int, y int, width int, height int) ui2.Element {
	window := &d.windows[index]
	selected := window.id == d.overview.selected_id
	hovered := d.hover == window.id_preview
	mut children := frame_elements(4)
	children << ui2.label('', app_title_text(window.title), ui2.rect(10, 7, f64(width - 20), 21),
		ui2.TextStyle{ color: taskbar_preview_text, size: 13, bold: selected, lines: 1 })
	image_y := 32
	image_width := if width - 20 > 0 { width - 20 } else { 1 }
	image_height := if height - image_y - 27 > 0 { height - image_y - 27 } else { 1 }
	if height >= 70 && window.thumbnail.len > 0 {
		mut thumb_width := image_width
		mut thumb_height := if window.thumbnail_width > 0 {
			window.thumbnail_height * thumb_width / window.thumbnail_width
		} else {
			image_height
		}
		if thumb_height > image_height {
			thumb_height = image_height
			thumb_width = if window.thumbnail_height > 0 {
				window.thumbnail_width * thumb_height / window.thumbnail_height
			} else {
				image_width
			}
		}
		children << ui2.image('', window.id_thumbnail, ui2.rect(f64((width - thumb_width) / 2),
			f64(image_y + (image_height - thumb_height) / 2), f64(thumb_width), f64(thumb_height)))
	} else if height >= 70 {
		icon_size := if image_height < 48 { image_height } else { 48 }
		icon := if window.icon.len > 0 { window.icon } else { 'builtin:window' }
		children << ui2.button_with_image('', '', icon,
			ui2.rect(f64((width - icon_size) / 2), f64(image_y + (image_height - icon_size) / 2),
				f64(icon_size), f64(icon_size)), ui2.BoxStyle{ transparent: true },
			ui2.TextStyle{ color: taskbar_preview_text })
	}
	if window.minimized && height >= 70 {
		children << ui2.label('', tr('desktop.overview.minimized'),
			ui2.rect(10, f64(height - 23), f64(width - 20), 18),
			ui2.TextStyle{ color: taskbar_preview_text, size: 11, align: .center })
	}
	return ui2.clickable_view(window.id_preview, ui2.rect(f64(x), f64(y), f64(width), f64(height)),
		ui2.BoxStyle{
			bg:     if selected {
				app_accent
			} else if hovered {
				taskbar_preview_tile_hover
			} else {
				taskbar_preview_box
			}
			radius: 8
		},
		children)
}

fn (mut d Desktop) window_overview_element() ui2.Element {
	d.reconcile_window_overview()
	layout := window_overview_layout(d.canvas.width, d.canvas.height)
	count := d.window_overview_count()
	mut children := frame_elements(layout.capacity() + workspace_count + 5)
	children << ui2.label('', tr('desktop.overview.title'),
		ui2.rect(window_overview_padding, 12, f64(layout.width - 2 * window_overview_padding), 26),
		ui2.TextStyle{ color: taskbar_preview_text, size: 20, bold: true })
	for workspace, id in window_overview_workspace_ids {
		children << ui2.button(id, workspace_labels[workspace],
			ui2.rect(f64(window_overview_padding + workspace * 42), 40, 34, 24),
			ui2.BoxStyle{
				bg:     if workspace == d.current_workspace {
					app_accent
				} else {
					taskbar_preview_box
				}
				radius: 5
			},
			ui2.TextStyle{ color: taskbar_preview_text, size: 12, align: .center })
	}
	start := d.overview.page * layout.capacity()
	mut slot := 0
	mut ordinal := 0
	for i := d.windows.len - 1; i >= 0; i-- {
		if d.windows[i].workspace != d.current_workspace {
			continue
		}
		if ordinal < start {
			ordinal++
			continue
		}
		if slot >= layout.capacity() {
			break
		}
		x := window_overview_padding + slot % layout.columns * (layout.card_width + window_overview_gap)
		y := window_overview_padding + window_overview_header_height +
			slot / layout.columns * (layout.card_height + window_overview_gap)
		children << d.window_overview_card(i, x, y, layout.card_width, layout.card_height)
		slot++
	}
	if count == 0 {
		children << ui2.label('', tr('desktop.overview.empty'),
			ui2.rect(window_overview_padding, window_overview_padding + window_overview_header_height,
				f64(layout.width - 2 * window_overview_padding), 30),
			ui2.TextStyle{ color: taskbar_preview_text, size: 14, align: .center })
	}
	footer_y := layout.height - window_overview_footer_height - window_overview_padding
	children << ui2.label('', tr('desktop.overview.hint'),
		ui2.rect(window_overview_padding, f64(footer_y), f64(layout.width - 2 * window_overview_padding), 18),
		ui2.TextStyle{ color: taskbar_preview_text, size: 11, lines: 1 })
	if count > layout.capacity() {
		children << ui2.button(window_overview_previous, tr('desktop.overview.previous'),
			ui2.rect(window_overview_padding, f64(footer_y + 20), 94, 23),
			ui2.BoxStyle{ bg: taskbar_preview_box, radius: 4 },
			ui2.TextStyle{ color: taskbar_preview_text, size: 11 })
		children << ui2.button(window_overview_next, tr('desktop.overview.next'),
			ui2.rect(window_overview_padding + 102, f64(footer_y + 20), 94, 23),
			ui2.BoxStyle{ bg: taskbar_preview_box, radius: 4 },
			ui2.TextStyle{ color: taskbar_preview_text, size: 11 })
	}
	panel := ui2.clickable_view(window_overview_panel,
		ui2.rect(f64(layout.x), f64(layout.y), f64(layout.width), f64(layout.height)),
		ui2.BoxStyle{ bg: taskbar_preview_bg, radius: 12 }, children)
	return ui2.clickable_view(window_overview_dismiss,
		ui2.rect(0, 0, f64(d.canvas.width), f64(d.canvas.height)),
		ui2.BoxStyle{ transparent: true }, frame_child(panel))
}
