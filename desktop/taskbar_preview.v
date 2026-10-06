// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Taskbar thumbnails, the window picker, Aero Peek and Show Desktop.
//
// Resting the pointer on a taskbar button opens a panel above it with a live
// thumbnail of each of the button's windows. Clicking a grouped button opens
// the same panel at once, so one of several windows can be chosen instead of
// only the most recent. Resting on a thumbnail peeks at that window: every
// other window turns into a glass outline. The strip in the lower-right corner
// shows the desktop when clicked and peeks at it when rested on.
//
// Thumbnails are sampled from the composed canvas rather than rendered again:
// a remote application's tree is fetched over its pipe once per frame, and a
// second build just for a picture would double that cost. A window's picture
// is refreshed whenever it is fully in view, and a covered or minimized window
// keeps the last one taken, which is also what Windows shows for a window it
// cannot currently compose.
module main

import ui2

const taskbar_preview_prefix = 'preview.'
const taskbar_preview_panel = 'taskbar.preview'
const action_show_desktop = 'taskbar.showdesktop'
const window_thumbnail_image_prefix = 'thumbnail:'
const peek_ghost_id = 'peek.ghost'
const taskbar_tooltip_id = 'taskbar.tooltip'
const key_super_d = '\x1b[100;9u'

const taskbar_show_desktop_width = 12
const taskbar_preview_delay_ms = i64(400)
const taskbar_preview_linger_ms = i64(350)
const taskbar_peek_delay_ms = i64(500)
const taskbar_tooltip_delay_ms = i64(600)
const taskbar_hover_poll_ms = i64(50)
const thumbnail_max_width = 196
const thumbnail_max_height = 118
const thumbnail_capture_interval_ms = i64(250)
const taskbar_preview_padding = 8
const taskbar_preview_title_height = 24
const taskbar_preview_gap = 4
const taskbar_preview_margin = 8
const taskbar_preview_list_row = 30
const taskbar_preview_list_width = 300
const taskbar_preview_bg = u32(0x1c2536)
const taskbar_preview_alpha = u32(226)
const taskbar_preview_edge = u32(0x56627c)
const taskbar_preview_tile_hover = u32(0x3c4b68)
const taskbar_preview_text = u32(0xf2f5fa)
const taskbar_preview_box = u32(0x2a3447)
const taskbar_preview_close_hover = u32(0xd8443a)
const peek_ghost_alpha = u32(34)
const peek_ghost_edge_alpha = u32(150)

struct TaskbarPreview {
mut:
	// The button under the pointer that has windows, by stable key (owned).
	hover_key   string
	hover_since i64
	open        bool
	// The button whose windows the panel shows (owned).
	key string
	// The centre of that button, which the panel is centred over.
	anchor_x    int
	leave_since i64
	// Where the panel was last laid out, so thumbnails are never sampled from
	// a window it covers.
	panel_x      int
	panel_y      int
	panel_width  int
	panel_height int
	// Aero Peek at one window, after resting on its thumbnail.
	thumb_hover int
	thumb_since i64
	peek_window int
	// Aero Peek at the desktop, after resting on Show Desktop.
	desktop_since i64
	peek_desktop  bool
	// A short description of a status icon or Show Desktop (owned action).
	tooltip_action string
	tooltip_since  i64
	tooltip_shown  bool
	tooltip_x      int
	tooltip_y      int
	tooltip_width  int
	tooltip_height int
	last_capture   i64
}

struct ShowDesktop {
mut:
	active    bool
	workspace int
	// The windows Show Desktop minimized, bottom to top, for putting back.
	hidden []int
}

// ── Hover timing ───────────────────────────────────────────────────

// replace_owned releases an owned string and returns an owned copy of the
// value to store in its place; an unchanged value is kept as it is.
fn replace_owned(slot string, value string) string {
	if slot == value {
		return slot
	}
	if slot.len > 0 {
		unsafe { slot.free() }
	}
	return if value.len > 0 { value.clone() } else { '' }
}

fn preview_window_id(action string) int {
	if !action.starts_with(taskbar_preview_prefix) {
		return 0
	}
	return action[taskbar_preview_prefix.len..].int()
}

fn (mut d Desktop) update_taskbar_hover() {
	d.update_taskbar_hover_at(monotonic_millis())
}

