// SPDX-License-Identifier: GPL-2.0-or-later
// Offer the vacant half after a user tiles a window. Candidates keep their
// current frames until the user explicitly chooses one.
module main

import ui2

const window_snap_assist_panel = 'snap-assist.panel'
const window_snap_assist_dismiss = 'snap-assist.dismiss'
const window_snap_assist_previous = 'snap-assist.previous'
const window_snap_assist_next = 'snap-assist.next'
const window_snap_assist_sequences = ['\x1b[A', '\x1b[B', '\x1b[C', '\x1b[D', '\x1bOA', '\x1bOB',
	'\x1bOC', '\x1bOD', '\x1b[Z', key_super_up, key_super_down, key_super_right, key_super_left]

struct WindowSnapAssist {
mut:
	active      bool
	anchor_id   int
	target      WindowSnap
	selected_id int
	page        int
	pending     [16]u8
	pending_len int
}

struct WindowSnapAssistLayout {
	x           int
	y           int
	width       int
	height      int
	padding     int
	gap         int
	header      int
	footer      int
	columns     int
	rows        int
	card_width  int
	card_height int
}

fn (layout WindowSnapAssistLayout) capacity() int {
	return layout.columns * layout.rows
}

fn window_snap_assist_opposite(snap WindowSnap) WindowSnap {
	return match snap {
		.left { WindowSnap.right }
		.right { WindowSnap.left }
		else { WindowSnap.none_ }
	}
}

fn window_snap_assist_layout(target WindowSnap, screen_width int,
	screen_height int) WindowSnapAssistLayout {
	frame := window_placement_frame(WindowPlacement{ snap: target }, screen_width, screen_height)
	margin := if frame.w >= 220 && frame.h >= 200 {
		12
	} else if frame.w >= 32 && frame.h >= 32 {
		8
	} else {
		0
	}
	width := if frame.w - 2 * margin > 0 { frame.w - 2 * margin } else { 1 }
	height := if frame.h - 2 * margin > 0 { frame.h - 2 * margin } else { 1 }
	mut padding := if width >= 120 {
		12
	} else if width >= 32 {
		4
	} else {
		0
	}
	if padding > height / 4 { padding = height / 4 }
	gap := if width >= 160 { 10 } else { 6 }
	mut header := if height >= 180 { 44 } else { 28 }
	mut footer := if height >= 180 { 44 } else { 30 }
	interior_height := height - 2 * padding
	if header > interior_height / 3 { header = interior_height / 3 }
	if footer > interior_height / 3 { footer = interior_height / 3 }
	inner_width := if width - 2 * padding > 0 { width - 2 * padding } else { 1 }
	inner_height := if height - 2 * padding - header - footer > 0 {
		height - 2 * padding - header - footer
	} else {
		1
	}
	mut columns := (inner_width + gap) / (window_overview_card_width + gap)
	if columns < 1 { columns = 1 }
	if columns > 4 { columns = 4 }
	card_width := (inner_width - (columns - 1) * gap) / columns
	card_height := if inner_height < window_overview_card_height {
		inner_height
	} else {
		window_overview_card_height
	}
	mut rows := (inner_height + gap) / (card_height + gap)
	if rows < 1 { rows = 1 }
	if rows > 4 { rows = 4 }
	return WindowSnapAssistLayout{
		x:           frame.x + margin
		y:           frame.y + margin
		width:       width
		height:      height
		padding:     padding
		gap:         gap
		header:      header
		footer:      footer
		columns:     columns
		rows:        rows
		card_width:  card_width
		card_height: card_height
	}
}

fn (d &Desktop) window_snap_assist_eligible(index int, anchor_id int) bool {
	window := &d.windows[index]
	return window.id != anchor_id && window.workspace == d.current_workspace && !window.minimized
		&& window.width > 0 && window.height > 0 && window.x < d.canvas.width
		&& window.y < desktop_usable_height(d.canvas.height) && window.x + window.width > 0
		&& window.y + window.height > 0
}

fn (d &Desktop) window_snap_assist_occupied(anchor_id int, target WindowSnap) bool {
	for index, window in d.windows {
		if d.window_snap_assist_eligible(index, anchor_id) && window.snap == target {
			return true
		}
	}
	return false
}

