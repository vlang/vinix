// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn color_test_has_text(element ui2.Element, text string) bool {
	if element.text == text { return true }
	for child in element.children { if color_test_has_text(child, text) { return true } }
	return false
}

fn test_color_meter_samples_physical_pixels_masks_alpha_and_rounds_apertures() {
	mut desktop := Desktop{ canvas: new_scaled_canvas(5, 5, 10, 10, 2), pointer_x: 2, pointer_y: 3 }
	defer { unsafe { free(desktop.canvas.pixels) desktop.native_asset_icons.free() } }
	desktop.canvas.clear(0x102030)
	unsafe { desktop.canvas.pixels[7 * 10 + 5] = 0xaabbccdd }
	pointer := color_meter_sample(&desktop, ColorMeterRequest{ sequence: 7, command: .pointer })
	assert pointer.sequence == 7 && pointer.x == 5 && pointer.y == 7
	assert pointer.width == 10 && pointer.height == 10 && pointer.rgb == 0xbbccdd && pointer.count == 1
	unsafe {
		desktop.canvas.pixels[0] = 0
		desktop.canvas.pixels[1] = 0x010101
		desktop.canvas.pixels[10] = 0x020202
		desktop.canvas.pixels[11] = 0x030303
	}
	edge := color_meter_sample(&desktop, ColorMeterRequest{ command: .sample, aperture: 3 })
	assert edge.count == 4 && edge.rgb == 0x020202
	assert !edge.valid[0] && edge.valid[40] && edge.grid[40] == 0
	assert edge.valid[41] && edge.grid[41] == 0x010101
	for aperture in [1, 3, 5, 9]! {
		report := color_meter_sample(&desktop, ColorMeterRequest{ command: .sample, x: 4, y: 4, aperture: aperture })
		assert report.count == aperture * aperture
	}
}

fn test_color_meter_uses_saved_pixels_under_hidpi_cursor() {
	mut desktop := Desktop{ canvas: new_scaled_canvas(5, 5, 10, 10, 2) }
	defer { unsafe { free(desktop.canvas.pixels) desktop.cursor_backing.pixels.free() desktop.native_asset_icons.free() } }
	desktop.canvas.clear(0xffffff)
	desktop.cursor_backing.box = DamageRect{ x: 1, y: 1, w: 2, h: 2, valid: true }
	desktop.cursor_backing.pixels = []u32{len: 16, init: 0x123456}
	report := color_meter_sample(&desktop, ColorMeterRequest{ command: .sample, x: 3, y: 3 })
	assert report.rgb == 0x123456 && report.grid[40] == 0x123456
	outside := color_meter_sample(&desktop, ColorMeterRequest{ command: .sample, x: 7, y: 7 })
	assert outside.rgb == 0xffffff
}

fn test_color_meter_unavailable_and_outside_coordinates_never_fabricate_samples() {
	mut desktop := Desktop{}
	defer { unsafe { desktop.native_asset_icons.free() } }
	assert color_meter_sample(&desktop, ColorMeterRequest{ command: .pointer }).status == .unavailable
	desktop.canvas = new_canvas(10, 10)
	defer { unsafe { free(desktop.canvas.pixels) } }
	for coordinate in [-1, 10, 2147483647]! {
		report := color_meter_sample(&desktop, ColorMeterRequest{ command: .sample, x: coordinate })
		assert report.status == .invalid && report.count == 0
	}
	assert color_meter_sample(&desktop, ColorMeterRequest{ command: .sample, aperture: 2 }).status == .invalid
}

fn test_color_meter_bounded_request_and_report_codecs_reject_malformed_data() {
	request := ColorMeterRequest{ sequence: 91, command: .sample, x: 3, y: 4, aperture: 5 }
	mut bytes := color_meter_encode_request(request)
	defer { unsafe { bytes.free() } }
	assert bytes.len == color_meter_request_size
	assert color_meter_decode_request(unsafe { tos(bytes.data, bytes.len) })? == request
	assert color_meter_decode_request('short') == none
	bytes[8] = 255
	assert color_meter_decode_request(unsafe { tos(bytes.data, bytes.len) }) == none
	bytes[8] = 1
	bytes[20] = 2
	assert color_meter_decode_request(unsafe { tos(bytes.data, bytes.len) }) == none
	mut desktop := Desktop{ canvas: new_canvas(10, 10) }
	defer { unsafe { free(desktop.canvas.pixels) desktop.native_asset_icons.free() } }
	desktop.canvas.clear(0xabcdef)
	report := color_meter_sample(&desktop, request)
	mut encoded := color_meter_encode_report(report)
	defer { unsafe { encoded.free() } }
	assert encoded.len == color_meter_report_size
	assert color_meter_decode_report(unsafe { tos(encoded.data, encoded.len) })? == report
	assert color_meter_decode_report('short') == none
	encoded[40] = 2
	assert color_meter_decode_report(unsafe { tos(encoded.data, encoded.len) }) == none
	encoded[40] = 1
	encoded[31] = 255
	assert color_meter_decode_report(unsafe { tos(encoded.data, encoded.len) }) == none
}

