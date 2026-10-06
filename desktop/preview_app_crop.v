// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.malloc(usize) voidptr
fn C.vheap_alloc(voidptr, u64)
fn C.vheap_free(voidptr)

enum PreviewTool {
	pan
	select
}

// Endpoints are inclusive displayed-image pixels. Keep this bounded state
// inline: pointer movement never allocates a pixel mask or a temporary image.
struct PreviewSelection {
mut:
	active   bool
	dragging bool
	anchor_x int
	anchor_y int
	caret_x  int
	caret_y  int
}

struct PreviewCropRect {
	left   int
	top    int
	width  int
	height int
}

// One alternate image owns its buffer independently of the active image.
// Original file bytes and paths stay in PreviewApp, shared by both states.
// Viewport size belongs to the current window; restored pan is clamped to it.
struct PreviewCropState {
	pixels           &u8 = unsafe { nil }
	pixels_from_crop bool
	width            int
	height           int
	orientation      int = 1
	rotation         int
	fit              bool = true
	zoom             int  = 100
	pan_x            int
	pan_y            int
	tool             PreviewTool
	selection        PreviewSelection
}

fn (a &PreviewApp) crop_state() PreviewCropState {
	return PreviewCropState{
		pixels: a.pixels
		pixels_from_crop: a.pixels_from_crop
		width: a.width
		height: a.height
		orientation: a.orientation
		rotation: a.rotation
		fit: a.fit
		zoom: a.zoom
		pan_x: a.pan_x
		pan_y: a.pan_y
		tool: a.tool
		selection: a.selection
	}
}

fn (a &PreviewApp) can_undo_crop() bool {
	return a.crop_history.pixels != unsafe { nil } && !a.crop_undone
}

fn (a &PreviewApp) can_redo_crop() bool {
	return a.crop_history.pixels != unsafe { nil } && a.crop_undone
}

fn (mut a PreviewApp) release_crop_history() {
	preview_release_pixel_buffer(a.crop_history.pixels, a.crop_history.pixels_from_crop)
	a.crop_history = PreviewCropState{}
	a.crop_undone = false
}

fn (mut a PreviewApp) swap_crop_state() {
	// Both buffers remain owned exactly once. Surface files contain their own
	// rendered copy, so neither the compositor nor a UI tree borrows these pixels.
	previous := a.crop_history
	a.crop_history = a.crop_state()
	a.pixels = previous.pixels
	a.pixels_from_crop = previous.pixels_from_crop
	a.width = previous.width
	a.height = previous.height
	a.orientation = previous.orientation
	a.rotation = previous.rotation
	a.fit = previous.fit
	a.zoom = previous.zoom
	a.pan_x = previous.pan_x
	a.pan_y = previous.pan_y
	a.tool = previous.tool
	a.selection = previous.selection
	a.selection.dragging = false
	a.dragging = false
	a.focus = .image
	a.select_all = false
	a.pending_len = 0
	a.clamp_pan()
	a.surface_dirty = true
	a.refresh_details()
}

fn (mut a PreviewApp) undo_crop() bool {
	if !a.can_undo_crop() { return false }
	a.swap_crop_state()
	a.crop_undone = true
	a.status_key = 'preview.status.crop_undone'
	return true
}

fn (mut a PreviewApp) redo_crop() bool {
	if !a.can_redo_crop() { return false }
	a.swap_crop_state()
	a.crop_undone = false
	a.status_key = 'preview.status.crop_redone'
	return true
}

fn (a &PreviewApp) crop_rect() PreviewCropRect {
	if !a.selection.active { return PreviewCropRect{} }
	left := if a.selection.anchor_x < a.selection.caret_x { a.selection.anchor_x } else { a.selection.caret_x }
	top := if a.selection.anchor_y < a.selection.caret_y { a.selection.anchor_y } else { a.selection.caret_y }
	right := if a.selection.anchor_x > a.selection.caret_x { a.selection.anchor_x } else { a.selection.caret_x }
	bottom := if a.selection.anchor_y > a.selection.caret_y { a.selection.anchor_y } else { a.selection.caret_y }
	return PreviewCropRect{left: left, top: top, width: right - left + 1, height: bottom - top + 1}
}

fn (a &PreviewApp) crop_rect_valid(rect PreviewCropRect) bool {
	width, height := a.oriented_dimensions()
	return a.pixels != unsafe { nil } && preview_dimensions_valid(width, height)
		&& rect.left >= 0 && rect.top >= 0 && rect.width > 0 && rect.height > 0
		&& rect.left < width && rect.top < height
		&& rect.width <= width - rect.left && rect.height <= height - rect.top
}

fn (mut a PreviewApp) reset_selection() {
	if a.selection.active { a.surface_dirty = a.pixels != unsafe { nil } }
	a.selection = PreviewSelection{}
	a.dragging = false
	if a.status_key == 'preview.status.selection' {
		a.status_key = if a.tool == .select { 'preview.status.select' } else { 'preview.status.pan' }
	}
}

fn (mut a PreviewApp) set_tool(tool PreviewTool) {
	a.reset_selection()
	a.tool = tool
	a.focus = .image
	a.select_all = false
	a.status_key = if tool == .select { 'preview.status.select' } else { 'preview.status.pan' }
}

