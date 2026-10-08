// SPDX-License-Identifier: GPL-2.0-or-later
module main

const control_wire_ids = ['n64.open', 'n64.pause', 'n64.reset', 'n64.up', 'n64.down',
	'n64.left', 'n64.right', 'n64.start', 'n64.z', 'n64.l', 'n64.r', 'n64.a', 'n64.b',
	'n64.c_up', 'n64.c_down', 'n64.c_left', 'n64.c_right', 'n64.stick_up', 'n64.stick_down',
	'n64.stick_left', 'n64.stick_right']
const control_images = ['builtin:folder', 'builtin:ps_pause', 'builtin:ps_reset',
	'builtin:arrow_up', 'builtin:arrow_down', 'builtin:arrow_left', 'builtin:arrow_right',
	'', '', '', '', '', '', 'builtin:n64_c_up', 'builtin:n64_c_down',
	'builtin:n64_c_left', 'builtin:n64_c_right', 'builtin:arrow_up', 'builtin:arrow_down',
	'builtin:arrow_left', 'builtin:arrow_right']
const control_hints = ['Open a Z64, V64 or N64 cartridge', 'Pause / Resume - P',
	'Restart the cartridge', 'D-pad Up - Up arrow', 'D-pad Down - Down arrow',
	'D-pad Left - Left arrow', 'D-pad Right - Right arrow', 'Start - Enter',
	'Z trigger (back of controller) - C', 'L shoulder - Q', 'R shoulder - E',
	'A - Z', 'B - X', 'C Up - I', 'C Down - K', 'C Left - J', 'C Right - L',
	'Control stick Up - W', 'Control stick Down - S', 'Control stick Left - A',
	'Control stick Right - D']

__global hovered_control = -1
__global pointer_held = false
__global stick_held = false

fn controller_height() int {
	return if app_height < 500 { 172 } else { 224 }
}

// The compact shell preserves the original three grips and control positions.
// All drawing and hit targets use this same 360-by-224 coordinate system.
fn controller_point(x int, y int) (int, int) {
	height := controller_height()
	width := 360 * height / 224
	return (app_width - width) / 2 + x * height / 224,
		app_height - height - 16 + y * height / 224
}

fn controller_size(size int) int {
	return size * controller_height() / 224
}

