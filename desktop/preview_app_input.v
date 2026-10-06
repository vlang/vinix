// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn (mut a PreviewApp) focus_field(focus PreviewFocus) {
	a.focus = focus
	a.select_all = true
	a.pending_len = 0
	a.dragging = false
	a.selection.dragging = false
}

fn (mut a PreviewApp) field_character(length int) {
	mut field := if a.focus == .open_path { &a.open_path } else { &a.export_path }
	unsafe { field.flags |= .noslices }
	if a.select_all {
		field.clear()
		a.select_all = false
	}
	if field.len + length > preview_max_path { return }
	for index in 0 .. length { field << a.pending[index] }
}

fn (mut a PreviewApp) field_ascii(ch u8) {
	mut field := if a.focus == .open_path { &a.open_path } else { &a.export_path }
	unsafe { field.flags |= .noslices }
	if ch == 0x01 {
		a.select_all = true
		return
	}
	if ch == 0x15 {
		field.clear()
		a.select_all = false
		return
	}
	if ch == 8 || ch == 127 {
		if a.select_all {
			field.clear()
			a.select_all = false
		} else if field.len > 0 {
			field.trim(editor_char_before(*field, field.len))
		}
		return
	}
	if ch == `\r` || ch == `\n` {
		if a.focus == .open_path { a.open_image() } else { a.export_image(false) }
		return
	}
	if ch == `\t` {
		a.focus_field(if a.focus == .open_path {
			PreviewFocus.export_path
		} else {
			PreviewFocus.open_path
		})
		return
	}
	if ch >= 32 && ch < 127 {
		if a.select_all {
			field.clear()
			a.select_all = false
		}
		if field.len < preview_max_path { field << ch }
	}
}

fn (mut a PreviewApp) key_input(input string) {
	mut index := 0
	for index < input.len {
		ch := input[index]
		if a.pending_len > 0 {
			if editor_utf8_follows(a.pending[0], a.pending_len, ch) {
				a.pending[a.pending_len] = ch
				a.pending_len++
				if a.pending_len == editor_utf8_length(a.pending[0]) {
					if a.focus != .image { a.field_character(a.pending_len) }
					a.pending_len = 0
				}
				index++
				continue
			}
			a.pending_len = 0
		}
		if ch >= 0x80 {
			if editor_utf8_length(ch) > 1 {
				a.pending[0] = ch
				a.pending_len = 1
			}
			index++
			continue
		}
		if ch == 0x0f {
			a.open_image()
			index++
			continue
		}
		if ch == 0x13 {
			a.export_image(false)
			index++
			continue
		}
		if ch == 0x1b {
			if index + 1 < input.len && (input[index + 1] == `[` || input[index + 1] == `O`) {
				index += 2
				start := index
				for index < input.len && (input[index] < 0x40 || input[index] > 0x7e) { index++ }
				if index < input.len && index == start && a.focus == .image {
					match input[index] {
						`A` { a.pan(0, -64) }
						`B` { a.pan(0, 64) }
						`C` { a.pan(64, 0) }
						`D` { a.pan(-64, 0) }
						else {}
					}
				}
				index++
			} else {
				a.clear_selection()
				a.focus = .image
				a.select_all = false
				index++
			}
			continue
		}
		if a.focus != .image {
			a.field_ascii(ch)
		} else {
			match ch {
				0x01 { a.select_image() }
				`\r`, `\n` { if a.tool == .select { a.apply_crop() } }
				`s`, `S` { a.set_tool(.select) }
				`p`, `P` { a.set_tool(.pan) }
				`+`, `=` { a.zoom_by(25) }
				`-` { a.zoom_by(-25) }
				`0` { a.set_zoom(100) }
				`f`, `F` { a.fit_image() }
				`r`, `R` { a.rotate(1) }
				`l`, `L` { a.rotate(-1) }
				`\t` { a.focus_field(.open_path) }
				else {}
			}
		}
		index++
	}
}

