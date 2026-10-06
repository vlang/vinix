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

fn color_meter_test_reply(mut app ColorMeterApp, desktop &Desktop) ColorMeterReport {
	report := color_meter_sample(desktop, app.take_desktop_service_request())
	bytes := color_meter_encode_report(report)
	app.receive_desktop_service_reply(unsafe { tos(bytes.data, bytes.len) })
	unsafe { bytes.free() }
	return report
}

fn test_color_meter_live_locks_resolve_each_unlocked_axis_from_physical_pointer_and_cursor_backing() {
	mut desktop := Desktop{ canvas: new_scaled_canvas(5, 5, 10, 10, 2), pointer_x: 2, pointer_y: 3 }
	defer { unsafe { free(desktop.canvas.pixels) desktop.cursor_backing.pixels.free() desktop.native_asset_icons.free() } }
	for y in 0 .. 10 {
		for x in 0 .. 10 { unsafe { desktop.canvas.pixels[y * 10 + x] = u32(y * 10 + x) } }
	}
	x := color_meter_sample(&desktop, ColorMeterRequest{ command: .pointer_lock_x, x: 1, y: 100 })
	assert x.x == 1 && x.y == 7 && x.rgb == 71
	y := color_meter_sample(&desktop, ColorMeterRequest{ command: .pointer_lock_y, x: 100, y: 2 })
	assert y.x == 5 && y.y == 2 && y.rgb == 25
	both := color_meter_sample(&desktop, ColorMeterRequest{ command: .pointer_lock_xy, x: 9, y: 0, aperture: 3 })
	assert both.x == 9 && both.y == 0 && both.count == 4 && both.rgb == 14
	desktop.cursor_backing.box = DamageRect{ x: 0, y: 3, w: 1, h: 1, valid: true }
	desktop.cursor_backing.pixels = []u32{len: 4, init: 0x2468ac}
	unsafe { desktop.canvas.pixels[7 * 10 + 1] = 0xffffff }
	saved := color_meter_sample(&desktop, ColorMeterRequest{ command: .pointer_lock_x, x: 1 })
	assert saved.x == 1 && saved.y == 7 && saved.rgb == 0x2468ac
	desktop.pointer_x = 4
	desktop.pointer_y = 1
	moved := color_meter_sample(&desktop, ColorMeterRequest{ command: .pointer_lock_x, x: 1 })
	assert moved.x == 1 && moved.y == 3 && moved.rgb == 31
}

fn test_color_meter_lock_commands_append_without_changing_existing_wire_values_and_sizes() {
	assert int(ColorMeterCommand.sample) == 1 && int(ColorMeterCommand.pointer) == 2
	assert int(ColorMeterCommand.copy_hex) == 3 && int(ColorMeterCommand.copy_rgb) == 4
	assert color_meter_request_size == 24 && color_meter_report_size == 441
	for command in [ColorMeterCommand.sample, .pointer, .copy_hex, .copy_rgb,
		.pointer_lock_x, .pointer_lock_y, .pointer_lock_xy]! {
		request := ColorMeterRequest{ sequence: 17, command: command, x: 3, y: 7, aperture: 9 }
		mut bytes := color_meter_encode_request(request)
		assert bytes.len == 24
		assert color_meter_decode_request(unsafe { tos(bytes.data, bytes.len) })? == request
		bytes[8] = 8
		assert color_meter_decode_request(unsafe { tos(bytes.data, bytes.len) }) == none
		unsafe { bytes.free() }
	}
}

fn test_color_meter_independent_locks_capture_report_and_preserve_freeze_copy_manual_sample_and_aperture() {
	mut desktop := Desktop{ canvas: new_scaled_canvas(5, 5, 10, 10, 2), pointer_x: 2, pointer_y: 3 }
	defer { unsafe { free(desktop.canvas.pixels) desktop.native_asset_icons.free() } }
	desktop.canvas.clear(0x123456)
	mut app := &ColorMeterApp{}
	defer { app.close_app() unsafe { free(app) } }
	app.handle('color_meter.lock_x')!
	assert !app.locked_x && app.status == 'color_meter.lock_requires_sample'
	assert app.take_desktop_service_request().command == .none_
	app.handle('color_meter.live')!
	assert color_meter_test_reply(mut app, &desktop).x == 5
	app.handle('color_meter.lock_x')!
	assert app.following && app.locked_x && !app.locked_y && app.lock_x == 5
	desktop.pointer_x = 4
	desktop.pointer_y = 1
	x := color_meter_test_reply(mut app, &desktop)
	assert x.x == 5 && x.y == 3
	app.handle('color_meter.lock_y')!
	assert app.locked_y && app.lock_y == 3
	desktop.pointer_x = 0
	desktop.pointer_y = 4
	assert color_meter_test_reply(mut app, &desktop).y == 3
	app.handle('color_meter.aperture.9')!
	both := color_meter_test_reply(mut app, &desktop)
	assert both.x == 5 && both.y == 3 && both.aperture == 9 && both.count == 72
	app.handle('color_meter.freeze')!
	assert !app.following && app.locked_x && app.locked_y
	assert editor_bytes_text(app.x_input) == '5' && editor_bytes_text(app.y_input) == '3'
	app.handle('color_meter.copy_rgb')!
	assert app.take_desktop_service_request().command == .copy_rgb && !app.following
	app.handle('color_meter.x')!
	app.paste_input('0')
	app.handle('color_meter.y')!
	app.paste_input('9')
	app.handle('color_meter.sample')!
	manual := color_meter_test_reply(mut app, &desktop)
	assert manual.x == 0 && manual.y == 9 && app.lock_x == 5 && app.lock_y == 3
	app.handle('color_meter.live')!
	assert app.take_desktop_service_request().command == .pointer_lock_xy
	app.handle('color_meter.lock_x')!
	assert app.take_desktop_service_request().command == .pointer_lock_y
	assert !app.locked_x && app.locked_y
	app.handle('color_meter.lock_y')!
	assert app.take_desktop_service_request().command == .pointer
	assert !app.locked_x && !app.locked_y && app.following
	app.close_app()
	assert !app.locked_x && !app.locked_y && app.lock_x == 0 && app.lock_y == 0
}

