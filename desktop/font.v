// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Text rendering. The faces in font_data.v are 8-bit coverage atlases, so a
// glyph is drawn by blending its coverage with the run's color — the same
// antialiasing a desktop toolkit would give, without a rasteriser on the
// target.
//
// Runs are decoded as UTF-8 and looked up by code point. The atlases carry
// printable ASCII plus the supplemental runes in font_extra_runes: the Latin-1
// and Russian letters the keyboard layouts type, and signs such as the real
// division and plus-minus that label ui2's calculator keys.
module main

import encoding.base64

// Glyph positions are relative to the top left of the line box, which is where
// a run is placed, so drawing needs no baseline arithmetic.
struct Glyph {
	width     int
	height    int
	bearing_x int
	bearing_y int
	advance   int
	offset    int // into FontFace.pixels
}

struct FontFace {
mut:
	// What the face was baked at, which is how a text style picks between them.
	bold         bool
	mono         bool
	size         int
	raster_scale int
	ascent       int
	descent      int
	line_height  int
	glyphs       []Glyph
	pixels       []u8
}

const glyph_header_size = 5

fn load_face(data FaceBlob) FontFace {
	encoded := data.parts.join('')
	raw := base64.decode(encoded)
	unsafe { encoded.free() }
	count := font_last_char - font_first_char + 1 + font_extra_runes.len
	header_bytes := count * glyph_header_size

	mut glyphs := []Glyph{cap: count}
	// Coverage is read where it was decoded, just past the metrics header,
	// rather than from a copy that would leave the decoded blob behind.
	mut offset := header_bytes
	for i := 0; i < count; i++ {
		base := i * glyph_header_size
		width := int(raw[base])
		height := int(raw[base + 1])
		glyphs << Glyph{
			width:     width
			height:    height
			bearing_x: int(i8(raw[base + 2]))
			bearing_y: int(raw[base + 3])
			advance:   int(raw[base + 4])
			offset:    offset
		}
		offset += width * height
	}

	return FontFace{
		bold:         data.bold
		mono:         data.mono
		size:         data.size
		raster_scale: data.raster_scale
		ascent:       data.ascent
		descent:      data.descent
		line_height:  data.ascent + data.descent
		glyphs:       glyphs
		pixels:       raw
	}
}

fn load_fonts() []FontFace {
	mut faces := []FontFace{cap: font_blobs.len}
	for blob in font_blobs {
		faces << load_face(blob)
	}
	return faces
}

// load_fonts_for_scale loads only the faces rasterised for one display scale,
// which is all face_for picks from while that scale is in use. The 2x faces
// are most of the atlas data and a 100% desktop never draws with them.
fn load_fonts_for_scale(scale int) []FontFace {
	mut faces := []FontFace{cap: font_blobs.len}
	for blob in font_blobs {
		if blob.raster_scale == scale {
			faces << load_face(blob)
		}
	}
	if faces.len == 0 {
		unsafe { faces.free() }
		return load_fonts()
	}
	return faces
}

fn free_fonts(mut faces []FontFace) {
	for face in faces {
		unsafe {
			face.glyphs.free()
			face.pixels.free()
		}
	}
	unsafe { faces.free() }
	faces = []FontFace{}
}

// next_rune decodes one UTF-8 sequence and reports how many bytes it took. A
// byte that starts no valid sequence is returned as itself and consumed, so
// malformed input degrades into visible nonsense rather than into a loop that
// never advances.
@[inline]
fn next_rune(text string, index int) (u32, int) {
	first := text[index]
	if first < 0x80 {
		return u32(first), 1
	}
	if first & 0xe0 == 0xc0 && index + 1 < text.len {
		return u32(first & 0x1f) << 6 | u32(text[index + 1] & 0x3f), 2
	}
	if first & 0xf0 == 0xe0 && index + 2 < text.len {
		return u32(first & 0x0f) << 12 | u32(text[index + 1] & 0x3f) << 6 | u32(text[index + 2] & 0x3f), 3
	}
	if first & 0xf8 == 0xf0 && index + 3 < text.len {
		return u32(first & 0x07) << 18 | u32(text[index + 1] & 0x3f) << 12 | u32(text[index + 2] & 0x3f) << 6 | u32(text[index + 3] & 0x3f), 4
	}
	return u32(first), 1
}