// update_taskbar_hover_at turns the pointer's resting place into the preview,
// peek and tooltip states. It runs once per compositor pass; the timestamps
// make every delay independent of how often that is.
fn (mut d Desktop) update_taskbar_hover_at(now i64) {
	if d.taskbar_press.dragging || d.start_menu_open || create_context_menu.visible
		|| d.switcher.active || d.overview.active || d.window_layout.active
		|| d.drag.kind != .none_ || d.tray.flyout != .none_ {
		d.close_taskbar_preview()
		d.end_peek()
		d.hide_tooltip()
		return
	}
	hover := d.hover
	mut hovered := TaskbarEntry{}
	mut hovered_key := ''
	if taskbar_entry_action(hover) {
		if entry := d.taskbar_entry_for_action(hover) {
			if entry.window_count > 0 {
				hovered = entry
				hovered_key = entry.key
			}
		}
	}
	in_panel := hover == taskbar_preview_panel || hover.starts_with(taskbar_preview_prefix)
	if hovered_key != d.taskbar_preview.hover_key {
		d.taskbar_preview.hover_key = replace_owned(d.taskbar_preview.hover_key, hovered_key)
		d.taskbar_preview.hover_since = now
		// Once the panel is up, moving along the taskbar switches it at once.
		if d.taskbar_preview.open && hovered_key.len > 0 {
			d.open_taskbar_preview(hovered)
		}
	}
	if hovered_key.len > 0 && !d.taskbar_preview.open
		&& now - d.taskbar_preview.hover_since >= taskbar_preview_delay_ms {
		d.open_taskbar_preview(hovered)
	}
	if d.taskbar_preview.open {
		if hovered_key.len > 0 || in_panel {
			d.taskbar_preview.leave_since = 0
		} else if d.taskbar_preview.leave_since == 0 {
			d.taskbar_preview.leave_since = now
		} else if now - d.taskbar_preview.leave_since >= taskbar_preview_linger_ms {
			d.close_taskbar_preview()
		}
	}

	thumb := if d.taskbar_preview.open { preview_window_id(hover) } else { 0 }
	if thumb != d.taskbar_preview.thumb_hover {
		d.taskbar_preview.thumb_hover = thumb
		d.taskbar_preview.thumb_since = now
		if d.taskbar_preview.peek_window != 0 {
			d.taskbar_preview.peek_window = 0
			d.dirty = true
		}
	} else if thumb != 0 && d.taskbar_preview.peek_window == 0
		&& now - d.taskbar_preview.thumb_since >= taskbar_peek_delay_ms {
		d.taskbar_preview.peek_window = thumb
		d.dirty = true
	}

	if hover == action_show_desktop {
		if d.taskbar_preview.desktop_since == 0 {
			d.taskbar_preview.desktop_since = now
		} else if !d.taskbar_preview.peek_desktop
			&& now - d.taskbar_preview.desktop_since >= taskbar_peek_delay_ms {
			d.taskbar_preview.peek_desktop = true
			d.dirty = true
		}
	} else {
		d.taskbar_preview.desktop_since = 0
		if d.taskbar_preview.peek_desktop {
			d.taskbar_preview.peek_desktop = false
			d.dirty = true
		}
	}

	tooltip := if d.tooltip_text(hover).len > 0 { hover } else { '' }
	if tooltip != d.taskbar_preview.tooltip_action {
		d.hide_tooltip()
		d.taskbar_preview.tooltip_action = replace_owned(d.taskbar_preview.tooltip_action, tooltip)
		d.taskbar_preview.tooltip_since = now
	} else if tooltip.len > 0 && !d.taskbar_preview.tooltip_shown
		&& now - d.taskbar_preview.tooltip_since >= taskbar_tooltip_delay_ms {
		d.taskbar_preview.tooltip_shown = true
		d.dirty = true
	}
}

fn (mut d Desktop) hide_tooltip() {
	if d.taskbar_preview.tooltip_shown {
		d.taskbar_preview.tooltip_shown = false
		d.dirty = true
	}
	d.taskbar_preview.tooltip_action = replace_owned(d.taskbar_preview.tooltip_action, '')
}

