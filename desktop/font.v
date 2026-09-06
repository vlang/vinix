// Text rendering. The faces in font_data.v are 8-bit coverage atlases, so a
// glyph is drawn by blending its coverage with the run's color — the same
// antialiasing a desktop toolkit would give, without a rasteriser on the
// target.
module main

import encoding.base64

enum Face {
	small = 0
	ui    = 1
	bold  = 2
	clock = 3
}

// Glyph positions are relative to the top left of the line box, which is where
// a run is placed, so drawing needs no baseline arithmetic.
struct Glyph {
	width   int
	height  int
	bearing_x int
	bearing_y int
	advance int
	offset  int // into FontFace.pixels
}

struct FontFace {
mut:
	ascent      int
	descent     int
	line_height int
	glyphs      []Glyph
	pixels      []u8
}

const glyph_header_size = 5

fn load_face(data FaceBlob) FontFace {
	raw := base64.decode(data.parts.join(''))
	count := font_last_char - font_first_char + 1
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

// glyph_for maps a byte to its entry. Anything outside the baked range is
// drawn as a space rather than as a missing-glyph box, so an unexpected
// character costs a gap and not a broken layout.
@[inline]
fn (f &FontFace) glyph_for(ch u8) Glyph {
	if ch < u8(font_first_char) || ch > u8(font_last_char) {
		return f.glyphs[0]
	}
	return f.glyphs[int(ch) - font_first_char]
}

fn (f &FontFace) text_width(text string) int {
	mut width := 0
	for i := 0; i < text.len; i++ {
		width += f.glyph_for(text[i]).advance
	}
	return width
}

// truncate fits a string into `limit` pixels, ending it with an ellipsis when
// it does not fit. Window titles are user text of any length and the taskbar
// gives them a fixed slot, so something has to give.
fn (f &FontFace) truncate(text string, limit int) string {
	if f.text_width(text) <= limit {
		return text
	}
	ellipsis := '...'
	tail := f.text_width(ellipsis)
	mut width := 0
	mut cut := 0
	for i := 0; i < text.len; i++ {
		advance := f.glyph_for(text[i]).advance
		if width + advance + tail > limit {
			break
		}
		width += advance
		cut = i + 1
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
	for i := 0; i < text.len; i++ {
		glyph := face.glyph_for(text[i])
		if glyph.width > 0 && glyph.height > 0 {
			c.blit_glyph(face, glyph, pen + glyph.bearing_x, y + glyph.bearing_y, color)
		}
		pen += glyph.advance
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
		dst := py * c.stride
		for col := 0; col < glyph.width; col++ {
			px := x + col
			if px < 0 || px >= c.width {
				continue
			}
			coverage := u32(face.pixels[src + col])
			if coverage == 0 {
				continue
			}
			unsafe {
				c.pixels[dst + px] = blend(c.pixels[dst + px], color, coverage)
			}
		}
	}
}

fn (mut c Canvas) draw_text_centered(face &FontFace, x int, y int, w int, text string, color u32) {
	c.draw_text(face, x + (w - face.text_width(text)) / 2, y, text, color)
}

fn (mut c Canvas) draw_text_right(face &FontFace, right int, y int, text string, color u32) {
	c.draw_text(face, right - face.text_width(text), y, text, color)
}
