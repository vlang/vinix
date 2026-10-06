// SPDX-License-Identifier: GPL-2.0-or-later
// One fixed-size print canvas, converted in place and streamed by Preview's
// bounded PNG writer. No image or font allocation survives this operation.
module main

const grapher_png_width = 960
const grapher_png_height = 640
const grapher_png_plot_x = 110
const grapher_png_plot_y = 110
const grapher_png_plot_width = 822
const grapher_png_plot_height = 440
const grapher_png_background = u32(0xffffff)
const grapher_png_text = u32(0x273142)
const grapher_png_muted = u32(0x667085)
const grapher_png_grid = u32(0xe5e7eb)
const grapher_png_axis = u32(0x97a1b0)
const grapher_png_curve = u32(0x1671d9)

fn grapher_png_tick(mut canvas Canvas, face &FontFace, value f64, x int, y int, right bool) {
	mut buffer := [64]u8{}
	length := unsafe { C.snprintf(&char(&buffer[0]), 64, c'%.5g', value) }
	text := unsafe { tos(&buffer[0], if length > 0 && length < 64 { length } else { 0 }) }
	if right {
		canvas.draw_text_right(face, x, y, text, grapher_png_muted)
	} else {
		canvas.draw_text(face, x, y, text, grapher_png_muted)
	}
}

fn (app &GrapherApp) write_graph_png(fd int) bool {
	if !app.plotted || app.dirty { return false }
	mut canvas := new_canvas(grapher_png_width, grapher_png_height)
	defer { unsafe { free(canvas.pixels) } }
	face := load_face(face_ui_1x)
	title := load_face(face_large_bold_1x)
	defer {
		unsafe {
			face.glyphs.free()
			face.pixels.free()
			title.glyphs.free()
			title.pixels.free()
		}
	}
	canvas.clear(grapher_png_background)
	canvas.draw_text(unsafe { &title }, 28, 20, tr('app.grapher'), grapher_png_text)
	canvas.draw_text(unsafe { &face }, 28, 57, 'y =', grapher_png_text)
	expression, owned := face.truncate(app.field_text(0), grapher_png_width - 106)
	canvas.draw_text(unsafe { &face }, 68, 57, expression, grapher_png_text)
	if owned { unsafe { expression.free() } }
	canvas.draw_text(unsafe { &face }, 28, 82, tr('grapher.radians'), grapher_png_muted)
	saved := canvas.push_clip_rect(grapher_png_plot_x, grapher_png_plot_y,
		grapher_png_plot_width, grapher_png_plot_height)
	for index in 1 .. 10 {
		canvas.fill_rect(grapher_png_plot_x + grapher_png_plot_width * index / 10,
			grapher_png_plot_y, 1, grapher_png_plot_height, grapher_png_grid)
		canvas.fill_rect(grapher_png_plot_x,
			grapher_png_plot_y + grapher_png_plot_height * index / 10,
			grapher_png_plot_width, 1, grapher_png_grid)
	}
	if app.range[0] <= 0 && app.range[1] >= 0 {
		x := int(-app.range[0] / (app.range[1] - app.range[0]) * f64(grapher_png_plot_width - 1))
		canvas.fill_rect(grapher_png_plot_x + x, grapher_png_plot_y, 1,
			grapher_png_plot_height, grapher_png_axis)
	}
	if app.range[2] <= 0 && app.range[3] >= 0 {
		y := grapher_project_y(0, app.range[2], app.range[3], grapher_png_plot_height)
		canvas.fill_rect(grapher_png_plot_x, grapher_png_plot_y + y,
			grapher_png_plot_width, 1, grapher_png_axis)
	}
	for index in 0 .. grapher_sample_count {
		stroke := app.chart_stroke(index, grapher_png_plot_width, grapher_png_plot_height) or { continue }
		canvas.fill_rect(grapher_png_plot_x + stroke.x, grapher_png_plot_y + stroke.y,
			stroke.width, stroke.height, grapher_png_curve)
	}
	canvas.restore_clip(saved)
	canvas.fill_rect(grapher_png_plot_x - 1, grapher_png_plot_y - 1,
		grapher_png_plot_width + 2, 1, grapher_png_grid)
	canvas.fill_rect(grapher_png_plot_x - 1, grapher_png_plot_y + grapher_png_plot_height,
		grapher_png_plot_width + 2, 1, grapher_png_grid)
	canvas.fill_rect(grapher_png_plot_x - 1, grapher_png_plot_y, 1,
		grapher_png_plot_height, grapher_png_grid)
	canvas.fill_rect(grapher_png_plot_x + grapher_png_plot_width, grapher_png_plot_y,
		1, grapher_png_plot_height, grapher_png_grid)
	grapher_png_tick(mut canvas, unsafe { &face }, app.range[3], 98, grapher_png_plot_y, true)
	grapher_png_tick(mut canvas, unsafe { &face }, app.range[2], 98,
		grapher_png_plot_y + grapher_png_plot_height - face.line_height, true)
	grapher_png_tick(mut canvas, unsafe { &face }, app.range[0], grapher_png_plot_x,
		grapher_png_plot_y + grapher_png_plot_height + 12, false)
	grapher_png_tick(mut canvas, unsafe { &face }, app.range[1],
		grapher_png_plot_x + grapher_png_plot_width,
		grapher_png_plot_y + grapher_png_plot_height + 12, true)
	canvas.draw_text(unsafe { &face }, 28, 318, 'y', grapher_png_text)
	canvas.draw_text_centered(unsafe { &face }, grapher_png_plot_x, 586,
		grapher_png_plot_width, 'x', grapher_png_text)
	canvas.draw_text(unsafe { &face }, 28, 615, tr(app.status), grapher_png_muted)
	// Read each RGB word before changing its bytes; this works on either endian.
	pixels := unsafe { &u8(canvas.pixels) }
	for index in 0 .. grapher_png_width * grapher_png_height {
		color := unsafe { canvas.pixels[index] }
		unsafe {
			pixels[index * 4] = u8(color >> 16)
			pixels[index * 4 + 1] = u8(color >> 8)
			pixels[index * 4 + 2] = u8(color)
			pixels[index * 4 + 3] = 255
		}
	}
	// This descriptor borrows the canvas only for the synchronous stream. It
	// never initializes Preview state and must not call its ownership cleanup.
	image := PreviewApp{ pixels: pixels, width: grapher_png_width, height: grapher_png_height }
	return unsafe { (&image).write_png(fd) }
}