// A pending delay needs the loop to come back for it; nothing else would
// wake an idle desktop whose pointer has simply stopped moving.
fn (d &Desktop) taskbar_hover_idle_interval(maximum i64) i64 {
	p := &d.taskbar_preview
	pending := (p.hover_key.len > 0 && !p.open) || (p.open && p.leave_since != 0)
		|| (p.thumb_hover != 0 && p.peek_window == 0)
		|| (p.desktop_since != 0 && !p.peek_desktop)
		|| (p.tooltip_action.len > 0 && !p.tooltip_shown)
	if pending && taskbar_hover_poll_ms < maximum {
		return taskbar_hover_poll_ms
	}
	return maximum
}

fn (mut d Desktop) open_taskbar_preview(entry TaskbarEntry) {
	if entry.window_count == 0 {
		return
	}
	d.taskbar_preview.key = replace_owned(d.taskbar_preview.key, entry.key)
	d.taskbar_preview.open = true
	d.taskbar_preview.leave_since = 0
	if target := d.hit_target_named(entry.id) {
		d.taskbar_preview.anchor_x = target.x + target.width / 2
	}
	d.dirty = true
}

fn (mut d Desktop) close_taskbar_preview() {
	if !d.taskbar_preview.open {
		return
	}
	d.taskbar_preview.open = false
	d.taskbar_preview.key = replace_owned(d.taskbar_preview.key, '')
	d.taskbar_preview.leave_since = 0
	d.taskbar_preview.thumb_hover = 0
	d.taskbar_preview.panel_width = 0
	d.taskbar_preview.panel_height = 0
	if d.taskbar_preview.peek_window != 0 {
		d.taskbar_preview.peek_window = 0
	}
	d.dirty = true
}

fn (mut d Desktop) end_peek() {
	if d.taskbar_preview.peek_window != 0 || d.taskbar_preview.peek_desktop {
		d.dirty = true
	}
	d.taskbar_preview.peek_window = 0
	d.taskbar_preview.peek_desktop = false
	d.taskbar_preview.thumb_hover = 0
	d.taskbar_preview.desktop_since = 0
}

// peek_target is the window Aero Peek keeps solid: a window id, -1 for the
// desktop itself (every window a ghost), or 0 when not peeking.
fn (d &Desktop) peek_target() int {
	if d.taskbar_preview.peek_desktop {
		return -1
	}
	return d.taskbar_preview.peek_window
}

// ── Clicks ─────────────────────────────────────────────────────────

// taskbar_entry_click is a press on a taskbar button. A button with several
// windows opens the picker; pressing it again while the picker is showing
// brings up the most recent window, as a single click used to.
fn (mut d Desktop) taskbar_entry_click(action string, x int, y int) {
	entry := d.taskbar_entry_for_action(action) or { return }
	d.hide_tooltip()
	if entry.window_count > 1 {
		if d.taskbar_preview.open && d.taskbar_preview.key == entry.key {
			d.close_taskbar_preview()
			d.activate(entry.window_id)
		} else {
			d.open_taskbar_preview(entry)
		}
		d.begin_taskbar_press(action, x, y, false)
		return
	}
	d.close_taskbar_preview()
	if entry.window_id != 0 {
		d.activate(entry.window_id)
		d.begin_taskbar_press(action, x, y, false)
		return
	}
	// A closed pin starts its program when the click completes.
	d.begin_taskbar_press(action, x, y, entry.pinned)
}

fn (mut d Desktop) handle_preview_action(action string) {
	id := preview_window_id(action)
	if id == 0 {
		return
	}
	if action.ends_with('.close') {
		d.close_window(id)
		d.end_peek()
		d.dirty = true
		return
	}
	d.close_taskbar_preview()
	d.end_peek()
	d.activate(id)
}

// ── Show Desktop ───────────────────────────────────────────────────

