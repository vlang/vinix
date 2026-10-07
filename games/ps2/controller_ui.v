// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The button order remains the frontend's established control order. Wire
// actions have a stable namespace; pointer hit testing uses the same frames.
const control_wire_ids = ['ps2.open', 'ps2.pause', 'ps2.reset', 'ps2.up', 'ps2.down',
	'ps2.left', 'ps2.right', 'ps2.select', 'ps2.start', 'ps2.l1', 'ps2.r1',
	'ps2.cross', 'ps2.circle', 'ps2.square', 'ps2.triangle', 'ps2.l2', 'ps2.r2']
const control_images = ['builtin:folder', 'builtin:ps_pause', 'builtin:ps_reset',
	'builtin:arrow_up', 'builtin:arrow_down', 'builtin:arrow_left', 'builtin:arrow_right',
	'builtin:ps_select', 'builtin:ps_start', '', '', 'builtin:ps_cross',
	'builtin:ps_circle', 'builtin:ps_square', 'builtin:ps_triangle', '', '']
const control_hints = ['Open an ISO or ELF game', 'Pause / Resume - P', 'Restart the game',
	'D-pad Up - Up arrow / W', 'D-pad Down - Down arrow / S', 'D-pad Left - Left arrow / A',
	'D-pad Right - Right arrow / D', 'Select - Tab', 'Start - Enter', 'L1 - Q', 'R1 - E',
	'Cross - Z', 'Circle - X', 'Square - C', 'Triangle - V', 'L2 - 1', 'R2 - 3']

__global hovered_control = -1
__global pointer_held = false

fn controller_width() int {
	return if app_width > 800 { 768 } else { app_width - 32 }
}

fn control_rect(index int) (int, int, int, int) {
	if index == 0 { return 16, app_height - 158, 112, 32 }
	if index == 1 { return app_width - 144, app_height - 158, 88, 32 }
	if index == 2 { return app_width - 48, app_height - 158, 32, 32 }
	panel_width := controller_width()
	left := (app_width - panel_width) / 2
	key := if panel_width < 560 { 28 } else { 34 }
	stride := key + 2
	cy := app_height - 66
	dpad := left + panel_width * 12 / 100
	face := left + panel_width * 88 / 100
	shoulder_width := if panel_width < 560 { 36 } else { 48 }
	center_width := if panel_width < 560 { 36 } else { 52 }
	match index {
		3 { return dpad - key / 2, cy - stride - key / 2, key, key }
		4 { return dpad - key / 2, cy + stride - key / 2, key, key }
		5 { return dpad - stride - key / 2, cy - key / 2, key, key }
		6 { return dpad + stride - key / 2, cy - key / 2, key, key }
		7 { return left + panel_width * 45 / 100 - center_width / 2, cy - 24, center_width, 32 }
		8 { return left + panel_width * 55 / 100 - center_width / 2, cy - 24, center_width, 32 }
		9 { return left + panel_width * 31 / 100 - shoulder_width / 2, cy - 38, shoulder_width, 30 }
		10 { return left + panel_width * 69 / 100 - shoulder_width / 2, cy - 38, shoulder_width, 30 }
		11 { return face - key / 2, cy + stride - key / 2, key, key }
		12 { return face + stride - key / 2, cy - key / 2, key, key }
		13 { return face - stride - key / 2, cy - key / 2, key, key }
		14 { return face - key / 2, cy - stride - key / 2, key, key }
		15 { return left + panel_width * 31 / 100 - shoulder_width / 2, cy + 6, shoulder_width, 30 }
		16 { return left + panel_width * 69 / 100 - shoulder_width / 2, cy + 6, shoulder_width, 30 }
		else { return 0, 0, 0, 0 }
	}
}

fn control_at(x int, y int) int {
	for index in 0 .. control_ids.len {
		left, top, width, height := control_rect(index)
		if x >= left && x < left + width && y >= top && y < top + height { return index }
	}
	return -1
}

