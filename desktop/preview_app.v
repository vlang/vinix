// SPDX-License-Identifier: GPL-2.0-or-later
// Preview keeps the decoded image at its original resolution. Only the visible
// viewport becomes a compositor surface, so zooming does not allocate an
// enlarged copy of the image or render pixels outside the window.
module main

const preview_max_source = u64(40 * 1024 * 1024)
const preview_max_pixels = 8 * 1024 * 1024
const preview_max_dimension = 8192
const preview_max_path = 1024
const preview_toolbar_height = 148
const preview_status_height = 28
const preview_max_viewport = 2048
const preview_min_zoom = 10
const preview_max_zoom = 400

const preview_action_open = 'preview.open'
const preview_action_open_path = 'preview.path.open'
const preview_action_export_path = 'preview.path.export'
const preview_action_image = 'preview.image'
const preview_action_fit = 'preview.fit'
const preview_action_actual = 'preview.actual'
const preview_action_zoom_in = 'preview.zoom.in'
const preview_action_zoom_out = 'preview.zoom.out'
const preview_action_rotate_left = 'preview.rotate.left'
const preview_action_rotate_right = 'preview.rotate.right'
const preview_action_export_png = 'preview.export.png'
const preview_action_export_copy = 'preview.export.copy'
const preview_action_pan = 'preview.pan'
const preview_action_select = 'preview.select'
const preview_action_crop = 'preview.crop'
const preview_action_clear_selection = 'preview.selection.clear'

enum PreviewFocus {
	image
	open_path
	export_path
}

struct PreviewApp {
mut:
	open_path          []u8
	export_path        []u8
	loaded_path        string
	source             []u8
	pixels             &u8 = unsafe { nil }
	pixels_from_crop   bool
	width              int
	height             int
	orientation        int = 1
	rotation           int
	fit                bool = true
	zoom               int  = 100
	pan_x              int
	pan_y              int
	viewport_width     int
	viewport_height    int
	focus              PreviewFocus = .open_path
	select_all         bool         = true
	pending            [4]u8
	pending_len        int
	surface_path       string
	surface_image      string
	surface_serial     u64
	surface_background u32
	surface_dirty      bool
	status_key         string = 'preview.status.choose'
	details            string
	details_language   DesktopLanguage
	dragging           bool
	drag_x             int
	drag_y             int
	drag_pan_x         int
	drag_pan_y         int
	tool               PreviewTool
	selection          PreviewSelection
}

fn open_preview(mut _ Desktop) !NativeApp {
	mut app := &PreviewApp{}
	home := if desktop_user_home.len > 0 { desktop_user_home } else { desktop_home }
	path := '${home}/Pictures/image.png'
	preview_set_field(mut app.open_path, path)
	unsafe { path.free() }
	return app
}

fn preview_set_field(mut field []u8, value string) {
	unsafe { field.flags |= .noslices }
	field.clear()
	for byte in value {
		if field.len >= preview_max_path { break }
		field << byte
	}
}

fn preview_path_valid(path string) bool {
	if path.len == 0 || path.len > preview_max_path { return false }
	mut at := 0
	for at < path.len {
		first := path[at]
		if first < 32 || first == 127 { return false }
		if first < 128 {
			at++
			continue
		}
		length := editor_utf8_length(first)
		if length < 2 || at + length > path.len { return false }
		for offset in 1 .. length {
			if !editor_utf8_follows(first, offset, path[at + offset]) { return false }
		}
		at += length
	}
	return true
}

fn preview_source_supported(bytes []u8) bool {
	if bytes.len >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff {
		return true
	}
	signature := [u8(0x89), `P`, `N`, `G`, `\r`, `\n`, 0x1a, `\n`]!
	if bytes.len < signature.len { return false }
	for index, byte in signature {
		if bytes[index] != byte { return false }
	}
	return true
}

fn preview_dimensions_valid(width int, height int) bool {
	return width > 0 && height > 0 && width <= preview_max_dimension
		&& height <= preview_max_dimension && i64(width) * i64(height) <= preview_max_pixels
}

fn (mut a PreviewApp) set_status(key string) {
	a.status_key = key
}

fn (mut a PreviewApp) release_surface() {
	if a.surface_path.len > 0 { desktop_unlink(a.surface_path) }
	unsafe {
		a.surface_path.free()
		a.surface_image.free()
	}
	a.surface_path = ''
	a.surface_image = ''
}

fn (mut a PreviewApp) release_image() {
	a.release_surface()
	a.release_pixels()
	unsafe {
		a.source.free()
		a.loaded_path.free()
		a.details.free()
	}
	a.pixels = unsafe { nil }
	a.source = []u8{}
	a.loaded_path = ''
	a.details = ''
	a.width = 0
	a.height = 0
	a.orientation = 1
	a.rotation = 0
	a.dragging = false
	a.tool = .pan
	a.selection = PreviewSelection{}
	a.surface_dirty = false
}

