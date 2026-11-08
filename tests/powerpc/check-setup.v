// SPDX-License-Identifier: GPL-2.0-or-later
// Independent assertions on the real 800x600 first-run desktop scanout.
module main

import os

fn pixel(data []u8, x int, y int) u32 {
	at := 'P6\n800 600\n255\n'.len + (y * 800 + x) * 3
	return u32(data[at]) << 16 | u32(data[at + 1]) << 8 | data[at + 2]
}

fn setup_screen(path string) ![]u8 {
	data := os.read_bytes(path)!
	header := 'P6\n800 600\n255\n'
	if data.len != header.len + 800 * 600 * 3 || data[..header.len].bytestr() != header {
		return error('Invalid or incomplete 800x600 PPM: ' + path)
	}
	for point in [[20, 20], [780, 580], [20, 300]] {
		if pixel(data, point[0], point[1]) != 0x172235 {
			return error('Setup backdrop missing: ' + path)
		}
	}
	for point in [[190, 300], [610, 300], [400, 100], [400, 500]] {
		if pixel(data, point[0], point[1]) != 0xfbfcfe {
			return error('Setup card missing: ' + path)
		}
	}
	mut ink := 0
	for y in 124 .. 150 {
		for x in 212 .. 450 {
			if pixel(data, x, y) & 0x808080 == 0 { ink++ }
		}
	}
	if ink < 150 { return error('Setup heading missing: ' + path) }
	return data
}

fn changed(a []u8, b []u8, x int, y int, w int, h int) int {
	mut count := 0
	for yy in y .. y + h {
		for xx in x .. x + w {
			if pixel(a, xx, yy) != pixel(b, xx, yy) { count++ }
		}
	}
	return count
}

fn check(directory string) ! {
	before := setup_screen(directory + '/program.ppm')!
	typed := setup_screen(directory + '/program-typed.ppm')!
	clicked := setup_screen(directory + '/program-clicked.ppm')!
	settled := setup_screen(directory + '/program-settled.ppm')!
	if changed(before, typed, 220, 220, 100, 24) < 80 {
		return error('USB typing did not change the name field')
	}
	if changed(typed, clicked, 220, 292, 160, 24) < 80 {
		return error('Click and typing did not change the password field')
	}
	if changed(clicked, settled, 212, 214, 376, 182) != 0 {
		return error('Setup fields changed after input settled')
	}
	mut samples := 0
	for name in os.ls(directory)! {
		if name.starts_with('stability-') && name.ends_with('.ppm') {
			setup_screen(directory + '/' + name)!
			samples++
		}
	}
	println('PASS native desktop setup: form, text, USB field changes, ${samples} additional frames')
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--frame' {
		setup_screen(os.args[2]) or {
			eprintln(err)
			exit(1)
		}
		println('PASS native desktop setup frame')
		return
	}
	if os.args.len != 2 {
		eprintln('Usage: v run tests/powerpc/check-setup.v CAPTURE_DIRECTORY')
		exit(2)
	}
	check(os.args[1]) or {
		eprintln(err)
		exit(1)
	}
}