fn control_rect(index int) (int, int, int, int) {
	bar_top := app_height - controller_height() - 68
	if index == 0 { return 16, bar_top + 6, 112, 32 }
	if index == 1 { return app_width - 144, bar_top + 6, 88, 32 }
	if index == 2 { return app_width - 48, bar_top + 6, 32, 32 }
	mut px, mut py, mut width, mut height := 0, 0, 24, 24
	match index {
		3 { px = 77; py = 48 }
		4 { px = 77; py = 96 }
		5 { px = 53; py = 72 }
		6 { px = 101; py = 72 }
		7 { px = 180; py = 47; width = 22; height = 22 }
		8 { px = 180; py = 187; width = 34; height = 22 }
		9 { px = 61; py = 13; width = 42; height = 20 }
		10 { px = 299; py = 13; width = 42; height = 20 }
		11 { px = 273; py = 123; width = 32; height = 32 }
		12 { px = 246; py = 99; width = 32; height = 32 }
		13 { px = 295; py = 42; width = 22; height = 22 }
		14 { px = 295; py = 90; width = 22; height = 22 }
		15 { px = 271; py = 66; width = 22; height = 22 }
		16 { px = 319; py = 66; width = 22; height = 22 }
		17 { px = 180; py = 103; width = 26; height = 26 }
		18 { px = 180; py = 155; width = 26; height = 26 }
		19 { px = 154; py = 129; width = 26; height = 26 }
		20 { px = 206; py = 129; width = 26; height = 26 }
		else { return 0, 0, 0, 0 }
	}
	x, y := controller_point(px, py)
	width = controller_size(width)
	height = controller_size(height)
	if width < 20 { width = 20 }
	if height < 20 { height = 20 }
	return x - width / 2, y - height / 2, width, height
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

fn in_stick_well(x int, y int) bool {
	cx, cy := controller_point(180, 129)
	dx, dy := x - cx, y - cy
	radius := controller_size(40)
	return dx * dx + dy * dy <= radius * radius
}

fn stick_mask_at(x int, y int) u32 {
	cx, cy := controller_point(180, 129)
	deadzone := controller_size(6)
	mut mask := u32(0)
	if y < cy - deadzone { mask |= u32(1) << 14 }
	if y > cy + deadzone { mask |= u32(1) << 15 }
	if x < cx - deadzone { mask |= u32(1) << 16 }
	if x > cx + deadzone { mask |= u32(1) << 17 }
	return mask
}

fn control_background(index int) u32 {
	return match index {
		3 ... 6 { u32(0x343a40) }
		7 { u32(0xd85459) }
		8 ... 10 { u32(0x666d77) }
		11 { u32(0x357fdf) }
		12 { u32(0x27985b) }
		13 ... 16 { u32(0xe8c64a) }
		else { u32(0x222e40) }
	}
}

fn control_build(mut out []u8, index int, offset_x int, offset_y int) {
	x, y, width, height := control_rect(index)
	held := (emulator.buttons | emulator.pulse) & control_mask(index) != 0
		|| (index < 3 && pointer_held && hovered_control == index)
	base := control_background(index)
	// Dim pressed plastic and brighten hover, retaining each button's color.
	bg := if held { ((base & 0xfefefe) >> 1) + ((base & 0xfcfcfc) >> 2) }
		else if hovered_control == index { ((base & 0xfefefe) >> 1) + 0x7f7f7f }
		else { base }
	text := match index {
		0 { 'Open game' }
		1 { if emulator.paused { 'Resume' } else { 'Pause' } }
		8 ... 12 { control_names[index] }
		else { '' }
	}
	image := if index == 1 && emulator.paused { 'builtin:ps_start' } else { control_images[index] }
	encode_element(mut out, 4, f64(x - offset_x), f64(y - offset_y), f64(width), f64(height),
		control_wire_ids[index], text, image, 0, ElementStyle{
			bg: bg
			radius: if index == 7 || (index >= 11 && index <= 16) { f64(height) / 2 }
				else if index >= 3 && index <= 6 { 2 } else { 6 }
			color: if index >= 13 && index <= 16 { 0x594a1c }
				else if index >= 17 { if held { 0xd4d9de } else { 0x858d97 } }
				else { 0xf4f6fa }
			size: if index == 11 || index == 12 { 16 } else { 12 }
			bold: index >= 8 && index <= 12
			transparent: index >= 17
			tooltip: control_hints[index]
		})
}

fn controller_caption(mut out []u8, x int, y int, width int, text string) {
	px, py := controller_point(x, y)
	w := controller_size(width)
	left, top := controller_point(0, 0)
	encode_element(mut out, 2, f64(px - left - w / 2), f64(py - top), f64(w), 14,
		'', text, '', 0, ElementStyle{ transparent: true, color: 0x434a53, size: 9, bold: true })
}

fn ui_build(mut out []u8) {
	encode_element(mut out, 0, 0, 0, f64(app_width), f64(app_height), '', '', '', 3, ElementStyle{})
	path := 'vinix-surface:${emulator.surface_path}'
	defer { unsafe { path.free() } }
	available_height := app_height - controller_height() - 68
	width := if app_width * 3 <= available_height * 4 { app_width } else { available_height * 4 / 3 }
	height := width * 3 / 4
	encode_element(mut out, 3, f64((app_width - width) / 2), f64((available_height - height) / 2),
		f64(width), f64(height), '', '', path, 0, ElementStyle{ transparent: true })

	encode_element(mut out, 1, 0, f64(available_height), f64(app_width), 44, '', '', '', 4,
		ElementStyle{ bg: 0x111824 })
	control_build(mut out, 0, 0, available_height)
	label := if opening { 'Game path: ${path_text}_ (Enter to open, Esc to cancel)' }
		else if hovered_control >= 0 && emulator.status.starts_with('Playing ') { control_hints[hovered_control] }
		else if stick_held && emulator.status.starts_with('Playing ') { 'Control stick - drag to move, release to center' }
		else { emulator.status }
	defer { if opening { unsafe { label.free() } } }
	encode_element(mut out, 2, 144, 6, f64(app_width - 296), 32, 'status', label, '', 0,
		ElementStyle{ transparent: true, color: 0x9aaac0, size: 12, align: 0 })
	control_build(mut out, 1, 0, available_height)
	control_build(mut out, 2, 0, available_height)

	left, top := controller_point(0, 0)
	body_width := controller_size(360)
	body_height := controller_height()
	encode_element(mut out, 1, f64(left), f64(top), f64(body_width), f64(body_height),
		'', '', '', 31, ElementStyle{ transparent: true })
	encode_element(mut out, 3, 0, 0, f64(body_width), f64(body_height), '', '', 'builtin:n64_body', 0,
		ElementStyle{ transparent: true, color: 0xb8bdc6 })
	// Dark sockets make the colored face buttons read as raised plastic.
	for index in [7, 11, 12, 13, 14, 15, 16]! {
		x, y, w, h := control_rect(index)
		encode_element(mut out, 1, f64(x - left - 2), f64(y - top - 2), f64(w + 4), f64(h + 4),
			'', '', '', 0, ElementStyle{ bg: 0x656c76, radius: f64(h + 4) / 2 })
	}
	dx, dy := controller_point(77, 72)
	key := controller_size(24)
	encode_element(mut out, 1, f64(dx - left - key / 2), f64(dy - top - key / 2), f64(key), f64(key),
		'', '', '', 0, ElementStyle{ bg: 0x343a40, radius: 1 })
	for index in 3 .. control_ids.len { control_build(mut out, index, left, top) }
	buttons := emulator.buttons | emulator.pulse
	offset_x := (if buttons & (u32(1) << 17) != 0 { 8 } else { 0 })
		- (if buttons & (u32(1) << 16) != 0 { 8 } else { 0 })
	offset_y := (if buttons & (u32(1) << 15) != 0 { 8 } else { 0 })
		- (if buttons & (u32(1) << 14) != 0 { 8 } else { 0 })
	sx, sy := controller_point(180 + offset_x, 129 + offset_y)
	cap_size := controller_size(28)
	encode_element(mut out, 3, f64(sx - left - cap_size / 2), f64(sy - top - cap_size / 2),
		f64(cap_size), f64(cap_size), '', '', 'builtin:n64_stick', 0,
		ElementStyle{ transparent: true, color: 0xbcc3cc })
	controller_caption(mut out, 180, 63, 44, 'START')
	controller_caption(mut out, 180, 202, 40, 'BACK')
	controller_caption(mut out, 295, 59, 16, 'C')
}
