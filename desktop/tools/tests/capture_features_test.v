// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2
import os

fn capture_feature_has_action(tree ui2.Element, action string) bool {
	if tree.id == action || tree.action_id == action { return true }
	for child in tree.children {
		if capture_feature_has_action(child, action) { return true }
	}
	return false
}

fn test_capture_video_timer_and_keyboard_commands() {
	mut desktop := Desktop{}
	mut app := CaptureApp{ desktop: &desktop, page: .video }
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 560, 396))!
	assert capture_feature_has_action(tree, capture_action_delay_0)
	assert capture_feature_has_action(tree, capture_action_delay_3)
	assert capture_feature_has_action(tree, capture_action_delay_5)
	free_tree(tree)
	app.handle(capture_action_delay_5)!
	app.key_input('\r')
	assert desktop.capture.request.command == .start_video
	assert desktop.capture.request.delay == 5
	before := desktop.capture.request.sequence
	app.paste_input('\r\x1b')
	app.key_input('\x1b[3~')
	assert desktop.capture.request.sequence == before
	desktop.capture.report.phase = .recording
	app.key_input('\n')
	assert desktop.capture.request.command == .stop
	desktop.capture.report.phase = .screenshot_countdown
	app.key_input('\x1b')
	assert desktop.capture.request.command == .stop
}

fn test_capture_cursor_choice_preserves_default_and_freezes_active_request() {
	defer { app_compositor_features = app_features }
	mut desktop := Desktop{}
	mut app := CaptureApp{ desktop: &desktop }
	app.request(.screenshot)
	assert !desktop.capture.request.hide_cursor
	app.handle(capture_action_cursor)!
	assert app.hide_cursor
	app.request(.start_video)
	assert desktop.capture.request.hide_cursor
	for phase in [CapturePhase.screenshot_countdown, .video_countdown, .recording]! {
		desktop.capture.report.phase = phase
		app.handle(capture_action_cursor)!
		assert app.hide_cursor && desktop.capture.request.hide_cursor
	}
	desktop.capture.report.phase = .idle
	app_compositor_features = app_features & ~app_feature_capture_cursor
	app.handle(capture_action_cursor)!
	app.request(.screenshot)
	assert !desktop.capture.request.hide_cursor
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 560, 396))!
	assert !capture_feature_has_action(tree, capture_action_cursor)
	free_tree(tree)
}

fn test_capture_cursor_flag_crosses_both_protocol_headers() {
	defer { app_compositor_features = app_features }
	mut pair := [2]i32{}
	assert C.pipe(&pair[0]) == 0
	defer { desktop_close(pair[0]); desktop_close(pair[1]) }
	for hidden in [false, true]! {
		state := AppWireState{capture_request: CaptureRequest{
			sequence: 7, command: .screenshot, delay: 3, fps: 10, hide_cursor: hidden}}
		assert send_app_request(pair[1], .handle, 560, 396, state, capture_action_cursor)
		command, width, height, received, payload := receive_app_request(pair[0])!
		assert command == .handle && width == 560 && height == 396
		assert received.capture_request.hide_cursor == hidden
		assert received.capture_request.fps == 10 && payload == capture_action_cursor
		free_app_payload(payload)
		assert send_app_response(pair[1], true, state, []u8{})
		reply := receive_app_response(pair[0])!
		assert reply.ok && reply.state.capture_request.hide_cursor == hidden
		if reply.payload.cap > 0 { unsafe { reply.payload.free() } }
	}
}

fn test_capture_cursor_flags_refuse_unknown_and_unadvertised_bits() {
	defer { app_compositor_features = app_features }
	mut pair := [2]i32{}
	assert C.pipe(&pair[0]) == 0
	defer { desktop_close(pair[0]); desktop_close(pair[1]) }
	for flags in [u8(2), 128, 1]! {
		for response in [false, true]! {
			mut header := []u8{cap: app_request_header_size}
			wire_put_u32(mut header, app_protocol_magic)
			wire_put_u8(mut header, app_protocol_version)
			wire_put_u8(mut header, if response { 0 } else { u8(AppCommand.build) })
			wire_put_u8(mut header, if flags == 1 { app_features & ~app_feature_capture_cursor } else { app_features })
			wire_put_u8(mut header, flags)
			if !response { wire_put_i32(mut header, 560); wire_put_i32(mut header, 396) }
			wire_put_state(mut header, AppWireState{})
			wire_put_u32(mut header, 0)
			assert desktop_write_all(pair[1], header.data, u64(header.len))
			unsafe { header.free() }
			if response {
				if _ := receive_app_response(pair[0]) { assert false }
			} else {
				if _, _, _, _, _ := receive_app_request(pair[0]) { assert false }
			}
		}
	}
}