fn (mut a PreviewApp) clear_selection() {
	a.reset_selection()
	a.status_key = if a.tool == .select { 'preview.status.select' } else { 'preview.status.pan' }
}

fn (mut a PreviewApp) select_image() {
	if a.pixels == unsafe { nil } { return }
	a.set_tool(.select)
	width, height := a.oriented_dimensions()
	a.selection = PreviewSelection{active: true, caret_x: width - 1, caret_y: height - 1}
	a.surface_dirty = true
	a.status_key = 'preview.status.selection'
}

// Pointer coordinates use the application's body. The viewport is centered
// when capped at 2048, independently of the image's fit/zoom/pan geometry.
fn (a &PreviewApp) selection_pixel(x int, y int, body_width int, body_height int,
	clamp bool) (int, int, bool) {
	geometry := a.geometry()
	width, height := a.oriented_dimensions()
	if geometry.width <= 0 || geometry.height <= 0 || width <= 0 || height <= 0 {
		return 0, 0, false
	}
	available_height := body_height - preview_toolbar_height - preview_status_height
	local_x := i64(x) - (body_width - a.viewport_width) / 2
	local_y := i64(y) - preview_toolbar_height - (available_height - a.viewport_height) / 2
	inside := local_x >= 0 && local_y >= 0 && local_x < a.viewport_width
		&& local_y < a.viewport_height && local_x >= geometry.left && local_y >= geometry.top
		&& local_x < geometry.left + geometry.width && local_y < geometry.top + geometry.height
	if !clamp && !inside { return 0, 0, false }
	// Wide intermediate values also bound an out-of-window drag delivered by IPC.
	raw_x := (local_x - geometry.left) * width / geometry.width
	raw_y := (local_y - geometry.top) * height / geometry.height
	return if raw_x < 0 { 0 } else if raw_x >= width { width - 1 } else { int(raw_x) },
		if raw_y < 0 { 0 } else if raw_y >= height { height - 1 } else { int(raw_y) }, true
}

fn (mut a PreviewApp) start_selection(x int, y int, width int, height int) {
	a.reset_selection()
	pixel_x, pixel_y, inside := a.selection_pixel(x, y, width, height, false)
	if !inside {
		a.status_key = 'preview.status.select'
		return
	}
	a.selection = PreviewSelection{
		active: true
		dragging: true
		anchor_x: pixel_x
		anchor_y: pixel_y
		caret_x: pixel_x
		caret_y: pixel_y
	}
	a.surface_dirty = true
	a.status_key = 'preview.status.selection'
}

fn (mut a PreviewApp) update_selection(x int, y int, width int, height int) {
	if !a.selection.dragging { return }
	pixel_x, pixel_y, valid := a.selection_pixel(x, y, width, height, true)
	if valid && (pixel_x != a.selection.caret_x || pixel_y != a.selection.caret_y) {
		a.selection.caret_x = pixel_x
		a.selection.caret_y = pixel_y
		a.surface_dirty = true
	}
}

fn preview_allocate_crop(length usize) &u8 {
	pixels := &u8(C.malloc(length))
	$if track_heap ? { C.vheap_alloc(pixels, u64(length)) }
	return pixels
}

fn preview_release_pixel_buffer(pixels &u8, pixels_from_crop bool) {
	if pixels == unsafe { nil } { return }
	if pixels_from_crop {
		$if track_heap ? { C.vheap_free(pixels) }
	}
	C.stbi_image_free(pixels)
}

fn (mut a PreviewApp) release_pixels() {
	preview_release_pixel_buffer(a.pixels, a.pixels_from_crop)
	a.pixels = unsafe { nil }
	a.pixels_from_crop = false
}

fn (mut a PreviewApp) apply_crop() bool {
	return a.apply_crop_using(preview_allocate_crop)
}

fn (mut a PreviewApp) apply_crop_using(allocate fn (usize) &u8) bool {
	rect := a.crop_rect()
	if !a.crop_rect_valid(rect) {
		a.status_key = 'preview.status.selection_empty'
		return false
	}
	// The bounded dimensions guarantee at most 32 MiB and no multiplication
// overflow. A failed allocation preserves pixels, selection and source bytes.
	length := usize(rect.width * rect.height * 4)
	pixels := allocate(length)
	if pixels == unsafe { nil } {
		a.status_key = 'preview.status.crop_failed'
		return false
	}
	for y in 0 .. rect.height {
		for x in 0 .. rect.width {
			input := a.pixel_offset(rect.left + x, rect.top + y)
			output := (y * rect.width + x) * 4
			for channel in 0 .. 4 {
				unsafe { pixels[output + channel] = a.pixels[input + channel] }
			}
		}
	}
	// Commit only after the new crop is complete. A second crop drops the old
	// alternate buffer and retains the active image for one Undo. At rest there
	// are at most two 32 MiB pixel buffers, plus the unchanged source bytes.
	a.release_crop_history()
	a.crop_history = a.crop_state()
	a.pixels = pixels
	a.pixels_from_crop = true
	a.width = rect.width
	a.height = rect.height
	a.orientation = 1
	a.rotation = 0
	a.reset_selection()
	a.fit = true
	a.zoom = 100
	a.pan_x = 0
	a.pan_y = 0
	a.surface_dirty = true
	a.refresh_details()
	a.status_key = 'preview.status.cropped'
	return true
}