fn (d &Desktop) window_snap_assist_anchor_valid() bool {
	index := d.window_index(d.snap_assist.anchor_id) or { return false }
	window := &d.windows[index]
	return window.workspace == d.current_workspace && !window.minimized && !window.maximized
		&& window_snap_assist_opposite(window.snap) == d.snap_assist.target
		&& d.snap_assist.target != .none_
}

fn (d &Desktop) window_snap_assist_count() int {
	mut count := 0
	for index in 0 .. d.windows.len {
		if d.window_snap_assist_eligible(index, d.snap_assist.anchor_id) { count++ }
	}
	return count
}

fn (d &Desktop) window_snap_assist_id_at(position int) ?int {
	if position < 0 { return none }
	mut slot := 0
	for index := d.windows.len - 1; index >= 0; index-- {
		if !d.window_snap_assist_eligible(index, d.snap_assist.anchor_id) { continue }
		if slot == position { return d.windows[index].id }
		slot++
	}
	return none
}

fn (d &Desktop) window_snap_assist_position(id int) ?int {
	mut slot := 0
	for index := d.windows.len - 1; index >= 0; index-- {
		if !d.window_snap_assist_eligible(index, d.snap_assist.anchor_id) { continue }
		if d.windows[index].id == id { return slot }
		slot++
	}
	return none
}

fn (mut d Desktop) close_window_snap_assist() {
	if !d.snap_assist.active { return }
	d.snap_assist = WindowSnapAssist{}
	d.set_hover('')
	d.dirty = true
}

// Called by user-facing placement paths, rather than by low-level snaps used
// for setup, restoring a session, or placing the selected companion window.
fn (mut d Desktop) open_window_snap_assist(id int) {
	d.close_window_snap_assist()
	index := d.window_index(id) or { return }
	window := &d.windows[index]
	target := window_snap_assist_opposite(window.snap)
	if target == .none_ || window.workspace != d.current_workspace || window.minimized
		|| window.maximized || d.canvas.width < 2 || desktop_usable_height(d.canvas.height) < 1
		|| d.window_snap_assist_occupied(id, target) {
		return
	}
	mut candidates := false
	for candidate in 0 .. d.windows.len {
		if d.window_snap_assist_eligible(candidate, id) {
			candidates = true
			break
		}
	}
	if !candidates { return }
	d.close_window_actions()
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
	if d.shortcut_press.dragging { d.restore_shortcut_drag() }
	d.shortcut_press = ShortcutPress{}
	d.drag = Drag{}
	d.drag_damage = DamageRect{}
	d.cancel_window_overlay_app_pointer()
	d.chrome_pointer_capture = false
	d.snap_assist = WindowSnapAssist{ active: true, anchor_id: id, target: target }
	d.snap_assist.selected_id = d.window_snap_assist_id_at(0) or { 0 }
	d.set_hover('')
	d.dirty = true
}

fn (mut d Desktop) reconcile_window_snap_assist() {
	if !d.snap_assist.active { return }
	if !d.window_snap_assist_anchor_valid()
		|| d.window_snap_assist_occupied(d.snap_assist.anchor_id, d.snap_assist.target)
		|| d.window_snap_assist_count() == 0 {
		d.close_window_snap_assist()
		return
	}
	position := d.window_snap_assist_position(d.snap_assist.selected_id) or {
		d.snap_assist.selected_id = d.window_snap_assist_id_at(0) or { 0 }
		0
	}
	layout := window_snap_assist_layout(d.snap_assist.target, d.canvas.width, d.canvas.height)
	d.snap_assist.page = position / layout.capacity()
}

fn (mut d Desktop) step_window_snap_assist(step int) {
	d.reconcile_window_snap_assist()
	if !d.snap_assist.active { return }
	count := d.window_snap_assist_count()
	position := d.window_snap_assist_position(d.snap_assist.selected_id) or { 0 }
	next := (position + step % count + count) % count
	d.snap_assist.selected_id = d.window_snap_assist_id_at(next) or { return }
	d.reconcile_window_snap_assist()
	d.dirty = true
}

fn (mut d Desktop) page_window_snap_assist(direction int) {
	d.reconcile_window_snap_assist()
	if !d.snap_assist.active { return }
	layout := window_snap_assist_layout(d.snap_assist.target, d.canvas.width, d.canvas.height)
	count := d.window_snap_assist_count()
	pages := (count + layout.capacity() - 1) / layout.capacity()
	if pages <= 1 { return }
	page := (d.snap_assist.page + direction + pages) % pages
	d.snap_assist.selected_id = d.window_snap_assist_id_at(page * layout.capacity()) or { return }
	d.reconcile_window_snap_assist()
	d.dirty = true
}

