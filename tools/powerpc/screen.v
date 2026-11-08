// SPDX-License-Identifier: GPL-2.0-or-later
module main

import strconv

fn validate_screen(data []u8) ! {
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
	if w < 320 || w > 1024 || h < 240 || h > 1024 || data.len - at != w * h * 3 { return error('Screenshot dimensions') }
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