fn (mut a PreviewApp) open_image() bool {
	// The editable byte array is lent to UI text, but POSIX paths must have a
	// terminator. A shorter edit can leave old bytes beyond the array's length.
	path := editor_bytes_text(a.open_path).clone()
	defer { unsafe { path.free() } }
	if path.len == 0 {
		a.set_status('preview.status.enter_path')
		return false
	}
	if !preview_path_valid(path) {
		a.set_status('preview.status.cannot_open')
		return false
	}
	fd := C.open(&char(path.str), C.O_RDONLY | C.O_NONBLOCK)
	if fd < 0 {
		a.set_status('preview.status.cannot_open')
		return false
	}
	defer { desktop_close(fd) }
	mut stat := C.stat{}
	if C.fstat(fd, &stat) != 0
		|| u32(stat.st_mode) & u32(C.S_IFMT) != u32(C.S_IFREG) || stat.st_size <= 0 {
		a.set_status('preview.status.cannot_open')
		return false
	}
	if u64(stat.st_size) > preview_max_source {
		a.set_status('preview.status.source_limit')
		return false
	}
	mut source := []u8{len: int(stat.st_size)}
	mut offset := 0
	for offset < source.len {
		got := desktop_read(fd, unsafe { &u8(source.data) + offset }, u64(source.len - offset))
		if got <= 0 {
			unsafe { source.free() }
			a.set_status('preview.status.cannot_open')
			return false
		}
		offset += int(got)
	}
	if !preview_source_supported(source) {
		pdf := source.len >= 4 && source[0] == `%` && source[1] == `P` && source[2] == `D`
			&& source[3] == `F`
		unsafe { source.free() }
		a.set_status(if pdf {
			'preview.status.pdf_unavailable'
		} else {
			'preview.status.unsupported'
		})
		return false
	}
	// Own and release the tiny output buffer explicitly. Native V promotes
	// both scalar and fixed-array addresses passed to stb without freeing them.
	mut dimensions := []int{len: 3}
	defer { unsafe { dimensions.free() } }
	if C.stbi_info_from_memory(source.data, source.len, unsafe { &dimensions[0] },
		unsafe { &dimensions[1] }, unsafe { &dimensions[2] }) == 0 {
		unsafe { source.free() }
		a.set_status('preview.status.cannot_decode')
		return false
	}
	if !preview_dimensions_valid(dimensions[0], dimensions[1]) {
		unsafe { source.free() }
		a.set_status('preview.status.pixel_limit')
		return false
	}
	if source[0] == 0x89 && !preview_png_inflate_bounded(source, dimensions[0], dimensions[1]) {
		unsafe { source.free() }
		a.set_status('preview.status.cannot_decode')
		return false
	}
	// Apple's optimized PNG variant stores premultiplied BGRA. Keep the
	// application's decoded pixels consistently in straight-alpha RGBA.
	C.stbi_convert_iphone_png_to_rgb(1)
	C.stbi_set_unpremultiply_on_load(1)
	pixels := C.stbi_load_from_memory(source.data, source.len, unsafe { &dimensions[0] },
		unsafe { &dimensions[1] }, unsafe { &dimensions[2] }, 4)
	if pixels == unsafe { nil } {
		unsafe { source.free() }
		a.set_status('preview.status.cannot_decode')
		return false
	}
	if !preview_dimensions_valid(dimensions[0], dimensions[1]) {
		C.stbi_image_free(pixels)
		unsafe { source.free() }
		a.set_status('preview.status.pixel_limit')
		return false
	}
	// Commit only a complete decode. An unsuccessful Open leaves the existing
	// image and its original-copy bytes available.
	loaded_path := path.clone()
	a.release_image()
	a.loaded_path = loaded_path
	a.source = source
	a.pixels = pixels
	a.width = dimensions[0]
	a.height = dimensions[1]
	a.orientation = preview_jpeg_orientation(source)
	a.rotation = 0
	a.fit = true
	a.zoom = 100
	a.pan_x = 0
	a.pan_y = 0
	a.focus = .image
	a.select_all = false
	a.pending_len = 0
	a.surface_dirty = true

	a.refresh_details()
	a.set_status('preview.status.opened')
	record_recent_item('vinix-preview', a.loaded_path)
	return true
}

fn (a &PreviewApp) oriented_dimensions() (int, int) {
	width, height := a.exif_dimensions()
	return if a.rotation & 1 == 0 { width } else { height }, if a.rotation & 1 == 0 {
		height
	} else { width }
}

@[inline]
fn (a &PreviewApp) pixel_offset(x int, y int) int {
	// Undo the user's turn in EXIF-oriented coordinates, then map that pixel
	// into the unchanged decoder allocation. Rendering and PNG export share
	// this composition, including the four mirrored EXIF orientations.
	width, height := a.exif_dimensions()
	mut exif_x := x
	mut exif_y := y
	match a.rotation {
		1 { exif_x = y; exif_y = height - 1 - x }
		2 { exif_x = width - 1 - x; exif_y = height - 1 - y }
		3 { exif_x = width - 1 - y; exif_y = x }
		else {}
	}
	return match a.orientation {
		2 { (exif_y * a.width + a.width - 1 - exif_x) * 4 }
		3 { ((a.height - 1 - exif_y) * a.width + a.width - 1 - exif_x) * 4 }
		4 { ((a.height - 1 - exif_y) * a.width + exif_x) * 4 }
		5 { (exif_x * a.width + exif_y) * 4 }
		6 { ((a.height - 1 - exif_x) * a.width + exif_y) * 4 }
		7 { ((a.height - 1 - exif_x) * a.width + a.width - 1 - exif_y) * 4 }
		8 { (exif_x * a.width + a.width - 1 - exif_y) * 4 }
		else { (exif_y * a.width + exif_x) * 4 }
	}
}

