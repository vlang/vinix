// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2
import os

#include "@VMODROOT/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn test_capture_cursor_pixel_sampling_and_png_encoding_release_every_frame() {
	mut canvas := new_canvas(4, 3)
	defer { unsafe { free(canvas.pixels) } }
	canvas.clear(0xffffff)
	backing := CursorBacking{box: DamageRect{x: 1, y: 1, w: 2, h: 1, valid: true}, pixels: [u32(0x456789), 0x102030]}
	defer { unsafe { backing.pixels.free() } }
	for count in [100, 200]! {
		C.vinix_heap_begin()
		for _ in 0 .. count {
			assert capture_pixel(&canvas, &backing, 1, 1) == 0x456789
			bytes := capture_png_bytes_with_backing(&canvas, &backing)!
			unsafe { bytes.free() }
		}
		live := C.vinix_heap_end()
		assert live == 0, 'Capture PNG retained ${live} bytes for ${count} frames'
	}
}

fn test_capture_cursor_ui_and_protocol_requests_retain_no_memory() {
	defer { app_compositor_features = app_features }
	mut desktop := Desktop{}
	mut app := CaptureApp{ desktop: &desktop }
	mut pair := [2]i32{}
	assert C.pipe(&pair[0]) == 0
	defer { desktop_close(pair[0]); desktop_close(pair[1]) }
	for page in [CapturePage.screenshot, .video]! {
		app.page = page
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 560, 396))!)
	}
	for count in [100, 200]! {
		C.vinix_heap_begin()
		for index in 0 .. count {
			app.page = if index % 2 == 0 { CapturePage.screenshot } else { CapturePage.video }
			app.handle(capture_action_cursor)!
			app.request(.screenshot)
			assert send_app_request(pair[1], .build, 560, 396, app_current_state(&desktop), '')
			_, _, _, state, payload := receive_app_request(pair[0])!
			assert state.capture_request.hide_cursor == app.hide_cursor
			free_app_payload(payload)
			begin_frame_elements()
			tree := app.build(ui2.rect(0, 0, 560, 396))!
			free_tree(tree)
		}
		live := C.vinix_heap_end()
		assert live == 0, 'Capture UI/protocol retained ${live} bytes for ${count} frames'
	}
}

fn test_capture_long_recording_releases_grown_index_and_frame_buffers() {
	path := os.join_path(os.temp_dir(), 'vinix-capture-memory.avi')
	defer { os.rm(path) or {}; unsafe { path.free() } }
	mut canvas := new_canvas(4, 2)
	defer { unsafe { free(canvas.pixels) } }
	canvas.clear(0x123456)
	backing := CursorBacking{box: DamageRect{x: 0, y: 0, w: 1, h: 1, valid: true}, pixels: [u32(0xabcdef)]}
	defer { unsafe { backing.pixels.free() } }
	for count in [1100, 2200]! {
		C.vinix_heap_begin()
		mut writer := capture_open_avi(path, &canvas, 10)!
		for _ in 0 .. count { assert writer.add_frame_with_backing(&canvas, &backing) }
		assert writer.finish()
		live := C.vinix_heap_end()
		assert live == 0, 'Capture AVI retained ${live} bytes after ${count} frames'
	}
}
