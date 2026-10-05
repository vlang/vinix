// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

const color_meter_aperture_actions = ['color_meter.aperture.1', 'color_meter.aperture.3',
	'color_meter.aperture.5', 'color_meter.aperture.9']!
const color_meter_aperture_values = [1, 3, 5, 9]!
const color_meter_aperture_texts = ['1 x 1', '3 x 3', '5 x 5', '9 x 9']!

@[heap]
struct ColorMeterApp {
mut:
	initialized bool
	following bool
	focus int
	selected bool
	x_input []u8
	y_input []u8
	sequence u32
	request ColorMeterRequest
	report ColorMeterReport
	aperture int = 1
	status string = 'color_meter.ready'
	hex_text string
	rgb_text string
	detail_text string
	language DesktopLanguage
}

fn (mut app ColorMeterApp) initialize() {
	if app.initialized { return }
	app.x_input = []u8{cap: 8}
	app.y_input = []u8{cap: 8}
	unsafe { app.x_input.flags |= .noslices app.y_input.flags |= .noslices }
	app.x_input << u8(48)
	app.y_input << u8(48)
	app.initialized = true
}

fn open_color_meter_app(mut _ Desktop) !NativeApp {
	return &ColorMeterApp{}
}

fn color_meter_coordinate(bytes []u8) ?int {
	if bytes.len == 0 || bytes.len > 7 { return none }
	mut number := 0
	for byte in bytes {
		if byte < 48 || byte > 57 { return none }
		number = number * 10 + int(byte - 48)
		if number > 32767 { return none }
	}
	return number
}

fn color_meter_set_coordinate(mut bytes []u8, coordinate int) {
	mut buffer := [16]u8{}
	length := unsafe { C.snprintf(&char(&buffer[0]), 16, c'%d', coordinate) }
	if length <= 0 || length > 7 { return }
	bytes.clear()
	for index in 0 .. length { bytes << buffer[index] }
}

fn (mut app ColorMeterApp) queue(command ColorMeterCommand) {
	app.initialize()
	mut x := 0
	mut y := 0
	if command == .sample {
		x = color_meter_coordinate(app.x_input) or { app.status = 'color_meter.invalid_input' return }
		y = color_meter_coordinate(app.y_input) or { app.status = 'color_meter.invalid_input' return }
	}
	app.sequence++
	app.request = ColorMeterRequest{ sequence: app.sequence, command: command, x: x, y: y, aperture: app.aperture }
}

fn (mut app ColorMeterApp) take_desktop_service_request() ColorMeterRequest {
	request := app.request
	app.request = ColorMeterRequest{}
	return request
}

fn (mut app ColorMeterApp) refresh_texts() {
	unsafe { app.hex_text.free() app.rgb_text.free() app.detail_text.free() }
	app.hex_text = if app.report.count > 0 { color_meter_value_text(app.report.rgb, true) } else { '' }
	app.rgb_text = if app.report.count > 0 { color_meter_value_text(app.report.rgb, false) } else { '' }
	mut buffer := [96]u8{}
	length := unsafe { C.snprintf(&char(&buffer[0]), 96, c'%d x %d px / (%d, %d) / %d',
		app.report.width, app.report.height, app.report.x, app.report.y, app.report.count) }
	text := if length > 0 && length < 96 { unsafe { tos(&buffer[0], length).clone() } } else { '' }
	app.detail_text = tr_fill('color_meter.details', text)
	unsafe { text.free() }
	app.language = desktop_language
}

fn (mut app ColorMeterApp) receive_desktop_service_reply(payload string) {
	report := color_meter_decode_report(payload) or { app.status = 'color_meter.unavailable' return }
	if report.sequence != app.sequence { return }
	previous := ColorMeterReport{ ...app.report, sequence: report.sequence }
	if previous != report || app.hex_text.len == 0 {
		app.report = report
		app.refresh_texts()
	}
	app.report = report
	app.status = match report.status {
		.sampled { if app.following { 'color_meter.live_status' } else { 'color_meter.frozen' } }
		.copied { 'color_meter.copied' }
		.invalid { 'color_meter.invalid' }
		.unavailable { 'color_meter.unavailable' }
		else { 'color_meter.ready' }
	}
}

