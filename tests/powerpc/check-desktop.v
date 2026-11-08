// SPDX-License-Identifier: GPL-2.0-or-later
// Independently check sustained compositor ownership and actual USB actions.
module main

import os

fn pixel(data []u8, x int, y int) u32 {
	at := 'P6\n800 600\n255\n'.len + (y * 800 + x) * 3
	return u32(data[at]) << 16 | u32(data[at + 1]) << 8 | data[at + 2]
}

fn screen(path string) ![]u8 {
	data := os.read_bytes(path)!
	header := 'P6\n800 600\n255\n'
	if data.len != header.len + 800 * 600 * 3 || data[..header.len].bytestr() != header {
		return error('Invalid 800x600 screenshot: ' + path)
	}
	if pixel(data, 725, 20) == 0xff0000 && pixel(data, 749, 20) == 0x00ff00 && pixel(data, 773, 20) == 0x0000ff {
		return error('Kernel console replaced the desktop: ' + path)
	}
	return data
}

// The System window has a wide pale body; icons never span 300 pixels.
// Locate it independently of the kernel, compositor log and mouse commands.
fn window(data []u8) !(int, int) {
	for y in 0 .. 500 {
		mut start := 0
		for x in 0 .. 800 {
			color := pixel(data, x, y)
			if color >> 16 < 220 || (color >> 8 & 255) < 220 || color & 255 < 220 { start = x + 1 }
			if x - start >= 300 { return start, y }
		}
	}
	return error('System window body missing')
}

fn check(directory string) ! {
	log := os.read_file(directory + '/program.log')!
	marker := 'vinix-desktop: GPU init: first canvas presented'
	if !log.contains(marker) { return error('Compositor never presented its first frame') }
	after := log.all_after(marker)
	if after.contains('mapping framebuffer memory') || after.contains('calling presenter creation') {
		return error('Unchanged display was repeatedly unmapped and reopened after startup')
	}
	if log.contains('VINIX-PPC: PANIC') || log.contains('init exited') { return error('Desktop stopped') }
	for group in ['idle', 'settled'] {
		for i in 0 .. 20 { screen(directory + '/display-${group}-${i:02}.ppm')! }
	}
	for group in ['drag', 'held'] {
		for i in 0 .. 6 { screen(directory + '/display-${group}-${i:02}.ppm')! }
	}
	before := screen(directory + '/display-before-drag.ppm')!
	end := screen(directory + '/display-after-drag.ppm')!
	x1, y1 := window(before)!
	x2, y2 := window(end)!
	if x2 != x1 - 220 || y2 != y1 + 78 { return error('Held USB drag was lost: window (${x1},${y1}) -> (${x2},${y2}), expected (-220,+78)') }
	opened := screen(directory + '/display-menu-open.ppm')!
	closed := screen(directory + '/display-menu-close.ppm')!
	mut changed := 0
	for y in 300 .. 550 {
		for x in 0 .. 180 { if pixel(opened, x, y) != pixel(closed, x, y) { changed++ } }
	}
	if changed < 10000 { return error('USB clicks did not open and close the Start menu') }
	println('PASS desktop: 56 captures, no remapping or console overwrite, held drag across discovery polls, Start menu clicks')
}

fn main() {
	if os.args.len != 2 { eprintln('Usage: v run tests/powerpc/check-desktop.v CAPTURE_DIRECTORY'); exit(2) }
	check(os.args[1]) or { eprintln(err); exit(1) }
}