fn (mut app GrapherApp) export_png() {
	app.document_status = ''
	app.export_status = ''
	if app.dirty || !app.plotted {
		if !app.plot() { return }
	}
	path := app.field_text(7)
	if !grapher_document_path_valid(path) {
		app.export_status = 'grapher.png_invalid'
		return
	}
	parent, leaf := archive_parent(path)
	if parent < 0 {
		app.export_status = 'grapher.png_failed'
		return
	}
	defer {
		desktop_close(parent)
		unsafe { leaf.free() }
	}
	fd := C.openat(parent, &char(leaf.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK, 0o600)
	if fd < 0 {
		app.export_status = if C.errno == C.EEXIST { 'grapher.png_exists' } else { 'grapher.png_failed' }
		return
	}
	mut identity := C.stat{}
	identified := unsafe { C.fstat(fd, &identity) } == 0
	written := identified && app.write_graph_png(fd) && desktop_preferences_fsync(fd)
		&& archive_sync_parent(parent, fd)
	closed := desktop_close(fd) == 0
	if !written || !closed {
		mut current := C.stat{}
		if identified && unsafe { C.fstatat(parent, &char(leaf.str), &current, C.AT_SYMLINK_NOFOLLOW) } == 0
			&& current.st_dev == identity.st_dev && current.st_ino == identity.st_ino {
			C.unlinkat(parent, &char(leaf.str), 0)
		}
		app.export_status = 'grapher.png_failed'
		return
	}
	app.export_status = 'grapher.png_saved'
}
