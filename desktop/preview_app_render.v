// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn preview_put_be32(bytes &u8, at int, value u32) {
	unsafe {
		bytes[at] = u8(value >> 24)
		bytes[at + 1] = u8(value >> 16)
		bytes[at + 2] = u8(value >> 8)
		bytes[at + 3] = u8(value)
	}
}

fn (mut a PreviewApp) publish_surface() bool {
	if a.pixels == unsafe { nil } || a.viewport_width <= 0 || a.viewport_height <= 0 {
		return false
	}
	geometry := a.geometry()
	oriented_width, oriented_height := a.oriented_dimensions()
	stride := a.viewport_width * 4
	buffer_size := stride * a.viewport_height
	mut surface := []u8{len: 48 + buffer_size}
	defer { unsafe { surface.free() } }
	files_quicklook_put_u32(mut surface, 0, vinix_surface_magic)
	files_quicklook_put_u32(mut surface, 4, vinix_surface_version)
	files_quicklook_put_u32(mut surface, 8, u32(vinix_surface_header_size))
	files_quicklook_put_u32(mut surface, 12, u32(a.viewport_width))
	files_quicklook_put_u32(mut surface, 16, u32(a.viewport_height))
	files_quicklook_put_u32(mut surface, 20, u32(stride))
	files_quicklook_put_u32(mut surface, 24, vinix_surface_format_xrgb8888)
	files_quicklook_put_u32(mut surface, 40, u32(buffer_size))
	for y in 0 .. a.viewport_height {
		for x in 0 .. a.viewport_width {
			out := 48 + (y * a.viewport_width + x) * 4
			inside := x >= geometry.left && y >= geometry.top && x < geometry.left + geometry.width
				&& y < geometry.top + geometry.height
			if !inside {
				surface[out] = u8(body_panel)
				surface[out + 1] = u8(body_panel >> 8)
				surface[out + 2] = u8(body_panel >> 16)
				continue
			}
			image_x := (x - geometry.left) * oriented_width / geometry.width
			image_y := (y - geometry.top) * oriented_height / geometry.height
			input := a.pixel_offset(image_x, image_y)
			alpha := int(unsafe { a.pixels[input + 3] })
			background := if (image_x / 8 + image_y / 8) & 1 == 0 { 255 } else { 224 }
			for component in 0 .. 3 {
				value := int(unsafe { a.pixels[input + component] })
				surface[out + 2 - component] = u8((value * alpha + background * (255 - alpha)) / 255)
			}
		}
	}
	a.surface_serial++
	pid := C.getpid().str()
	serial := a.surface_serial.str()
	path := '/tmp/vinix-preview-${pid}-${serial}.surface'
	unsafe {
		pid.free()
		serial.free()
	}
	fd := C.open(&char(path.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL, 0o600)
	if fd < 0 {
		unsafe { path.free() }
		return false
	}
	written := desktop_write_all(fd, surface.data, u64(surface.len))
		&& desktop_write_all(fd, unsafe { &surface[48] }, u64(buffer_size))
	closed := desktop_close(fd) == 0
	if !written || !closed {
		desktop_unlink(path)
		unsafe { path.free() }
		return false
	}
	a.release_surface()
	a.surface_path = path
	a.surface_image = vinix_preview_image_prefix + path
	a.surface_background = body_panel
	a.surface_dirty = false
	return true
}

fn (mut a PreviewApp) set_viewport(width int, height int) {
	next_width := if width <= 0 {
		1
	} else if width > preview_max_viewport {
		preview_max_viewport
	} else {
		width
	}
	next_height := if height <= 0 {
		1
	} else if height > preview_max_viewport {
		preview_max_viewport
	} else {
		height
	}
	if a.viewport_width != next_width || a.viewport_height != next_height {
		a.viewport_width = next_width
		a.viewport_height = next_height
		a.clamp_pan()
		a.surface_dirty = a.pixels != unsafe { nil }
	}
}
