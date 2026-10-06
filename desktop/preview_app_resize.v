// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Decimal pixel dimensions stay inline, including a terminator. Editing or
// synchronizing controls never allocates strings or retains per-key buffers.
struct PreviewDimension {
mut:
	bytes [5]u8
	len   int
}

enum PreviewEdit {
	crop
	resize
}

fn (field &PreviewDimension) text() string {
	return unsafe { tos(&u8(&field.bytes[0]), field.len) }
}

fn (field &PreviewDimension) value() int {
	if field.len < 1 || field.len > 4 { return 0 }
	mut value := 0
	for index in 0 .. field.len {
		byte := field.bytes[index]
		if byte < `0` || byte > `9` { return 0 }
		value = value * 10 + int(byte - `0`)
	}
	return value
}

fn (mut field PreviewDimension) set(value int) {
	field = PreviewDimension{}
	if value < 1 || value > preview_max_dimension { return }
	mut divisor := 1000
	for divisor > value { divisor /= 10 }
	mut remaining := value
	for divisor > 0 {
		field.bytes[field.len] = u8(`0` + remaining / divisor)
		field.len++
		remaining %= divisor
		divisor /= 10
	}
}

fn (mut a PreviewApp) refresh_resize_fields() {
	width, height := a.oriented_dimensions()
	a.resize_width.set(width)
	a.resize_height.set(height)
}

fn (mut a PreviewApp) resize_partner() {
	if !a.resize_locked || a.pixels == unsafe { nil } { return }
	width, height := a.oriented_dimensions()
	if !preview_dimensions_valid(width, height) { return }
	if a.focus == .resize_height {
		value := a.resize_height.value()
		if value < 1 || value > preview_max_dimension { return }
		partner := (i64(value) * width + height / 2) / height
		if partner > preview_max_dimension { a.resize_width = PreviewDimension{}; return }
		a.resize_width.set(if partner < 1 { 1 } else { int(partner) })
	} else {
		value := a.resize_width.value()
		if value < 1 || value > preview_max_dimension { return }
		partner := (i64(value) * height + width / 2) / width
		if partner > preview_max_dimension { a.resize_height = PreviewDimension{}; return }
		a.resize_height.set(if partner < 1 { 1 } else { int(partner) })
	}
}

fn (mut a PreviewApp) toggle_resize_lock() {
	a.resize_locked = !a.resize_locked
	if a.resize_locked { a.resize_partner() }
}

fn (mut a PreviewApp) resize_key(ch u8) {
	if ch == `\t` {
		a.focus_field(if a.focus == .resize_width { PreviewFocus.resize_height } else { PreviewFocus.open_path })
		return
	}
	if ch == `\r` || ch == `\n` { a.apply_resize(); return }
	if ch == 0x01 { a.select_all = true; return }
	mut field := if a.focus == .resize_width { &a.resize_width } else { &a.resize_height }
	if ch == 0x15 || ch == 8 || ch == 127 {
		if ch == 0x15 || a.select_all { field.set(0) }
		else if field.len > 0 { field.len--; field.bytes[field.len] = 0 }
		a.select_all = false
		a.resize_partner()
		return
	}
	if ch < `0` || ch > `9` { return }
	if !a.select_all && field.len >= 4 { return }
	if a.select_all { field.set(0); a.select_all = false }
	field.bytes[field.len] = ch
	field.len++
	field.bytes[field.len] = 0
	a.resize_partner()
}

fn (mut a PreviewApp) resize_paste(input string) {
	mut field := if a.focus == .resize_width { &a.resize_width } else { &a.resize_height }
	length := if a.select_all { 0 } else { field.len }
	if input.len == 0 || length + input.len > 4 { return }
	for byte in input { if byte < `0` || byte > `9` { return } }
	if a.select_all { field.set(0); a.select_all = false }
	for byte in input { field.bytes[field.len] = byte; field.len++ }
	field.bytes[field.len] = 0
	a.resize_partner()
}

