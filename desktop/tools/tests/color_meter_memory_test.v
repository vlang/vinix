// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

#include "@VMODROOT/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn test_color_meter_sample_codecs_text_and_request_dispatch_retain_zero_bytes() {
	mut desktop := Desktop{ canvas: new_scaled_canvas(5, 5, 10, 10, 2) }
	defer { unsafe { free(desktop.canvas.pixels) desktop.native_asset_icons.free() } }
	desktop.canvas.clear(0x123456)
	mut receiver := &ColorMeterApp{}
	mut native := NativeApp(receiver)
	defer { receiver.close_app() unsafe { free(receiver) } }
	C.vinix_heap_begin()
	for index in 0 .. 200 {
		receiver.handle('color_meter.live')!
		bytes := native_app_desktop_service_request(mut native)
		request := color_meter_decode_request(unsafe { tos(bytes.data, bytes.len) })?
		report := color_meter_sample(&desktop, ColorMeterRequest{ ...request, aperture: [1, 3, 5, 9]![index % 4] })
		payload := color_meter_encode_report(report)
		native_app_receive_desktop_service(mut native, unsafe { tos(payload.data, payload.len) })
		assert receiver.hex_text == '#123456'
		unsafe { bytes.free() payload.free() }
		quiet := native_app_desktop_service_request(mut native)
		assert quiet.len == 0
		if quiet.cap > 0 { unsafe { quiet.free() } }
	}
	receiver.close_app()
	assert C.vinix_heap_end() == 0
}

fn test_color_meter_frames_mode_edit_resize_and_complete_lifetimes_retain_zero_bytes() {
	mut desktop := Desktop{ canvas: new_canvas(10, 10) }
	defer { unsafe { free(desktop.canvas.pixels) desktop.native_asset_icons.free() } }
	desktop.canvas.clear(0xabcdef)
	mut warm := &ColorMeterApp{}
	for size in [ui2.rect(0, 0, 620, 516), ui2.rect(0, 0, 584, 506),
		ui2.rect(0, 0, 400, 300), ui2.rect(0, 0, 180, 96)]! {
		begin_frame_elements()
		tree := warm.build(size)!
		free_tree(tree)
	}
	warm.close_app()
	unsafe { free(warm) }
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut app := &ColorMeterApp{}
		app.handle('color_meter.x')!
		app.paste_input('4')
		app.key_input('\t4')
		app.handle('color_meter.sample')!
		request := app.take_desktop_service_request()
		payload := color_meter_encode_report(color_meter_sample(&desktop, request))
		app.receive_desktop_service_reply(unsafe { tos(payload.data, payload.len) })
		unsafe { payload.free() }
		app.handle('color_meter.lock_x')!
		app.handle('color_meter.lock_y')!
		for size in [ui2.rect(0, 0, 620, 516), ui2.rect(0, 0, 584, 506),
			ui2.rect(0, 0, 400, 300), ui2.rect(0, 0, 180, 96)]! {
			begin_frame_elements()
			tree := app.build(size)!
			free_tree(tree)
		}
		app.handle('color_meter.live')!
		assert !app.poll()
		app.handle('color_meter.copy_rgb')!
		app.close_app()
		app.close_app()
		unsafe { free(app) }
	}
	assert C.vinix_heap_end() == 0
}

fn test_color_meter_actual_parent_services_release_transport_and_clipboard_allocations() {
	mut requests := [2]i32{}
	mut responses := [2]i32{}
	assert C.pipe(&requests[0]) == 0 && C.pipe(&responses[0]) == 0
	defer { for fd in [requests[0], requests[1], responses[0], responses[1]]! { desktop_close(fd) } }
	mut desktop := Desktop{ canvas: new_canvas(10, 10), clipboard: HostClipboard{ configured: true } }
	defer { unsafe { free(desktop.canvas.pixels) desktop.native_asset_icons.free() } }
	desktop.canvas.clear(0xabcdef)
	mut remote := RemoteApp{
		desktop: unsafe { &desktop }
		request_fd: requests[1]
		response_fd: responses[0]
		peer_features: app_feature_desktop_services
		desktop_services: true
	}
	C.vinix_heap_begin()
	for index in 0 .. 200 {
		for command in [ColorMeterCommand.sample, .pointer, .pointer_lock_x, .pointer_lock_y,
			.pointer_lock_xy, .copy_hex, .copy_rgb]! {
			request := color_meter_encode_request(ColorMeterRequest{ sequence: u32(index), command: command, x: 5, y: 6 })
			assert send_app_response(responses[1], true, app_current_state(&desktop), []u8{})
			remote.handle_desktop_service(unsafe { tos(request.data, request.len) })
			unsafe { request.free() }
			operation, _, _, _, payload := receive_app_request(requests[0])!
			assert operation == .desktop_service_reply
			report := color_meter_decode_report(payload)?
			assert report.count == 1
			if command == .pointer_lock_x { assert report.x == 5 && report.y == 0 }
			if command == .pointer_lock_y { assert report.x == 0 && report.y == 6 }
			if command == .pointer_lock_xy { assert report.x == 5 && report.y == 6 }
			unsafe { payload.free() }
		}
	}
	assert desktop.clipboard.local_available
	assert C.vinix_heap_end() == 0
}

fn test_color_meter_independent_lock_unlock_freeze_stale_replies_and_live_resampling_retain_zero_bytes() {
	mut desktop := Desktop{ canvas: new_scaled_canvas(5, 5, 10, 10, 2), pointer_x: 2, pointer_y: 3 }
	defer { unsafe { free(desktop.canvas.pixels) desktop.native_asset_icons.free() } }
	desktop.canvas.clear(0x3579bd)
	mut receiver := &ColorMeterApp{}
	mut native := NativeApp(receiver)
	defer { receiver.close_app() unsafe { free(receiver) } }
	C.vinix_heap_begin()
	for _ in 0 .. 200 {
		receiver.handle('color_meter.live')!
		for action in ['color_meter.lock_x', 'color_meter.lock_y', 'color_meter.aperture.5',
			'color_meter.lock_x', 'color_meter.lock_y']! {
			bytes := native_app_desktop_service_request(mut native)
			request := color_meter_decode_request(unsafe { tos(bytes.data, bytes.len) })?
			payload := color_meter_encode_report(color_meter_sample(&desktop, request))
			native_app_receive_desktop_service(mut native, unsafe { tos(payload.data, payload.len) })
			assert receiver.hex_text == '#3579BD'
			unsafe { bytes.free() payload.free() }
			receiver.handle(action)!
		}
		receiver.take_desktop_service_request()
		receiver.waiting_since = desktop_monotonic_ms() - color_meter_live_reply_timeout_ms
		assert receiver.poll() && receiver.status == 'color_meter.live_unavailable'
		receiver.freeze()
		stale := color_meter_encode_report(ColorMeterReport{ sequence: receiver.sequence - 1, status: .unavailable })
		native_app_receive_desktop_service(mut native, unsafe { tos(stale.data, stale.len) })
		assert receiver.status == 'color_meter.frozen'
		unsafe { stale.free() }
		receiver.close_app()
	}
	assert C.vinix_heap_end() == 0
}