fn (mut app ColorMeterApp) freeze() {
	app.following = false
	app.request = ColorMeterRequest{}
	if app.report.count > 0 {
		app.initialize()
		color_meter_set_coordinate(mut app.x_input, app.report.x)
		color_meter_set_coordinate(mut app.y_input, app.report.y)
		app.status = 'color_meter.frozen'
	}
}

fn (mut app ColorMeterApp) handle(action string) ! {
	app.initialize()
	for index, candidate in color_meter_aperture_actions {
		if action == candidate {
			app.aperture = color_meter_aperture_values[index]
			app.queue(if app.following { ColorMeterCommand.pointer } else { ColorMeterCommand.sample })
			return
		}
	}
	match action {
		'color_meter.live' { app.following = true app.queue(.pointer) }
		'color_meter.freeze' { app.freeze() }
		'color_meter.sample' { app.following = false app.queue(.sample) }
		'color_meter.copy_hex' { app.freeze() app.queue(.copy_hex) }
		'color_meter.copy_rgb' { app.freeze() app.queue(.copy_rgb) }
		'color_meter.x' { app.focus = 0 app.selected = true }
		'color_meter.y' { app.focus = 1 app.selected = true }
		else {}
	}
}

fn (mut app ColorMeterApp) paste_input(text string) {
	app.initialize()
	if text.len > 7 { app.status = 'color_meter.invalid_input' return }
	for byte in text { if byte < 48 || byte > 57 { app.status = 'color_meter.invalid_input' return } }
	if app.focus == 0 { console_paste_field(mut app.x_input, text, 7, app.selected) }
	else { console_paste_field(mut app.y_input, text, 7, app.selected) }
	app.selected = false
}

fn (mut app ColorMeterApp) key_input(input string) {
	app.initialize()
	if input.len > 1 && input[0] == 27 { return }
	for byte in input {
		if byte == 27 || byte == 32 { app.freeze() }
		else if byte == 13 || byte == 10 { app.handle('color_meter.sample') or {} }
		else if byte == 9 { app.focus = 1 - app.focus app.selected = true }
		else if byte == 1 { app.selected = true }
		else if byte == 3 { app.handle('color_meter.copy_hex') or {} }
		else if byte == 8 || byte == 127 {
			if app.focus == 0 { console_backspace(mut app.x_input, app.selected) }
			else { console_backspace(mut app.y_input, app.selected) }
			app.selected = false
		} else if byte >= 48 && byte <= 57 {
			character := unsafe { tos(&byte, 1) }
			if app.focus == 0 { console_edit_character(mut app.x_input, character, 7, app.selected) }
			else { console_edit_character(mut app.y_input, character, 7, app.selected) }
			app.selected = false
		}
	}
}

fn (mut app ColorMeterApp) poll() bool {
	if app.following { app.queue(.pointer) }
	// The compositor marks the tree only when its returned sample changes.
	return false
}

fn (app &ColorMeterApp) next_poll_ms() u64 {
	return if app.following { u64(100) } else { u64(1000) }
}

fn (mut app ColorMeterApp) close_app() {
	unsafe {
		app.x_input.free() app.y_input.free()
		app.hex_text.free() app.rgb_text.free() app.detail_text.free()
	}
	app.x_input = []u8{}
	app.y_input = []u8{}
	app.hex_text = ''
	app.rgb_text = ''
	app.detail_text = ''
	app.initialized = false
	app.following = false
	app.request = ColorMeterRequest{}
	app.report = ColorMeterReport{}
}