// toggle_show_desktop minimizes every window on this workspace, and a second
// use puts back exactly the windows it hid. Opening a window in between means
// there is something to hide again, so the next use hides that as well.
fn (mut d Desktop) toggle_show_desktop() {
	d.end_peek()
	d.close_taskbar_preview()
	mut visible := []int{cap: d.windows.len}
	defer { unsafe { visible.free() } }
	for window in d.windows {
		if window.workspace == d.current_workspace && !window.minimized {
			visible << window.id
		}
	}
	if visible.len > 0 {
		if !d.show_desktop.active || d.show_desktop.workspace != d.current_workspace {
			d.show_desktop.hidden.clear()
		}
		for id in visible {
			d.minimize(id)
			if !shortcut_order_contains(d.show_desktop.hidden, id) {
				d.show_desktop.hidden << id
			}
		}
		d.show_desktop.active = true
		d.show_desktop.workspace = d.current_workspace
		d.focus = 0
		d.dirty = true
		return
	}
	if !d.show_desktop.active || d.show_desktop.workspace != d.current_workspace {
		return
	}
	for id in d.show_desktop.hidden {
		index := d.window_index(id) or { continue }
		if d.windows[index].workspace != d.current_workspace {
			continue
		}
		d.windows[index].minimized = false
		d.raise(id)
	}
	d.show_desktop.hidden.clear()
	d.show_desktop.active = false
	d.dirty = true
}

// ── Thumbnails ─────────────────────────────────────────────────────

// thumbnail_size fits a window into the preview box without changing its
// shape. Both dimensions are at least one logical pixel.
fn thumbnail_size(width int, height int) (int, int) {
	if width <= 0 || height <= 0 {
		return 1, 1
	}
	mut thumb_width := thumbnail_max_width
	mut thumb_height := height * thumbnail_max_width / width
	if thumb_height > thumbnail_max_height {
		thumb_height = thumbnail_max_height
		thumb_width = width * thumbnail_max_height / height
	}
	if thumb_width < 1 {
		thumb_width = 1
	}
	if thumb_height < 1 {
		thumb_height = 1
	}
	return thumb_width, thumb_height
}

fn rects_overlap(ax int, ay int, aw int, ah int, bx int, by int, bw int, bh int) bool {
	return ax < bx + bw && bx < ax + aw && ay < by + bh && by < ay + ah
}

// window_in_clear_view reports whether nothing the compositor drew after a
// window covers any of it, which is when its canvas pixels are its picture.
fn (d &Desktop) window_in_clear_view(index int) bool {
	window := &d.windows[index]
	if window.x < 0 || window.y < 0 || window.x + window.width > d.canvas.width
		|| window.y + window.height > d.canvas.height - taskbar_height {
		return false
	}
	for above in index + 1 .. d.windows.len {
		other := &d.windows[above]
		if other.workspace != d.current_workspace || other.minimized {
			continue
		}
		if rects_overlap(window.x, window.y, window.width, window.height, other.x, other.y,
			other.width, other.height) {
			return false
		}
	}
	p := &d.taskbar_preview
	if p.panel_width > 0 && rects_overlap(window.x, window.y, window.width, window.height,
		p.panel_x, p.panel_y, p.panel_width, p.panel_height) {
		return false
	}
	if p.tooltip_shown && rects_overlap(window.x, window.y, window.width, window.height,
		p.tooltip_x, p.tooltip_y, p.tooltip_width, p.tooltip_height) {
		return false
	}
	if d.tray.flyout != .none_ && rects_overlap(window.x, window.y, window.width, window.height,
		d.tray.flyout_x, d.tray.flyout_y, d.tray.flyout_width, d.tray.flyout_height) {
		return false
	}
	return true
}

// capture_window_thumbnails runs after the tree is rendered and before the
// cursor is drawn, so pictures never contain the pointer. It samples on a slow
// cadence, and every frame while the preview panel is showing its pictures.
fn (mut d Desktop) capture_window_thumbnails() {
	if d.peek_target() != 0 || d.start_menu_open || d.switcher.shown || d.overview.active
		|| d.window_layout.active || d.drag.kind == .move {
		return
	}
	now := monotonic_millis()
	if !d.taskbar_preview.open && d.taskbar_preview.last_capture != 0
		&& now >= d.taskbar_preview.last_capture
		&& now - d.taskbar_preview.last_capture < thumbnail_capture_interval_ms {
		return
	}
	d.taskbar_preview.last_capture = now
	for index in 0 .. d.windows.len {
		if d.windows[index].workspace != d.current_workspace || d.windows[index].minimized {
			continue
		}
		if d.window_in_clear_view(index) {
			d.capture_window_thumbnail(index)
		}
	}
}