fn (mut a PreviewApp) paste_input(input string) {
	if a.focus == .image || input.len == 0 { return }
	a.pending_len = 0
	mut field := if a.focus == .open_path { &a.open_path } else { &a.export_path }
	existing_length := if a.select_all { 0 } else { field.len }
	if existing_length + input.len > preview_max_path { return }
	unsafe { field.flags |= .noslices }
	if a.select_all {
		field.clear()
		a.select_all = false
	}
	mut at := 0
	for at < input.len {
		first := input[at]
		if first < 128 {
			if first >= 32 && first != 127 { field << first }
			at++
			continue
		}
		length := editor_utf8_length(first)
		mut valid := length > 1 && at + length <= input.len
		if valid {
			for offset in 1 .. length {
				if !editor_utf8_follows(first, offset, input[at + offset]) { valid = false }
			}
		}
		if valid {
			for offset in 0 .. length { field << input[at + offset] }
			at += length
		} else {
			at++
		}
	}
}

fn (mut a PreviewApp) handle(action string) ! {
	a.pending_len = 0
	if action.starts_with(jump_open_prefix) {
		// The borrowed suffix lives until this command finishes; set_field
		// copies it once into the model without allocating a substring.
		path := unsafe { tos(&u8(action.str) + jump_open_prefix.len, action.len - jump_open_prefix.len) }
		if !preview_path_valid(path) {
			a.set_status('preview.status.cannot_open')
			return
		}
		preview_set_field(mut a.open_path, path)
		a.open_image()
		return
	}
	match action {
		preview_action_open { a.open_image() }
		preview_action_open_path { a.focus_field(.open_path) }
		preview_action_export_path { a.focus_field(.export_path) }
		preview_action_image {
			a.focus = .image
			a.select_all = false
		}
		preview_action_fit {
			a.fit_image()
			a.focus = .image
		}
		preview_action_actual {
			a.set_zoom(100)
			a.focus = .image
		}
		preview_action_zoom_in {
			a.zoom_by(25)
			a.focus = .image
		}
		preview_action_zoom_out {
			a.zoom_by(-25)
			a.focus = .image
		}
		preview_action_rotate_left {
			a.rotate(-1)
			a.focus = .image
		}
		preview_action_rotate_right {
			a.rotate(1)
			a.focus = .image
		}
		preview_action_export_png { a.export_image(false) }
		preview_action_export_copy { a.export_image(true) }
		preview_action_pan { a.set_tool(.pan) }
		preview_action_select { a.set_tool(.select) }
		preview_action_crop { a.apply_crop() }
		preview_action_clear_selection { a.clear_selection() }
		else {}
	}
}

fn (a &PreviewApp) pointer_input_enabled() bool { return true }

fn (a &PreviewApp) pointer_moves_matter() bool { return a.dragging || a.selection.dragging }

fn (mut a PreviewApp) pointer_event(phase AppPointerPhase, button AppPointerButton, scroll int,
	x int, y int, width int, height int) {
	if phase == .up {
		a.update_selection(x, y, width, height)
		a.selection.dragging = false
		a.dragging = false
		return
	}
	if a.pixels == unsafe { nil } { return }
	if phase == .scroll && y >= preview_toolbar_height && y < height - preview_status_height {
		a.pan(0, -scroll * 48)
		return
	}
	if phase == .down && button == .left && y >= preview_toolbar_height
		&& y < height - preview_status_height {
		a.focus = .image
		a.select_all = false
		if a.tool == .select {
			a.start_selection(x, y, width, height)
		} else if !a.fit {
			a.dragging = true
			a.drag_x = x
			a.drag_y = y
			a.drag_pan_x = a.pan_x
			a.drag_pan_y = a.pan_y
		}
	} else if phase == .move {
		if a.selection.dragging {
			a.update_selection(x, y, width, height)
		} else if a.dragging {
			a.pan(a.drag_pan_x - (x - a.drag_x) - a.pan_x,
				a.drag_pan_y - (y - a.drag_y) - a.pan_y)
		}
	}
}
