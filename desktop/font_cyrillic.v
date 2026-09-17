// SPDX-License-Identifier: GPL-2.0-or-later
// Compact Cyrillic fallback used by the framebuffer text renderer. The normal
// Latin/symbol faces remain the antialiased Roboto atlases in font_data.v;
// these 8x10 masks are expanded once, when each face is loaded, so Russian UI
// text works even on Vinix systems that have no runtime font rasteriser.
module main

const font_cyrillic_bitmap_width = 8
const font_cyrillic_bitmap_height = 10
const font_cyrillic_runes = [u32(0x0401), 0x0410, 0x0411, 0x0412, 0x0413, 0x0414, 0x0415,
	0x0416, 0x0417, 0x0418, 0x0419, 0x041a, 0x041b, 0x041c, 0x041d, 0x041e, 0x041f,
	0x0420, 0x0421, 0x0422, 0x0423, 0x0424, 0x0425, 0x0426, 0x0427, 0x0428, 0x0429,
	0x042a, 0x042b, 0x042c, 0x042d, 0x042e, 0x042f, 0x0430, 0x0431, 0x0432, 0x0433,
	0x0434, 0x0435, 0x0436, 0x0437, 0x0438, 0x0439, 0x043a, 0x043b, 0x043c, 0x043d,
	0x043e, 0x043f, 0x0440, 0x0441, 0x0442, 0x0443, 0x0444, 0x0445, 0x0446, 0x0447,
	0x0448, 0x0449, 0x044a, 0x044b, 0x044c, 0x044d, 0x044e, 0x044f, 0x0451]

// One 20-hex-character string per rune: ten rows, eight pixels per row.
// Generated from Roboto and thresholded to a tiny bitmap; keeping the fallback
// as masks rather than another large baked atlas adds the whole Russian
// alphabet for only a few kilobytes of source.
const font_cyrillic_patterns = [
	'28007c6040607840407c',
	'0018183c2c247e7ec2c3',
	'fcc080c0fcc6c6c6cefc',
	'fccec686fcfcc6c6cefc',
	'7e604040404040404040',
	'3e2626262662e6ff8181',
	'fcc0c080f8fcc0c0c0fc',
	'000000004b6a3c3c6acb',
	'7ce6860e3c0606c6ee7c',
	'c3c7c7cfdb9bf3e3e3c3',
	'3c1842464e4a52726262',
	'c6c6cc98f0f0d8ccc6c3',
	'003f33313131312161e1',
	'0000c3c3e7e7adb99999',
	'c3c3c3c3ffffc3c3c3c3',
	'3c66c3c3c3c3c3c3663c',
	'ffc3c3c3c3c3c3c3c3c3',
	'fccec6c686fcf080c0c0',
	'3c66c3c0c0c0c0c3663c',
	'ff181818181818181818',
	'00c36666243c18181070',
	'00187cfe9b9b9bde7c18',
	'004366341c183c3466c3',
	'464646464646667e0202',
	'c3c3c3c3c37f1b030303',
	'000000999999999999ff',
	'00939393939393ff0101',
	'0000f030303e3331333e',
	'0000818181f98d8d8df9',
	'c0c080c0fcc6c6c6cefc',
	'003c6643031f0343663c',
	'0000009eb3a1e1a1b39e',
	'3f634343633f3f2363c3',
	'7cfec3037ff3c3c3ff7b',
	'041c38607c664646663c',
	'feffc3c7fec7c3c3fffe',
	'fcfcc0c0c0c0c0c0c0c0',
	'3e3626262666ffffc381',
	'3c7ec3c3ffc0c0e27f3e',
	'00000000da5e3c7c5adb',
	'7cfec6063c0e06c6fe7c',
	'c3c7cfcfdbdbf3e3e3c3',
	'243c00464e4e5e766666',
	'00c6ccd8f0f0d8dcccc6',
	'00003f33333333337363',
	'000000c3c7e7efbf9b9b',
	'c3c3c3c3c3ffc3c3c3c3',
	'003c7ec3c3c3c3c37e3c',
	'ffffc3c3c3c3c3c3c3c3',
	'7c66464646667c404040',
	'3e7fc3c3c0c0c0c37f3c',
	'ffff1818181818181818',
	'6626243c3c1818183030',
	'08183c7e4a4a7e3c0818',
	'0066663c3c183c3c66e6',
	'cccccccccc84fcfe0606',
	'c3c3c3c3e37f03030303',
	'0000009b9b9b9b9b9bff',
	'00009393939393ff0101',
	'000000f030303e33333e',
	'0000008181c1f98dcdf9',
	'c0c0c0c0fecec3c3fefc',
	'3cfec3031f03c3c37e3c',
	'000000009e93f1b1939e',
	'003f7363637f3f336363',
	'24001c3e667e7e60763c',
]

@[inline]
fn font_hex_nibble(ch u8) u8 {
	return if ch >= `0` && ch <= `9` {
		ch - `0`
	} else if ch >= `a` && ch <= `f` {
		ch - `a` + 10
	} else {
		u8(0)
	}
}

@[inline]
fn font_cyrillic_row(pattern string, row int) u8 {
	offset := row * 2
	return font_hex_nibble(pattern[offset]) << 4 | font_hex_nibble(pattern[offset + 1])
}

// Append one scaled bitmap for every Russian letter to a loaded face. Advance
// widths stay in the same physical coordinate convention as the baked atlas.
fn append_cyrillic_glyphs(mut face FontFace, data FaceBlob) {
	logical_height := if data.size * 4 / 5 > 6 { data.size * 4 / 5 } else { 7 }
	logical_width := if logical_height * 7 / 10 > 4 { logical_height * 7 / 10 } else { 5 }
	width := logical_width * data.raster_scale
	height := logical_height * data.raster_scale
	bearing_y := if data.ascent > logical_height {
		(data.ascent - logical_height) * data.raster_scale
	} else {
		0
	}
	advance := (logical_width + 1) * data.raster_scale
	for index, pattern in font_cyrillic_patterns {
		offset := face.pixels.len
		for y := 0; y < height; y++ {
			source_y := y * font_cyrillic_bitmap_height / height
			row := font_cyrillic_row(pattern, source_y)
			for x := 0; x < width; x++ {
				source_x := x * font_cyrillic_bitmap_width / width
				mask := u8(1 << (font_cyrillic_bitmap_width - 1 - source_x))
				mut on := row & mask != 0
				// Bold faces get one physical pixel of horizontal weight, matching
				// the stronger Roboto face well enough at these small UI sizes.
				if data.bold && !on && source_x > 0 {
					on = row & u8(1 << (font_cyrillic_bitmap_width - source_x)) != 0
				}
				face.pixels << if on { u8(255) } else { u8(0) }
			}
		}
		face.glyphs << Glyph{
			width: width
			height: height
			bearing_x: 0
			bearing_y: bearing_y
			advance: advance
			offset: offset
		}
		_ = index
	}
}