// capture_window_thumbnail box-filters the window's backing-store pixels with
// four samples per thumbnail pixel, which keeps text from turning into noise.
fn (mut d Desktop) capture_window_thumbnail(index int) {
	scale := d.canvas.scale
	logical_width, logical_height := thumbnail_size(d.windows[index].width,
		d.windows[index].height)
	width := logical_width * scale
	height := logical_height * scale
	if d.windows[index].thumbnail.len != width * height {
		if d.windows[index].thumbnail.cap > 0 {
			unsafe { d.windows[index].thumbnail.free() }
		}
		d.windows[index].thumbnail = []u32{len: width * height}
	}
	d.windows[index].thumbnail_width = logical_width
	d.windows[index].thumbnail_height = logical_height
	d.windows[index].thumbnail_scale = scale
	source_x := d.windows[index].x * scale
	source_y := d.windows[index].y * scale
	source_width := d.windows[index].width * scale
	source_height := d.windows[index].height * scale
	stride := d.canvas.stride
	limit_x := d.canvas.physical_width - 1
	limit_y := d.canvas.physical_height - 1
	for row in 0 .. height {
		mut top := source_y + (row * 4 + 1) * source_height / (height * 4)
		mut bottom := source_y + (row * 4 + 3) * source_height / (height * 4)
		if top > limit_y {
			top = limit_y
		}
		if bottom > limit_y {
			bottom = limit_y
		}
		for column in 0 .. width {
			mut left := source_x + (column * 4 + 1) * source_width / (width * 4)
			mut right := source_x + (column * 4 + 3) * source_width / (width * 4)
			if left > limit_x {
				left = limit_x
			}
			if right > limit_x {
				right = limit_x
			}
			a := unsafe { d.canvas.pixels[top * stride + left] }
			b := unsafe { d.canvas.pixels[top * stride + right] }
			c := unsafe { d.canvas.pixels[bottom * stride + left] }
			e := unsafe { d.canvas.pixels[bottom * stride + right] }
			rb := ((a & 0xff00ff) + (b & 0xff00ff) + (c & 0xff00ff) + (e & 0xff00ff)) >> 2
			g := ((a & 0x00ff00) + (b & 0x00ff00) + (c & 0x00ff00) + (e & 0x00ff00)) >> 2
			d.windows[index].thumbnail[row * width + column] = (rb & 0xff00ff) | (g & 0x00ff00)
		}
	}
}

fn (mut d Desktop) release_window_thumbnail(index int) {
	if d.windows[index].thumbnail.cap > 0 {
		unsafe { d.windows[index].thumbnail.free() }
	}
	d.windows[index].thumbnail = []u32{}
}

// draw_window_thumbnail paints a sampled picture into its element's frame at
// the backing store's density, scaling only if the display scale changed.
fn (mut d Desktop) draw_window_thumbnail(id int, x int, y int, width int, height int) {
	index := d.window_index(id) or { return }
	window := &d.windows[index]
	thumb_scale := window.thumbnail_scale
	source_width := window.thumbnail_width * thumb_scale
	source_height := window.thumbnail_height * thumb_scale
	if window.thumbnail.len == 0 || source_width <= 0 || source_height <= 0 || width <= 0
		|| height <= 0 {
		return
	}
	scale := d.canvas.scale
	target_width := width * scale
	target_height := height * scale
	for row in 0 .. target_height {
		source_row := row * source_height / target_height
		for column in 0 .. target_width {
			source_column := column * source_width / target_width
			d.canvas.blend_physical_pixel(x * scale + column, y * scale + row,
				window.thumbnail[source_row * source_width + source_column], 255)
		}
	}
}

// ── Elements ───────────────────────────────────────────────────────

fn (d &Desktop) preview_entry() ?TaskbarEntry {
	if !d.taskbar_preview.open {
		return none
	}
	entries := d.taskbar_entries()
	defer { unsafe { entries.free() } }
	for entry in entries {
		if entry.key == d.taskbar_preview.key {
			return entry
		}
	}
	return none
}