// glyph_for maps a code point to its slot. Anything the atlases do not carry
// is drawn as a space rather than as a missing-glyph box, so an unexpected
// character costs a gap and not a broken layout. The supplemental block is
// ascending, so a binary search finds a slot without carrying a map.
@[inline]
fn (f &FontFace) glyph_for(code_point u32) Glyph {
	if code_point >= u32(font_first_char) && code_point <= u32(font_last_char) {
		return f.glyphs[int(code_point) - font_first_char]
	}
	ascii_count := font_last_char - font_first_char + 1
	mut low := 0
	mut high := font_extra_runes.len
	for low < high {
		middle := (low + high) / 2
		extra := font_extra_runes[middle]
		if extra == code_point {
			return f.glyphs[ascii_count + middle]
		}
		if extra < code_point {
			low = middle + 1
		} else {
			high = middle
		}
	}
	return f.glyphs[0]
}

fn (f &FontFace) text_width(text string) int {
	mut width := 0
	mut i := 0
	for i < text.len {
		code_point, size := next_rune(text, i)
		width += f.glyph_for(code_point).advance / f.raster_scale
		i += size
	}
	return width
}

// truncate fits a string into `limit` pixels, ending it with an ellipsis when
// it does not. Window titles are user text of any length and the taskbar gives
// them a fixed slot, so something has to give. The cut lands on a rune
// boundary because the scan advances one whole sequence at a time.
fn (f &FontFace) truncate(text string, limit int) (string, bool) {
	if f.text_width(text) <= limit {
		return text, false
	}
	ellipsis := '...'
	tail := f.text_width(ellipsis)
	mut width := 0
	mut cut := 0
	mut i := 0
	for i < text.len {
		code_point, size := next_rune(text, i)
		advance := f.glyph_for(code_point).advance / f.raster_scale
		if width + advance + tail > limit {
			break
		}
		width += advance
		i += size
		cut = i
	}
	if cut == 0 {
		return ellipsis, false
	}
	prefix := text[..cut]
	truncated := prefix + ellipsis
	unsafe { prefix.free() }
	return truncated, true
}

// draw_text places the run's line box at (x, y) and returns the pen position
// it ended at.
fn (mut c Canvas) draw_text(face &FontFace, x int, y int, text string, color u32) int {
	mut pen := x * c.scale
	mut i := 0
	for i < text.len {
		code_point, size := next_rune(text, i)
		glyph := face.glyph_for(code_point)
		if glyph.width > 0 && glyph.height > 0 {
			c.blit_glyph(face, glyph, pen + glyph.bearing_x, y * c.scale + glyph.bearing_y, color)
		}
		pen += glyph.advance
		i += size
	}
	return x + face.text_width(text)
}

fn (mut c Canvas) blit_glyph(face &FontFace, glyph Glyph, x int, y int, color u32) {
	for row := 0; row < glyph.height; row++ {
		py := y + row
		if py < 0 || py >= c.physical_height {
			continue
		}
		src := glyph.offset + row * glyph.width
		for col := 0; col < glyph.width; col++ {
			px := x + col
			if px < 0 || px >= c.physical_width {
				continue
			}
			coverage := u32(face.pixels[src + col])
			if coverage == 0 {
				continue
			}
			c.blend_physical_pixel(px, py, color, coverage)
		}
	}
}

fn (mut c Canvas) draw_text_centered(face &FontFace, x int, y int, w int, text string, color u32) {
	c.draw_text(face, x + (w - face.text_width(text)) / 2, y, text, color)
}

fn (mut c Canvas) draw_text_right(face &FontFace, right int, y int, text string, color u32) {
	c.draw_text(face, right - face.text_width(text), y, text, color)
}