fn (mut d Desktop) commit_window_snap_assist(id int) {
	d.reconcile_window_snap_assist()
	if !d.snap_assist.active { return }
	if d.window_snap_assist_position(id) == none {
		// A stale card must never substitute another window at the same index.
		d.dirty = true
		return
	}
	target := d.snap_assist.target
	d.close_window_snap_assist()
	d.snap_window(id, target)
}

fn (mut d Desktop) window_snap_assist_pointer_down(action string, world ActionWorld) bool {
	if !d.snap_assist.active { return false }
	d.reconcile_window_snap_assist()
	if !d.snap_assist.active { return true }
	if world != .desktop {
		d.close_window_snap_assist()
		return true
	}
	if action.starts_with(taskbar_preview_prefix) {
		// Match borrowed, cached selectors directly; parsing their numeric
		// suffix would allocate a substring on every candidate click.
		for window in d.windows {
			if window.id_preview == action {
				d.commit_window_snap_assist(window.id)
				return true
			}
		}
		return true
	}
	if action == window_snap_assist_previous || action == window_snap_assist_next {
		d.page_window_snap_assist(if action == window_snap_assist_previous { -1 } else { 1 })
		return true
	}
	if action != window_snap_assist_panel { d.close_window_snap_assist() }
	return true
}

fn (mut d Desktop) window_snap_assist_sequence(sequence string) {
	if sequence == key_super_up || sequence == key_super_down || sequence == key_super_right
		|| sequence == key_super_left {
		if !d.window_snap_assist_anchor_valid() {
			d.close_window_snap_assist()
			return
		}
		// Super+Up/Down after a half must retain the familiar quarter workflow.
		// Focus may have changed since the offer opened; arrange its anchor.
		anchor := d.snap_assist.anchor_id
		d.close_window_snap_assist()
		d.focus = anchor
		match sequence {
			key_super_up { d.tile_focused(.up) }
			key_super_down { d.tile_focused(.down) }
			key_super_right { d.tile_focused(.right) }
			else { d.tile_focused(.left) }
		}
		return
	}
	layout := window_snap_assist_layout(d.snap_assist.target, d.canvas.width, d.canvas.height)
	match sequence {
		'\x1b[A', '\x1bOA' { d.step_window_snap_assist(-layout.columns) }
		'\x1b[B', '\x1bOB' { d.step_window_snap_assist(layout.columns) }
		'\x1b[C', '\x1bOC' { d.step_window_snap_assist(1) }
		'\x1b[D', '\x1bOD', '\x1b[Z' { d.step_window_snap_assist(-1) }
		else {}
	}
}

// This modal has no opening chord to search for while inactive. Active reads
// are fully consumed, including typing queued after Enter or Escape closes
// it. Prefixes live in a fixed buffer; both paths allocate no output string.
fn (mut d Desktop) take_window_snap_assist_keys(keys string) string {
	d.reconcile_window_snap_assist()
	if !d.snap_assist.active { return keys }
	if keys.len == 0 {
		if d.snap_assist.pending_len == 1 { d.close_window_snap_assist() }
		d.snap_assist.pending_len = 0
		return ''
	}
	for ch in keys {
		if !d.snap_assist.active { continue }
		if d.snap_assist.pending_len > 0 || ch == 0x1b {
			d.snap_assist.pending[d.snap_assist.pending_len] = ch
			d.snap_assist.pending_len++
			sequence := unsafe { tos(&d.snap_assist.pending[0], d.snap_assist.pending_len) }
			mut partial := sequence.len == 1
			mut matched := false
			for candidate in window_snap_assist_sequences {
				result := match_at(sequence, 0, candidate)
				if result > seq_none {
					d.snap_assist.pending_len = 0
					d.window_snap_assist_sequence(candidate)
					matched = true
					break
				}
				if result == seq_partial { partial = true }
			}
			if matched || partial { continue }
			if sequence.len == 2 && ch != `[` && ch != `O` {
				d.close_window_snap_assist()
				continue
			}
			// Modifier release and unrelated CSI chords are consumed without
			// dismissing the offer. Bound the retained packet to 16 bytes.
			if sequence.len > 2 && sequence[1] == `[` && !(ch >= 0x40 && ch <= 0x7e)
				&& d.snap_assist.pending_len < d.snap_assist.pending.len {
				continue
			}
			d.snap_assist.pending_len = 0
			continue
		}
		if ch == 13 || ch == 10 {
			d.commit_window_snap_assist(d.snap_assist.selected_id)
		} else if ch == 9 {
			d.step_window_snap_assist(1)
		}
	}
	return ''
}