// taskbar_preview_element lays the panel out over its button: a row of
// thumbnails when they fit, and a list of titles when there are too many, as
// Windows 7 falls back to when its thumbnails would not fit the screen.
fn (mut d Desktop) taskbar_preview_element() ?ui2.Element {
	entry := d.preview_entry() or {
		d.close_taskbar_preview()
		return none
	}
	ids := d.taskbar_entry_window_ids(entry)
	defer { unsafe { ids.free() } }
	if ids.len == 0 {
		d.close_taskbar_preview()
		return none
	}
	pad := taskbar_preview_padding
	tile_width := thumbnail_max_width + 2 * pad
	tile_height := taskbar_preview_title_height + thumbnail_max_height + 2 * pad
	available := d.canvas.width - 2 * taskbar_preview_margin
	fits := (available - taskbar_preview_gap) / (tile_width + taskbar_preview_gap)
	list_mode := ids.len > fits
	panel_width := if list_mode {
		if taskbar_preview_list_width < available { taskbar_preview_list_width } else { available }
	} else {
		ids.len * (tile_width + taskbar_preview_gap) + taskbar_preview_gap
	}
	mut rows := ids.len
	max_rows := (d.canvas.height - taskbar_height - 2 * taskbar_preview_margin - 2 * taskbar_preview_gap) / taskbar_preview_list_row
	if list_mode && rows > max_rows {
		rows = max_rows
	}
	panel_height := if list_mode {
		rows * taskbar_preview_list_row + 2 * taskbar_preview_gap
	} else {
		tile_height + 2 * taskbar_preview_gap
	}
	mut panel_x := d.taskbar_preview.anchor_x - panel_width / 2
	if panel_x + panel_width > d.canvas.width - taskbar_preview_margin {
		panel_x = d.canvas.width - taskbar_preview_margin - panel_width
	}
	if panel_x < taskbar_preview_margin {
		panel_x = taskbar_preview_margin
	}
	panel_y := d.canvas.height - taskbar_height - panel_height - 6
	d.taskbar_preview.panel_x = panel_x
	d.taskbar_preview.panel_y = panel_y
	d.taskbar_preview.panel_width = panel_width
	d.taskbar_preview.panel_height = panel_height

	mut children := frame_elements(ids.len)
	for slot, id in ids {
		if list_mode && slot >= rows {
			break
		}
		index := d.window_index(id) or { continue }
		if list_mode {
			children << d.preview_list_row(index, taskbar_preview_gap, taskbar_preview_gap +
				slot * taskbar_preview_list_row, panel_width - 2 * taskbar_preview_gap)
		} else {
			children << d.preview_tile(index, taskbar_preview_gap + slot * (tile_width +
				taskbar_preview_gap), taskbar_preview_gap, tile_width, tile_height)
		}
	}
	return ui2.clickable_view(taskbar_preview_panel, ui2.rect(f64(panel_x), f64(panel_y),
		f64(panel_width), f64(panel_height)), ui2.BoxStyle{
		bg:     taskbar_preview_bg
		radius: 8
	}, children)
}

fn (d &Desktop) preview_tile_hovered(window &Window) bool {
	return d.hover == window.id_preview || d.hover == window.id_preview_close
}

fn (d &Desktop) preview_close_button(window &Window, x int, y int) ui2.Element {
	hovered := d.hover == window.id_preview_close
	return ui2.button_with_image(window.id_preview_close, '', 'builtin:close', ui2.rect(f64(x),
		f64(y), 20, 18), ui2.BoxStyle{
		bg:          taskbar_preview_close_hover
		radius:      4
		transparent: !hovered
	}, ui2.TextStyle{
		color: 0xffffff
	})
}