fn test_color_meter_freeze_lock_changes_and_invalid_manual_input_invalidate_pending_replies() {
	mut desktop := Desktop{ canvas: new_canvas(10, 10), pointer_x: 4, pointer_y: 5 }
	defer { unsafe { free(desktop.canvas.pixels) desktop.native_asset_icons.free() } }
	desktop.canvas.clear(0xabcdef)
	mut app := &ColorMeterApp{}
	defer { app.close_app() unsafe { free(app) } }
	app.handle('color_meter.live')!
	color_meter_test_reply(mut app, &desktop)
	app.poll()
	mut stale := color_meter_encode_report(color_meter_sample(&desktop, app.take_desktop_service_request()))
	defer { unsafe { stale.free() } }
	app.handle('color_meter.freeze')!
	app.receive_desktop_service_reply(unsafe { tos(stale.data, stale.len) })
	assert app.status == 'color_meter.frozen' && app.hex_text == '#ABCDEF'
	stale[4] = 255
	app.receive_desktop_service_reply(unsafe { tos(stale.data, stale.len) })
	assert app.status == 'color_meter.frozen'
	app.handle('color_meter.live')!
	old := app.take_desktop_service_request()
	app.handle('color_meter.lock_x')!
	lock_sequence := app.sequence
	bytes := color_meter_encode_report(ColorMeterReport{ sequence: old.sequence, status: .unavailable })
	app.receive_desktop_service_reply(unsafe { tos(bytes.data, bytes.len) })
	unsafe { bytes.free() }
	assert app.sequence == lock_sequence && app.lock_x == 4 && app.hex_text == '#ABCDEF'
	app.handle('color_meter.x')!
	app.paste_input('32768')
	app.handle('color_meter.sample')!
	assert app.sequence > lock_sequence && app.take_desktop_service_request().command == .none_
	assert app.status == 'color_meter.invalid_input'
	app.receive_desktop_service_reply(unsafe { tos(stale.data, stale.len) })
	assert app.status == 'color_meter.invalid_input'
}

fn test_color_meter_locked_bounds_and_unavailable_canvas_return_errors_without_clamping() {
	mut desktop := Desktop{ canvas: new_scaled_canvas(5, 5, 10, 10, 2), pointer_x: 3, pointer_y: 2 }
	defer { unsafe { free(desktop.canvas.pixels) desktop.native_asset_icons.free() } }
	desktop.canvas.clear(0x123456)
	for coordinate in [-1, 10, 2147483647]! {
		x := color_meter_sample(&desktop, ColorMeterRequest{ command: .pointer_lock_x, x: coordinate })
		y := color_meter_sample(&desktop, ColorMeterRequest{ command: .pointer_lock_y, y: coordinate })
		assert x.status == .invalid && y.status == .invalid && x.count == 0 && y.count == 0
	}
	desktop.pointer_x = 2147483647
	assert color_meter_sample(&desktop, ColorMeterRequest{ command: .pointer_lock_y, y: 0 }).status == .invalid
	assert color_meter_sample(&desktop, ColorMeterRequest{ command: .pointer_lock_xy, x: 0, y: 0 }).count == 1
	desktop.pointer_x = int(~u64(0) >> 1)
	assert color_meter_sample(&desktop, ColorMeterRequest{ command: .pointer_lock_y, y: 0 }).status == .invalid
	desktop.canvas.scale = 2147483647
	assert color_meter_sample(&desktop, ColorMeterRequest{ command: .pointer }).status == .unavailable
	desktop.canvas.scale = 0
	assert color_meter_sample(&desktop, ColorMeterRequest{ command: .pointer_lock_xy }).status == .unavailable
	desktop.canvas.scale = 2
	pixels := desktop.canvas.pixels
	desktop.canvas.pixels = unsafe { nil }
	assert color_meter_sample(&desktop, ColorMeterRequest{ command: .pointer_lock_x }).status == .unavailable
	desktop.canvas.pixels = pixels
	mut app := &ColorMeterApp{}
	defer { app.close_app() unsafe { free(app) } }
	app.handle('color_meter.sample')!
	color_meter_test_reply(mut app, &desktop)
	app.handle('color_meter.lock_x')!
	assert app.locked_x
	app.handle('color_meter.live')!
	desktop.canvas.physical_width = 0
	color_meter_test_reply(mut app, &desktop)
	assert app.status == 'color_meter.unavailable' && app.report.count == 0 && app.hex_text == ''
	app.handle('color_meter.lock_y')!
	assert !app.locked_y && app.status == 'color_meter.lock_requires_sample'
	app.handle('color_meter.lock_x')!
	assert !app.locked_x && app.following
}