fn test_color_meter_coordinates_selection_and_paste_are_decimal_only() {
	mut app := &ColorMeterApp{}
	defer { app.close_app() unsafe { free(app) } }
	app.handle('color_meter.x')!
	app.paste_input('32767')
	app.key_input('\t42')
	app.handle('color_meter.sample')!
	request := app.take_desktop_service_request()
	assert request.command == .sample && request.x == 32767 && request.y == 42
	assert app.take_desktop_service_request().command == .none_
	app.handle('color_meter.x')!
	app.paste_input('32768')
	app.handle('color_meter.sample')!
	assert app.take_desktop_service_request().command == .none_
	assert app.status == 'color_meter.invalid_input'
	app.paste_input('3\n4')
	assert editor_bytes_text(app.x_input) == '32768'
	app.key_input('\x01\x7f')
	app.handle('color_meter.sample')!
	assert app.status == 'color_meter.invalid_input'
}

fn test_color_meter_live_poll_freeze_and_copy_preserve_last_successful_sample() {
	mut desktop := Desktop{ canvas: new_canvas(10, 10), pointer_x: 5, pointer_y: 4 }
	defer { unsafe { free(desktop.canvas.pixels) desktop.native_asset_icons.free() } }
	desktop.canvas.clear(0x1278ef)
	mut app := &ColorMeterApp{}
	defer { app.close_app() unsafe { free(app) } }
	app.handle('color_meter.live')!
	assert app.following && app.next_poll_ms() == 100
	request := app.take_desktop_service_request()
	report := color_meter_sample(&desktop, request)
	encoded := color_meter_encode_report(report)
	app.receive_desktop_service_reply(unsafe { tos(encoded.data, encoded.len) })
	unsafe { encoded.free() }
	assert app.hex_text == '#1278EF' && app.rgb_text == 'rgb(18, 120, 239)'
	assert !app.poll() && app.take_desktop_service_request().command == .pointer
	app.key_input(' ')
	assert !app.following && app.next_poll_ms() == 1000 && app.report.rgb == 0x1278ef
	assert editor_bytes_text(app.x_input) == '5' && editor_bytes_text(app.y_input) == '4'
	assert !app.poll() && app.take_desktop_service_request().command == .none_
	app.key_input('\x03')
	assert app.take_desktop_service_request().command == .copy_hex
	app.handle('color_meter.aperture.9')!
	resampled := app.take_desktop_service_request()
	assert app.aperture == 9 && resampled.aperture == 9
	assert resampled.x == 5 && resampled.y == 4
}

fn test_color_meter_report_sequences_ignore_stale_samples_and_small_windows_explain_resize() {
	mut app := &ColorMeterApp{}
	defer { app.close_app() unsafe { free(app) } }
	app.handle('color_meter.sample')!
	bytes := color_meter_encode_report(ColorMeterReport{ sequence: 0, status: .unavailable })
	app.receive_desktop_service_reply(unsafe { tos(bytes.data, bytes.len) })
	unsafe { bytes.free() }
	assert app.status == 'color_meter.ready'
	begin_frame_elements()
	small := app.build(ui2.rect(0, 0, 400, 300))!
	assert color_test_has_text(small, tr('color_meter.resize'))
	free_tree(small)
	begin_frame_elements()
	full := app.build(ui2.rect(0, 0, 620, 516))!
	assert color_test_has_text(full, tr('color_meter.copy_rgb'))
	assert color_test_has_text(full, '9 x 9')
	free_tree(full)
}

struct ColorPasteTestReceiver {
mut:
	last string
	calls int
}
fn (mut _ ColorPasteTestReceiver) build(_ ui2.Rect) !ui2.Element { return ui2.Element{} }
fn (mut _ ColorPasteTestReceiver) handle(_ string) ! {}
fn (mut _ ColorPasteTestReceiver) key_input(_ string) {}
fn (mut receiver ColorPasteTestReceiver) paste_input(text string) { receiver.last = text receiver.calls++ }

fn test_color_meter_session_clipboard_pastes_native_text_and_keeps_host_override_explicit() {
	mut receiver := &ColorPasteTestReceiver{}
	mut desktop := Desktop{ focus: 71, clipboard: HostClipboard{ configured: true } }
	defer { unsafe { desktop.apps.free() desktop.windows.free() desktop.native_asset_icons.free() free(receiver) } }
	desktop.apps << receiver
	desktop.windows << Window{ id: 71, page: .app, app_index: 0, factory_index: 37 }
	assert desktop.clipboard.set_local_text('#AABBCC')
	for chord in ['\x16', key_cmd_v, key_shift_insert]! {
		remaining := desktop.take_paste_keys(chord)
		assert remaining.len == 0
		unsafe { remaining.free() }
		assert receiver.last == '#AABBCC'
	}
	assert receiver.calls == 3
	remaining := desktop.take_paste_keys(key_ctrl_shift_v)
	assert remaining.len == 0 && receiver.calls == 3
	unsafe { remaining.free() }
	assert !desktop.clipboard.set_local_text('')
	long := 'x'.repeat(clipboard_max_bytes + 1)
	assert !desktop.clipboard.set_local_text(long)
	unsafe { long.free() }
	assert desktop.clipboard.local_length == 7
}