fn (d &Desktop) preview_tile(index int, x int, y int, width int, height int) ui2.Element {
	window := &d.windows[index]
	pad := taskbar_preview_padding
	hovered := d.preview_tile_hovered(window)
	mut children := frame_elements(4)
	children << ui2.button_with_image('', '', window.icon, ui2.rect(f64(pad), 5, 16, 16),
		ui2.BoxStyle{
		transparent: true
	}, ui2.TextStyle{
		color: taskbar_preview_text
	})
	children << ui2.label('', app_title_text(window.title), ui2.rect(f64(pad + 22), 3, f64(width - 2 * pad - 46),
		20), ui2.TextStyle{
		color: taskbar_preview_text
		size:  12
	})
	box_y := taskbar_preview_title_height + pad
	if window.thumbnail.len > 0 {
		thumb_width, thumb_height := thumbnail_size(window.width, window.height)
		children << ui2.image('', window.id_thumbnail, ui2.rect(f64(pad + (thumbnail_max_width -
			thumb_width) / 2), f64(box_y + (thumbnail_max_height - thumb_height) / 2),
			f64(thumb_width), f64(thumb_height)))
	} else {
		// No picture has been taken yet -- the window opened covered, or on
		// another workspace. Its icon on a plain card still says what it is.
		children << ui2.view('', ui2.rect(f64(pad), f64(box_y), f64(thumbnail_max_width),
			f64(thumbnail_max_height)), ui2.BoxStyle{
			bg:     taskbar_preview_box
			radius: 4
		}, frame_child(ui2.button_with_image('', '', window.icon, ui2.rect(f64((thumbnail_max_width - 48) / 2),
			f64((thumbnail_max_height - 48) / 2), 48, 48), ui2.BoxStyle{
			transparent: true
		}, ui2.TextStyle{
			color: taskbar_preview_text
		})))
	}
	if hovered {
		children << d.preview_close_button(window, width - pad - 18, 3)
	}
	return ui2.clickable_view(window.id_preview, ui2.rect(f64(x), f64(y), f64(width),
		f64(height)), ui2.BoxStyle{
		bg:          taskbar_preview_tile_hover
		radius:      6
		transparent: !hovered
	}, children)
}

fn (d &Desktop) preview_list_row(index int, x int, y int, width int) ui2.Element {
	window := &d.windows[index]
	hovered := d.preview_tile_hovered(window)
	mut children := frame_elements(3)
	children << ui2.button_with_image('', '', window.icon, ui2.rect(8, 7, 16, 16), ui2.BoxStyle{
		transparent: true
	}, ui2.TextStyle{
		color: taskbar_preview_text
	})
	children << ui2.label('', app_title_text(window.title), ui2.rect(32, 5, f64(width - 64), 20), ui2.TextStyle{
		color: taskbar_preview_text
		size:  12
		bold:  window.id == d.focus
	})
	if hovered {
		children << d.preview_close_button(window, width - 26, 6)
	}
	return ui2.clickable_view(window.id_preview, ui2.rect(f64(x), f64(y), f64(width),
		f64(taskbar_preview_list_row)), ui2.BoxStyle{
		bg:          taskbar_preview_tile_hover
		radius:      5
		transparent: !hovered
	}, children)
}

// peek_ghost_element is what a window becomes while another is peeked at:
// only a faint pane of glass where it was, as Aero Peek draws it.
fn (d &Desktop) peek_ghost_element(index int) ui2.Element {
	return ui2.view(peek_ghost_id, d.windows[index].frame_rect(), ui2.BoxStyle{
		bg:     0xffffff
		radius: d.theme().window_radius
	}, [])
}

fn (mut d Desktop) taskbar_tooltip_element() ?ui2.Element {
	if !d.taskbar_preview.tooltip_shown {
		return none
	}
	action := d.taskbar_preview.tooltip_action
	text := d.tooltip_text(action)
	if text.len == 0 {
		return none
	}
	target := d.hit_target_named(action) or { return none }
	mut width := text.len * 7 + 20
	if d.fonts.len > 0 {
		face := d.face_for(ui2.TextStyle{
			size: 12
		})
		width = face.text_width(text) + 20
	}
	height := 26
	mut x := target.x + target.width / 2 - width / 2
	if x + width > d.canvas.width - 4 {
		x = d.canvas.width - 4 - width
	}
	if x < 4 {
		x = 4
	}
	y := d.canvas.height - taskbar_height - height - 6
	d.taskbar_preview.tooltip_x = x
	d.taskbar_preview.tooltip_y = y
	d.taskbar_preview.tooltip_width = width
	d.taskbar_preview.tooltip_height = height
	return ui2.view(taskbar_tooltip_id, ui2.rect(f64(x), f64(y), f64(width), f64(height)),
		ui2.BoxStyle{
		bg:     app_surface
		radius: 5
	}, frame_child(ui2.label('', text, ui2.rect(10, 0, f64(width - 20), f64(height)),
		ui2.TextStyle{
		color: body_text
		size:  12
	})))
}
