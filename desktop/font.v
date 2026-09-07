// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Text rendering. The faces in font_data.v are 8-bit coverage atlases, so a
// glyph is drawn by blending its coverage with the run's color — the same
// antialiasing a desktop toolkit would give, without a rasteriser on the
// target.
//
// Runs are decoded as UTF-8 and looked up by code point. The atlases carry
// printable ASCII plus the handful of supplemental runes in font_extra_runes,
// which is what lets an application like ui2's calculator, whose keys are
// labelled with the real division and plus-minus signs, come out right.
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
	bold        bool
	mono        bool
	size        int
	ascent      int
	descent     int
	line_height int
	glyphs      []Glyph
	pixels      []u8
}

const glyph_header_size = 5

fn load_face(data FaceBlob) FontFace {
	raw := base64.decode(data.parts.join(''))
	count := font_last_char - font_first_char + 1 + font_extra_runes.len
	header_bytes := count * glyph_header_size

	mut glyphs := []Glyph{cap: count}
	mut offset := 0
	for i := 0; i < count; i++ {
		base := i * glyph_header_size
		width := int(raw[base])
		height := int(raw[base + 1])
		glyphs << Glyph{
			width: width
			height: height
			bearing_x: int(i8(raw[base + 2]))
			bearing_y: int(raw[base + 3])
			advance: int(raw[base + 4])
			offset: offset
		}
		offset += width * height
	}

	return FontFace{
		bold: data.bold
		mono: data.mono
		size: data.size
		ascent: data.ascent
		descent: data.descent
		line_height: data.ascent + data.descent
		glyphs: glyphs
		pixels: raw[header_bytes..].clone()
	}
}

fn load_fonts() []FontFace {
	mut faces := []FontFace{cap: font_blobs.len}
	for blob in font_blobs {
		faces << load_face(blob)
	}
	return faces
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
// short enough that scanning it beats carrying a map.
@[inline]
fn (f &FontFace) glyph_for(code_point u32) Glyph {
	if code_point >= u32(font_first_char) && code_point <= u32(font_last_char) {
		return f.glyphs[int(code_point) - font_first_char]
	}
	ascii_count := font_last_char - font_first_char + 1
	for i, extra in font_extra_runes {
		if extra == code_point {
			return f.glyphs[ascii_count + i]
		}
	}
	return f.glyphs[0]
}

fn (f &FontFace) text_width(text string) int {
	mut width := 0
	mut i := 0
	for i < text.len {
		code_point, size := next_rune(text, i)
		width += f.glyph_for(code_point).advance
		i += size
	}
	return width
}

// truncate fits a string into `limit` pixels, ending it with an ellipsis when
// it does not. Window titles are user text of any length and the taskbar gives
// them a fixed slot, so something has to give. The cut lands on a rune
// boundary because the scan advances one whole sequence at a time.
fn (f &FontFace) truncate(text string, limit int) string {
	if f.text_width(text) <= limit {
		return text
	}
	ellipsis := '...'
	tail := f.text_width(ellipsis)
	mut width := 0
	mut cut := 0
	mut i := 0
	for i < text.len {
		code_point, size := next_rune(text, i)
		advance := f.glyph_for(code_point).advance
		if width + advance + tail > limit {
			break
		}
		width += advance
		i += size
		cut = i
	}
	if cut == 0 {
		return ellipsis
	}
	return text[..cut] + ellipsis
}

// draw_text places the run's line box at (x, y) and returns the pen position
// it ended at.
fn (mut c Canvas) draw_text(face &FontFace, x int, y int, text string, color u32) int {
	mut pen := x
	mut i := 0
	for i < text.len {
		code_point, size := next_rune(text, i)
		glyph := face.glyph_for(code_point)
		if glyph.width > 0 && glyph.height > 0 {
			c.blit_glyph(face, glyph, pen + glyph.bearing_x, y + glyph.bearing_y, color)
		}
		pen += glyph.advance
		i += size
	}
	return pen
}

fn (mut c Canvas) blit_glyph(face &FontFace, glyph Glyph, x int, y int, color u32) {
	for row := 0; row < glyph.height; row++ {
		py := y + row
		if py < 0 || py >= c.height {
			continue
		}
		src := glyph.offset + row * glyph.width
		for col := 0; col < glyph.width; col++ {
			px := x + col
			if px < 0 || px >= c.width {
				continue
			}
			coverage := u32(face.pixels[src + col])
			if coverage == 0 {
				continue
			}
			c.blend_pixel(px, py, color, coverage)
		}
	}
}

fn (mut c Canvas) draw_text_centered(face &FontFace, x int, y int, w int, text string, color u32) {
	c.draw_text(face, x + (w - face.text_width(text)) / 2, y, text, color)
}

fn (mut c Canvas) draw_text_right(face &FontFace, right int, y int, text string, color u32) {
	c.draw_text(face, right - face.text_width(text), y, text, color)
}
