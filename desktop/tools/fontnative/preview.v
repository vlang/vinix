// SPDX-License-Identifier: GPL-2.0-or-later
module fontnative

import compress.zlib
import encoding.binary
import hash.crc32
import os

fn png_chunk(kind string, data []u8) []u8 {
	mut result := []u8{len: 4}
	binary.big_endian_put_u32(mut result, u32(data.len))
	result << kind.bytes()
	result << data
	result << u32_bytes(crc32.sum([...kind.bytes(), ...data]))
	return result
}

fn paint(mut rgb []u8, glyph BakedGlyph, left int, top int, shade int) {
	for y in 0 .. glyph.height {
		for x in 0 .. glyph.width {
			xx, yy := left + glyph.bx + x, top + glyph.by + y
			if xx < 0 || xx >= 820 || yy < 0 || yy >= 740 { continue }
			alpha := int(glyph.pixels[y * glyph.width + x])
			for channel in 0 .. 3 {
				at := (yy * 820 + xx) * 3 + channel
				rgb[at] = u8((shade * alpha + int(rgb[at]) * (255 - alpha) + 127) / 255)
			}
		}
	}
}

pub fn preview(atlas Atlas, path string) ! {
	mut pixels := []u8{len: 820 * 740 * 3, init: u8(250)}
	labels := atlas.faces['small_1x'] or { return error('preview label face missing') }
	for column, scale in [1, 2] {
		mut y := 18
		for name in ['small', 'ui', 'bold', 'clock', 'large', 'large_bold', 'display', 'mono'] {
			face := atlas.faces[name + '_' + scale.str() + 'x'] or { return error('preview face missing') }
			mut pen := 20 + column * 400
			for point in (name + ' ' + face.size.str() + 'px / ' + scale.str() + 'x').runes() {
				glyph := labels.glyphs[int(point)] or { continue }
				paint(mut pixels, glyph, pen, y, 102)
				pen += glyph.advance
			}
			pen = 20 + column * 400
			for point in '中文（简体）'.runes() {
				glyph := face.glyphs[int(point)] or { continue }
				paint(mut pixels, glyph, pen, y + 18, 21)
				pen += glyph.advance
			}
			y += 90
		}
	}
	mut rows := []u8{len: 740 * (1 + 820 * 3)}
	for row in 0 .. 740 {
		copy(mut rows[row * (1 + 820 * 3) + 1..(row + 1) * (1 + 820 * 3)], pixels[row * 820 * 3..(row + 1) * 820 * 3])
	}
	mut info := []u8{len: 13}
	binary.big_endian_put_u32(mut info[..4], 820)
	binary.big_endian_put_u32(mut info[4..8], 740)
	info[8], info[9] = 8, 2
	mut png := [u8(137), `P`, `N`, `G`, 13, 10, 26, 10]
	for chunk in [png_chunk('IHDR', info), png_chunk('IDAT', zlib.compress(rows)!),
		png_chunk('IEND', [])] {
		png << chunk
	}
	os.write_file_array(path, png)!
}