struct PreviewGeometry {
	width  int
	height int
	left   int
	top    int
}

fn (a &PreviewApp) geometry() PreviewGeometry {
	width, height := a.oriented_dimensions()
	if width <= 0 || height <= 0 || a.viewport_width <= 0 || a.viewport_height <= 0 {
		return PreviewGeometry{}
	}
	mut scaled_width := width * a.zoom / 100
	mut scaled_height := height * a.zoom / 100
	if a.fit {
		// Fit may shrink below the manual zoom minimum. Small pictures are
		// enlarged by at most the same 400% used by the zoom controls.
		scaled_width = if a.viewport_width < width * 4 { a.viewport_width } else { width * 4 }
		scaled_height = scaled_width * height / width
		if scaled_height > a.viewport_height {
			scaled_height = a.viewport_height
			scaled_width = scaled_height * width / height
		}
	}
	if scaled_width < 1 { scaled_width = 1 }
	if scaled_height < 1 { scaled_height = 1 }
	return PreviewGeometry{
		width:  scaled_width
		height: scaled_height
		left:   if scaled_width <= a.viewport_width {
			(a.viewport_width - scaled_width) / 2
		} else {
			-a.pan_x
		}
		top:    if scaled_height <= a.viewport_height {
			(a.viewport_height - scaled_height) / 2
		} else {
			-a.pan_y
		}
	}
}

fn (mut a PreviewApp) clamp_pan() {
	geometry := a.geometry()
	a.pan_x = files_clamp(a.pan_x, if geometry.width > a.viewport_width {
		geometry.width - a.viewport_width
	} else {
		0
	})
	a.pan_y = files_clamp(a.pan_y, if geometry.height > a.viewport_height {
		geometry.height - a.viewport_height
	} else {
		0
	})
}

fn (mut a PreviewApp) center_pan() {
	geometry := a.geometry()
	a.pan_x = if geometry.width > a.viewport_width {
		(geometry.width - a.viewport_width) / 2
	} else {
		0
	}
	a.pan_y = if geometry.height > a.viewport_height {
		(geometry.height - a.viewport_height) / 2
	} else {
		0
	}
}

fn (mut a PreviewApp) refresh_details() {
	unsafe { a.details.free() }
	width, height := a.oriented_dimensions()
	width_text := width.str()
	height_text := height.str()
	zoom_number := a.zoom.str()
	zoom_text := if a.fit {
		tr('preview.fit')
	} else {
		tr_fill('preview.zoom.percent', zoom_number)
	}
	a.details = tr_fill3('preview.details', width_text, height_text, zoom_text)
	unsafe {
		width_text.free()
		height_text.free()
		zoom_number.free()
		if !a.fit { zoom_text.free() }
	}
	a.details_language = desktop_language
}

fn (mut a PreviewApp) set_zoom(percent int) {
	a.reset_selection()
	a.fit = false
	a.zoom = if percent < preview_min_zoom {
		preview_min_zoom
	} else if percent > preview_max_zoom {
		preview_max_zoom
	} else {
		percent
	}
	a.center_pan()
	a.surface_dirty = true
	a.refresh_details()
}

fn (mut a PreviewApp) zoom_by(delta int) {
	mut current := a.zoom
	if a.fit && a.width > 0 {
		geometry := a.geometry()
		width, _ := a.oriented_dimensions()
		current = geometry.width * 100 / width
	}
	a.set_zoom(current + delta)
}

fn (mut a PreviewApp) fit_image() {
	a.reset_selection()
	a.fit = true
	a.pan_x = 0
	a.pan_y = 0
	a.surface_dirty = true
	a.refresh_details()
}

fn (mut a PreviewApp) rotate(delta int) {
	if a.pixels == unsafe { nil } { return }
	a.reset_selection()
	a.rotation = (a.rotation + delta + 4) % 4
	a.center_pan()
	a.surface_dirty = true
	a.refresh_details()
}

fn (mut a PreviewApp) pan(dx int, dy int) {
	if a.fit { return }
	old_x := a.pan_x
	old_y := a.pan_y
	a.pan_x += dx
	a.pan_y += dy
	a.clamp_pan()
	if a.pan_x != old_x || a.pan_y != old_y {
		if a.selection.active { a.reset_selection() }
		a.surface_dirty = true
	}
}

fn (mut a PreviewApp) close_app() {
	a.release_image()
	unsafe {
		a.open_path.free()
		a.export_path.free()
	}
	a = PreviewApp{}
}