fn (mut d Desktop) window_snap_assist_element() ?ui2.Element {
	d.reconcile_window_snap_assist()
	if !d.snap_assist.active { return none }
	layout := window_snap_assist_layout(d.snap_assist.target, d.canvas.width, d.canvas.height)
	mut children := frame_elements(layout.capacity() + 4)
	children << ui2.label('', tr('window.snap_assist.title'),
		ui2.rect(f64(layout.padding), f64(layout.padding), f64(layout.width - 2 * layout.padding), f64(layout.header)),
		ui2.TextStyle{ color: taskbar_preview_text, size: if layout.width < 180 { 12 } else { 16 }, bold: true, lines: 1 })
	start := d.snap_assist.page * layout.capacity()
	mut slot := 0
	mut ordinal := 0
	for index := d.windows.len - 1; index >= 0; index-- {
		if !d.window_snap_assist_eligible(index, d.snap_assist.anchor_id) { continue }
		if ordinal < start {
			ordinal++
			continue
		}
		if slot >= layout.capacity() { break }
		x := layout.padding + slot % layout.columns * (layout.card_width + layout.gap)
		y := layout.padding + layout.header + slot / layout.columns * (layout.card_height + layout.gap)
		selected := d.windows[index].id == d.snap_assist.selected_id
		// The overview card lends title, thumbnail selector and icon. Spread
		// transfers its pooled child array without V cloning borrowed fields.
		children << ui2.Element{
			...d.window_overview_card(index, x, y, layout.card_width, layout.card_height)
			box: ui2.BoxStyle{
				bg:            if selected {
					app_accent
				} else if d.hover == d.windows[index].id_preview {
					taskbar_preview_tile_hover
				} else {
					taskbar_preview_box
				}
				radius:        8
				border_color:  if selected { taskbar_preview_text } else { taskbar_preview_box }
				border_left:   1
				border_right:  1
				border_top:    1
				border_bottom: 1
			}
		}
		slot++
	}
	footer_y := layout.height - layout.padding - layout.footer
	if layout.footer >= 44 {
		children << ui2.label('', tr('window.snap_assist.hint'),
			ui2.rect(f64(layout.padding), f64(footer_y), f64(layout.width - 2 * layout.padding), 18),
			ui2.TextStyle{ color: taskbar_preview_text, size: 11, lines: 1 })
	}
	if d.window_snap_assist_count() > layout.capacity() {
		inner_width := layout.width - 2 * layout.padding
		button_width := if inner_width >= 54 {
			24
		} else if inner_width >= 8 {
			(inner_width - 6) / 2
		} else {
			1
		}
		button_height := if layout.footer >= 24 { 24 } else { layout.footer }
		button_y := layout.height - layout.padding - button_height
		button_gap := if inner_width >= 8 { 6 } else { 0 }
		children << ui2.button_with_image(window_snap_assist_previous, '', 'builtin:arrow_left',
			ui2.rect(f64(layout.padding), f64(button_y), f64(button_width), f64(button_height)),
			ui2.BoxStyle{ bg: taskbar_preview_box, radius: 4 }, ui2.TextStyle{ color: taskbar_preview_text })
		children << ui2.button_with_image(window_snap_assist_next, '', 'builtin:arrow_right',
			ui2.rect(f64(layout.padding + button_width + button_gap), f64(button_y), f64(button_width), f64(button_height)),
			ui2.BoxStyle{ bg: taskbar_preview_box, radius: 4 }, ui2.TextStyle{ color: taskbar_preview_text })
	}
	return ui2.clickable_view(window_snap_assist_dismiss,
		ui2.rect(0, 0, f64(d.canvas.width), f64(d.canvas.height)), ui2.BoxStyle{ transparent: true },
		frame_child(ui2.clickable_view(window_snap_assist_panel,
			ui2.rect(f64(layout.x), f64(layout.y), f64(layout.width), f64(layout.height)),
			ui2.BoxStyle{ bg: taskbar_preview_bg, radius: 12 }, children)))
}