fn (mut app ColorMeterApp) build(size ui2.Rect) !ui2.Element {
	app.initialize()
	if app.language != desktop_language && app.hex_text.len > 0 { app.refresh_texts() }
	width := int(size.width)
	height := int(size.height)
	mut children := frame_elements(32)
	children << ui2.label('', tr('app.color_meter'), ui2.rect(12, 10, f64(width - 24), 24),
		ui2.TextStyle{ size: 18, color: body_heading, bold: true })
	if width < 584 || height < 506 {
		children << ui2.label('', tr('color_meter.resize'), ui2.rect(12, 44, f64(width - 24), 72),
			ui2.TextStyle{ size: 12, color: body_muted, lines: 3 })
		return ui2.screen(app_surface, children)
	}
	children << console_button('color_meter.live', 'color_meter.live', 12, 42, 142, app.following)
	children << console_button('color_meter.freeze', 'color_meter.freeze', 162, 42, 116, !app.following)
	children << console_button('color_meter.sample', 'color_meter.sample', 286, 42, 112, false)
	children << ui2.label('', tr('color_meter.x'), ui2.rect(12, 78, 120, 18), ui2.TextStyle{ size: 11, color: body_muted })
	children << ui2.label('', tr('color_meter.y'), ui2.rect(140, 78, 120, 18), ui2.TextStyle{ size: 11, color: body_muted })
	children << console_field('color_meter.x', editor_bytes_text(app.x_input), 12, 98, 120, app.focus == 0)
	children << console_field('color_meter.y', editor_bytes_text(app.y_input), 140, 98, 120, app.focus == 1)
	children << ui2.label('', tr('color_meter.aperture'), ui2.rect(276, 78, f64(width - 288), 18),
		ui2.TextStyle{ size: 11, color: body_muted })
	for index, action in color_meter_aperture_actions {
		children << ui2.button(action, color_meter_aperture_texts[index], ui2.rect(f64(276 + index * 76), 98, 68, 28),
			ui2.BoxStyle{ bg: if app.aperture == color_meter_aperture_values[index] { app_accent } else { settings_choice_bg }, radius: 4 },
			ui2.TextStyle{ size: 11, align: .center, color: if app.aperture == color_meter_aperture_values[index] { app_on_accent } else { body_text } })
	}
	children << ui2.label('', tr('color_meter.magnifier'), ui2.rect(12, 138, 228, 20), ui2.TextStyle{ size: 12, color: body_muted })
	mut cells := frame_elements(82)
	for row in 0 .. color_meter_grid_size {
		for column in 0 .. color_meter_grid_size {
			index := row * color_meter_grid_size + column
			cells << ui2.view('', ui2.rect(f64(column * 24), f64(row * 24), 24, 24),
				ui2.BoxStyle{ bg: if app.report.valid[index] { app.report.grid[index] } else { body_panel } }, [])
		}
	}
	radius := app.aperture / 2
	cells << ui2.view('', ui2.rect(f64((4 - radius) * 24), f64((4 - radius) * 24),
		f64(app.aperture * 24), f64(app.aperture * 24)), ui2.BoxStyle{
			transparent: true, border_color: 0xffffff, border_left: 1, border_right: 1, border_top: 1, border_bottom: 1
		}, [])
	children << ui2.view('color_meter.magnifier', ui2.rect(12, 162, 216, 216), ui2.BoxStyle{}, cells)
	children << ui2.label('', tr('color_meter.value'), ui2.rect(252, 142, f64(width - 264), 24), ui2.TextStyle{ size: 12, color: body_muted })
	children << ui2.view('color_meter.swatch', ui2.rect(252, 174, 120, 100), ui2.BoxStyle{ bg: if app.report.count > 0 { app.report.rgb } else { body_panel }, radius: 6 }, [])
	children << ui2.label('', app.hex_text, ui2.rect(384, 180, f64(width - 396), 28), ui2.TextStyle{ size: 20, color: body_text, font_family: 'mono' })
	children << ui2.label('', app.rgb_text, ui2.rect(384, 220, f64(width - 396), 24), ui2.TextStyle{ size: 12, color: body_text, font_family: 'mono' })
	children << console_button('color_meter.copy_hex', 'color_meter.copy_hex', 252, 294, 142, false)
	children << console_button('color_meter.copy_rgb', 'color_meter.copy_rgb', 402, 294, 142, false)
	children << ui2.label('', app.detail_text, ui2.rect(252, 338, f64(width - 264), 42),
		ui2.TextStyle{ size: 11, color: body_muted, lines: 2 })
	children << ui2.label('', tr(app.status), ui2.rect(12, f64(height - 126), f64(width - 24), 44),
		ui2.TextStyle{ size: 12, color: body_text, lines: 2 })
	children << ui2.label('', tr('color_meter.hint'), ui2.rect(12, f64(height - 76), f64(width - 24), 34),
		ui2.TextStyle{ size: 11, color: body_muted, lines: 2 })
	children << ui2.label('', tr('color_meter.clipboard_hint'), ui2.rect(12, f64(height - 37), f64(width - 24), 32),
		ui2.TextStyle{ size: 10, color: body_muted, lines: 2 })
	return ui2.screen(app_surface, children)
}