fn (a &PreviewApp) resize_valid() bool {
	return a.pixels != unsafe { nil }
		&& preview_dimensions_valid(a.resize_width.value(), a.resize_height.value())
}

// Pixel-center mapping, fixed at 1/256 of a source pixel and clamped at edges.
// Wide arithmetic bounds IPC-edited dimensions without multiplication overflow.
fn preview_resize_coordinate(at int, input int, output int) (int, int, u64) {
	mut coordinate := ((i64(at) * 2 + 1) * input * 256 / output - 256) / 2
	if coordinate < 0 { coordinate = 0 }
	limit := i64(input - 1) * 256
	if coordinate > limit { coordinate = limit }
	first := int(coordinate / 256)
	return first, if first + 1 < input { first + 1 } else { first }, u64(coordinate % 256)
}

fn (mut a PreviewApp) apply_resize() bool {
	return a.apply_resize_using(preview_allocate_crop)
}

fn (mut a PreviewApp) apply_resize_using(allocate fn (usize) &u8) bool {
	width := a.resize_width.value()
	height := a.resize_height.value()
	input_width, input_height := a.oriented_dimensions()
	if a.pixels == unsafe { nil } || !preview_dimensions_valid(input_width, input_height)
		|| !preview_dimensions_valid(width, height) {
		a.status_key = 'preview.status.resize_invalid'
		return false
	}
	if width == input_width && height == input_height {
		a.status_key = 'preview.status.resize_unchanged'
		return true
	}
	// At most 32 MiB per buffer. Only one new allocation is needed; no scratch
	// image or full rotated copy. Failure preserves active pixels and history.
	pixels := allocate(usize(width * height * 4))
	if pixels == unsafe { nil } { a.status_key = 'preview.status.resize_failed'; return false }
	for y in 0 .. height {
		y0, y1, fy := preview_resize_coordinate(y, input_height, height)
		for x in 0 .. width {
			x0, x1, fx := preview_resize_coordinate(x, input_width, width)
			offsets := [a.pixel_offset(x0, y0), a.pixel_offset(x1, y0),
				a.pixel_offset(x0, y1), a.pixel_offset(x1, y1)]!
			weights := [(256 - fx) * (256 - fy), fx * (256 - fy),
				(256 - fx) * fy, fx * fy]!
			mut alpha := u64(0)
			mut colors := [u64(0), 0, 0]!
			for index in 0 .. 4 {
				offset := offsets[index]
				weighted_alpha := unsafe { u64(a.pixels[offset + 3]) } * weights[index]
				alpha += weighted_alpha
				for channel in 0 .. 3 {
					colors[channel] += unsafe { u64(a.pixels[offset + channel]) } * weighted_alpha
				}
			}
			output := (y * width + x) * 4
			for channel in 0 .. 3 {
				unsafe { pixels[output + channel] = if alpha == 0 { 0 } else { u8((colors[channel] + alpha / 2) / alpha) } }
			}
			unsafe { pixels[output + 3] = u8((alpha + 32768) / 65536) }
		}
	}
	// Transfer ownership after every pixel is complete. A prior alternate is
	// released once; the active buffer becomes the sole Undo state, including
	// its original orientation, selection and view. PNG exports use this edit.
	a.release_crop_history()
	a.crop_history = a.crop_state()
	a.crop_edit = .resize
	a.pixels = pixels
	a.pixels_from_crop = true
	a.width = width
	a.height = height
	a.orientation = 1
	a.rotation = 0
	a.reset_selection()
	a.fit = true
	a.zoom = 100
	a.pan_x = 0
	a.pan_y = 0
	a.focus = .image
	a.select_all = false
	a.pending_len = 0
	a.surface_dirty = true
	a.refresh_details()
	a.refresh_resize_fields()
	a.status_key = 'preview.status.resized'
	return true
}
