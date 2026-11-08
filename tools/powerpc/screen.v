// SPDX-License-Identifier: GPL-2.0-or-later
module main

import strconv

struct Screen {
	width int
	height int
	offset int
}

fn screen_header(data []u8) !Screen {
	mut at := 0
	mut words := []string{}
	for words.len < 4 {
		start := at
		for at < data.len && data[at] != ` ` && data[at] != `\n` { at++ }
		if at == data.len { return error('Truncated PPM header') }
		if at > start { words << data[start..at].bytestr() }
		at++
	}
	if words[0] != 'P6' || words[3] != '255' { return error('Unsupported screenshot') }
	w := strconv.atoi(words[1])!
	h := strconv.atoi(words[2])!
	if w < 320 || w > 1920 || h < 240 || h > 1200 || data.len - at != w * h * 3 { return error('Screenshot dimensions') }
	return Screen{w, h, at}
}

fn validate_screen(data []u8) ! {
	screen := screen_header(data)!
	w := screen.width
	h := screen.height
	at := screen.offset
	for i, color in [u32(0xff0000), 0x00ff00, 0x0000ff] {
		pixel := at + (16 * w + w - 76 + i * 24) * 3
		actual := u32(data[pixel]) << 16 | u32(data[pixel + 1]) << 8 | data[pixel + 2]
		if actual != color { return error('Framebuffer color mismatch: ${actual:06x}') }
	}
	mut ink := 0
	for pixel := at + w * 56 * 3; pixel < at + w * (h - 40) * 3; pixel += 3 {
		if data[pixel] == 0xdc && data[pixel + 1] == 0xe9 && data[pixel + 2] == 0xf2 { ink++ }
	}
	if ink < 300 { return error('Framebuffer has no rendered console text') }
}

fn validate_pointer(data []u8, pressed bool) ! {
	screen := screen_header(data)!
	x := screen.width / 2 + 50
	y := screen.height / 2 + 30
	for yy in 0 .. 20 {
		for xx in 0 .. yy / 2 + 1 {
			pixel := screen.offset + ((y + yy) * screen.width + x + xx) * 3
			actual := u32(data[pixel]) << 16 | u32(data[pixel + 1]) << 8 | data[pixel + 2]
			expected := if xx == 0 || xx == yy / 2 || yy == 19 { u32(0) } else if pressed { u32(0xffb454) } else { u32(0xffffff) }
			if actual != expected { return error('USB pointer pixel mismatch at ${x + xx},${y + yy}: ${actual:06x}, expected ${expected:06x}') }
		}
	}
}