fn test_capture_cursor_free_png_uses_physical_backing_and_leaves_canvas_intact() {
	for scale in [1, 2]! {
		mut canvas := new_scaled_canvas(4, 3, 4 * scale, 3 * scale, scale)
		defer { unsafe { free(canvas.pixels) } }
		canvas.clear(0x102030)
		backing := CursorBacking{box: DamageRect{x: 1, y: 1, w: 2, h: 1, valid: true},
			pixels: []u32{len: 2 * scale * scale, init: u32(0x456789)}}
		defer { unsafe { backing.pixels.free() } }
		for y in scale .. 2 * scale {
			for x in scale .. 3 * scale { unsafe { canvas.pixels[y * canvas.stride + x] = 0xffffff } }
		}
		for hidden in [false, true]! {
			bytes := capture_png_bytes_with_backing(&canvas, if hidden { &backing } else { unsafe { nil } })!
			defer { unsafe { bytes.free() } }
			image := decode_png(bytes) or { panic('Invalid encoded PNG') }
			defer { unsafe { image.pixels.free() } }
			for y in 0 .. canvas.physical_height {
				for x in 0 .. canvas.physical_width {
					inside := x >= scale && x < 3 * scale && y >= scale && y < 2 * scale
					color := if inside { if hidden { u32(0x456789) } else { u32(0xffffff) } } else { u32(0x102030) }
					assert image.pixels[y * image.width + x] == 0xff000000 | color
					assert unsafe { canvas.pixels[y * canvas.stride + x] } == if inside { u32(0xffffff) } else { u32(0x102030) }
				}
			}
		}
	}
}

fn test_capture_cursor_free_avi_preserves_bottom_up_pixels_and_padding() {
	path := os.join_path(os.temp_dir(), 'vinix-cursor-free-avi-test.avi')
	defer { os.rm(path) or {}; unsafe { path.free() } }
	mut canvas := new_canvas(3, 2)
	defer { unsafe { free(canvas.pixels) } }
	canvas.clear(0x102030)
	unsafe { canvas.pixels[1] = 0xffffff }
	backing := CursorBacking{box: DamageRect{x: 1, y: 0, w: 1, h: 1, valid: true}, pixels: [u32(0x456789)]}
	defer { unsafe { backing.pixels.free() } }
	mut writer := capture_open_avi(path, &canvas, 10)!
	assert writer.add_frame_with_backing(&canvas, &backing)
	assert writer.frame[writer.row_stride + 3] == 0x89
	assert writer.frame[writer.row_stride + 4] == 0x67
	assert writer.frame[writer.row_stride + 5] == 0x45
	assert writer.frame[3] == 0x30 && writer.frame[4] == 0x20 && writer.frame[5] == 0x10
	assert writer.width == 2 && writer.row_stride == 8
	assert writer.frame[6] == 0 && writer.frame[7] == 0
	assert unsafe { canvas.pixels[1] } == 0xffffff
	assert writer.add_frame(&canvas)
	assert writer.frame[writer.row_stride + 3] == 0xff
	assert writer.finish()
}

fn test_capture_cursor_exclusion_refuses_stale_or_short_backing() {
	mut canvas := new_canvas(2, 2)
	defer { unsafe { free(canvas.pixels) } }
	mut backing := CursorBacking{}
	assert !capture_backing_valid(&canvas, &backing)
	backing.box = DamageRect{x: 1, y: 0, w: 2, h: 1, valid: true}
	assert !capture_backing_valid(&canvas, &backing)
	backing.box = DamageRect{x: 0, y: 0, w: 2, h: 1, valid: true}
	assert !capture_backing_valid(&canvas, &backing)
	if bytes := capture_png_bytes_with_backing(&canvas, &backing) { unsafe { bytes.free() }; assert false }
}