fn control_mask(index int) u32 {
	if index < 3 || index >= control_ids.len { return 0 }
	for button, name in joy_ids {
		if name == control_ids[index] { return u32(1) << button }
	}
	return 0
}

fn control_color(index int) u32 {
	return match index {
		11 { u32(0x7eb2ff) } // blue cross
		12 { u32(0xf08087) } // red circle
		13 { u32(0xe3a5d2) } // pink square
		14 { u32(0x70ddbd) } // green triangle
		else { u32(0xdce4f2) }
	}
}

fn control_build(mut out []u8, index int, offset_x int, offset_y int) {
	x, y, width, height := control_rect(index)
	shoulder := index == 9 || index == 10 || index == 15 || index == 16
	held := (emulator.buttons | emulator.pulse) & control_mask(index) != 0
		|| (index < 3 && pointer_held && hovered_control == index)
	bg := if held { u32(0x3a506a) } else if hovered_control == index {
		u32(0x2f4056)
	} else { u32(0x222e40) }
	text := if index == 0 { 'Open game' } else if index == 1 {
		if emulator.paused { 'Resume' } else { 'Pause' }
	} else if shoulder { control_names[index] } else { '' }
	image := if index == 1 && emulator.paused { 'builtin:ps_start' } else { control_images[index] }
	encode_element(mut out, 4, f64(x - offset_x), f64(y - offset_y), f64(width), f64(height),
		control_wire_ids[index], text, image, 0, ElementStyle{
			bg: bg
			radius: if index >= 11 && index <= 14 { f64(height) / 2 } else { 6 }
			color: control_color(index)
			size: 12
			bold: shoulder
			tooltip: control_hints[index]
		})
}

fn ui_build(mut out []u8) {
	encode_element(mut out, 0, 0, 0, f64(app_width), f64(app_height), '', '', '', 3, ElementStyle{})
	path := 'vinix-surface:${emulator.surface_path}'
	defer { unsafe { path.free() } }
	available_height := app_height - 164
	width := if app_width * 3 <= available_height * 4 { app_width } else { available_height * 4 / 3 }
	height := width * 3 / 4
	encode_element(mut out, 3, f64((app_width - width) / 2), f64((available_height - height) / 2),
		f64(width), f64(height), '', '', path, 0, ElementStyle{ transparent: true })

	// A quiet playback bar keeps file actions separate from the controller.
	encode_element(mut out, 1, 0, f64(available_height), f64(app_width), 44, '', '', '', 4,
		ElementStyle{ bg: 0x111824 })
	control_build(mut out, 0, 0, available_height)
	label := if opening { 'Game path: ${path_text}_ (Enter to open, Esc to cancel)' }
		else if hovered_control >= 0 && emulator.status.starts_with('Playing ') { control_hints[hovered_control] }
		else { emulator.status }
	defer { if opening { unsafe { label.free() } } }
	encode_element(mut out, 2, 144, 6, f64(app_width - 296), 32, 'status', label, '', 0,
		ElementStyle{ transparent: true, color: 0x9aaac0, size: 12, align: 0 })
	control_build(mut out, 1, 0, available_height)
	control_build(mut out, 2, 0, available_height)

	panel_width := controller_width()
	panel_left := (app_width - panel_width) / 2
	panel_top := app_height - 120
	encode_element(mut out, 1, f64(panel_left), f64(panel_top), f64(panel_width), 108,
		'', '', '', 16, ElementStyle{ bg: 0x182130, radius: 10 })
	for index in 3 .. control_ids.len { control_build(mut out, index, panel_left, panel_top) }
	for index in [7, 8]! {
		x, y, key_width, key_height := control_rect(index)
		encode_element(mut out, 2, f64(x - panel_left), f64(y + key_height + 4 - panel_top),
			f64(key_width), 18, if index == 7 { 'select-caption' } else { 'start-caption' },
			if index == 7 { 'SELECT' } else { 'START' }, '', 0,
			ElementStyle{ transparent: true, size: 10, color: 0x8797af, bold: true })
	}
}