fn test_color_meter_lock_controls_fit_default_minimum_and_tiny_resize_layouts() {
	mut app := &ColorMeterApp{}
	defer { app.close_app() unsafe { free(app) } }
	for size in [ui2.rect(0, 0, 620, 516), ui2.rect(0, 0, 584, 506),
		ui2.rect(0, 0, 400, 300), ui2.rect(0, 0, 180, 96)]! {
		begin_frame_elements()
		tree := app.build(size)!
		assert color_test_has_text(tree, if size.width >= 584 && size.height >= 506 { tr('color_meter.lock_x') } else { tr('color_meter.resize') })
		for child in tree.children {
			assert child.frame.x >= 0 && child.frame.y >= 0
			assert child.frame.width >= 0 && child.frame.height >= 0
			assert child.frame.x + child.frame.width <= size.width
			assert child.frame.y + child.frame.height <= size.height
		}
		free_tree(tree)
	}
}

fn test_color_meter_missing_live_service_reply_times_out_without_replacing_sample_and_rebases_clock_rollback() {
	mut desktop := Desktop{ canvas: new_canvas(10, 10), pointer_x: 4, pointer_y: 5 }
	defer { unsafe { free(desktop.canvas.pixels) desktop.native_asset_icons.free() } }
	desktop.canvas.clear(0x123456)
	mut app := &ColorMeterApp{}
	defer { app.close_app() unsafe { free(app) } }
	app.handle('color_meter.live')!
	color_meter_test_reply(mut app, &desktop)
	app.handle('color_meter.lock_x')!
	request := app.take_desktop_service_request()
	assert request.command == .pointer_lock_x && app.waiting
	sequence := app.sequence
	assert !app.poll() && app.sequence == sequence
	assert app.take_desktop_service_request().command == .none_
	start := app.waiting_since
	assert !app.live_reply_expired(~u64(0)) && app.waiting_since == start
	app.waiting_since = ~u64(0)
	assert !app.live_reply_expired(10) && app.waiting_since == 10
	assert !app.live_reply_expired(1009)
	assert app.live_reply_expired(1010)
	app.waiting_since = desktop_monotonic_ms() + 1000
	assert !app.poll() && app.following && app.waiting && app.sequence == sequence
	assert app.waiting_since <= desktop_monotonic_ms()
	assert app.report.rgb == 0x123456 && app.lock_x == 4
	// A matching successful reply ends waiting, so an old timestamp cannot
	// time out an already completed service operation.
	bytes := color_meter_encode_report(color_meter_sample(&desktop, request))
	app.receive_desktop_service_reply(unsafe { tos(bytes.data, bytes.len) })
	unsafe { bytes.free() }
	assert !app.waiting && app.following
	app.waiting_since = 0
	assert !app.poll() && app.sequence > sequence && app.following
	dropped := app.take_desktop_service_request()
	assert dropped.command == .pointer_lock_x && app.waiting
	app.waiting_since = desktop_monotonic_ms() - color_meter_live_reply_timeout_ms
	assert app.poll()
	assert !app.waiting && !app.following && app.status == 'color_meter.live_unavailable'
	assert app.report.rgb == 0x123456 && app.hex_text == '#123456' && app.locked_x
	assert editor_bytes_text(app.x_input) == '4' && editor_bytes_text(app.y_input) == '5'
	late := color_meter_encode_report(ColorMeterReport{ ...app.report, sequence: dropped.sequence, rgb: 0xffffff })
	app.receive_desktop_service_reply(unsafe { tos(late.data, late.len) })
	unsafe { late.free() }
	assert app.status == 'color_meter.live_unavailable' && app.hex_text == '#123456'
	app.handle('color_meter.copy_hex')!
	assert app.take_desktop_service_request().command == .copy_hex
	app.handle('color_meter.live')!
	assert app.take_desktop_service_request().command == .pointer_lock_x && app.waiting
	app.handle('color_meter.freeze')!
	assert !app.waiting && !app.poll()
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
