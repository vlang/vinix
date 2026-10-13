// SPDX-License-Identifier: GPL-2.0-or-later
module fontnative

import math

$if !font_sdk_custom ? {
	#pkgconfig freetype2
}

#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_GLYPH_H

@[typedef]
struct C.FT_FaceRec {
	glyph &C.FT_GlyphSlotRec
	size  &C.FT_SizeRec
}

@[typedef]
struct C.FT_GlyphSlotRec {
	bitmap      C.FT_Bitmap
	bitmap_left i32
	bitmap_top  i32
	metrics     C.FT_Glyph_Metrics
}

@[typedef]
struct C.FT_Glyph_Metrics {
	horiAdvance i64
}

@[typedef]
struct C.FT_SizeRec {
	metrics C.FT_Size_Metrics
}

@[typedef]
struct C.FT_Size_Metrics {
	ascender  i64
	descender i64
}

@[typedef]
struct C.FT_Bitmap {
	rows       u32
	width      u32
	pitch      i32
	buffer     &u8
	num_grays  u16
	pixel_mode u8
}

@[typedef]
struct C.FT_BBox {
mut:
	xMin i64
	xMax i64
	yMin i64
	yMax i64
}

@[typedef]
struct C.FT_Size_RequestRec {
	type           i32
	width          i64
	height         i64
	horiResolution u32
	vertResolution u32
}

fn C.FT_Init_FreeType(&voidptr) i32
fn C.FT_Done_FreeType(voidptr) i32
fn C.FT_New_Face(voidptr, &char, i64, &&C.FT_FaceRec) i32
fn C.FT_Done_Face(&C.FT_FaceRec) i32
fn C.FT_Request_Size(&C.FT_FaceRec, &C.FT_Size_RequestRec) i32
fn C.FT_Load_Glyph(&C.FT_FaceRec, u32, i32) i32
fn C.FT_Get_Char_Index(&C.FT_FaceRec, u64) u32
fn C.FT_Get_Glyph(&C.FT_GlyphSlotRec, &voidptr) i32
fn C.FT_Glyph_Get_CBox(voidptr, u32, &C.FT_BBox)
fn C.FT_Done_Glyph(voidptr)

pub struct Library {
mut:
	handle voidptr
}

pub struct Font {
mut:
	face &C.FT_FaceRec = unsafe { nil }
}

pub struct Glyph {
pub:
	width     int
	height    int
	bx        int
	by        int
	advance64 i64
	pixels    []u8
}

struct Positioned {
	index   u32
	x       int
	y       int
	advance i64
}

fn ft_check(code i32) ! { if code != 0 { return error('FreeType error ' + code.str()) } }

fn pixel(value i64) int { return int((value + 32) >> 6) }

pub fn library() !Library {
	mut handle := unsafe { nil }
	ft_check(C.FT_Init_FreeType(&handle))!
	return Library{handle}
}

pub fn (mut lib Library) close() {
	if lib.handle != unsafe { nil } {
		C.FT_Done_FreeType(lib.handle)
		lib.handle = unsafe { nil }
	}
}

pub fn (lib &Library) open(path string, size int) !Font {
	if lib.handle == unsafe { nil } || path.contains('\x00') || size <= 0 || size > 65535 {
		return error('invalid font path, size or library')
	}
	mut face := &C.FT_FaceRec(unsafe { nil })
	ft_check(C.FT_New_Face(lib.handle, path.str, 0, &face))!
	request := C.FT_Size_RequestRec{ type: 0, width: i64(size) * 64, height: i64(size) * 64 }
	ft_check(C.FT_Request_Size(face, &request)) or {
		C.FT_Done_Face(face)
		return err
	}
	return Font{face}
}

pub fn (mut font Font) close() {
	if font.face != unsafe { nil } {
		C.FT_Done_Face(font.face)
		font.face = unsafe { nil }
	}
}

pub fn (font &Font) metrics() ![]int {
	if font.face == unsafe { nil } { return error('font is closed') }
	return [pixel(font.face.size.metrics.ascender), -pixel(font.face.size.metrics.descender)]
}

fn (font &Font) positions(cp int) ![]Positioned {
	if font.face == unsafe { nil } || cp < 0 || cp > 0x10ffff {
		return error('invalid code point or closed font')
	}
	// The saved atlas keeps individual default-ignorable glyphs such as U+00AD.
	// Match its direct single-character FreeType layout and hinted advances.
	index := C.FT_Get_Char_Index(font.face, u64(cp))
	ft_check(C.FT_Load_Glyph(font.face, index, C.FT_LOAD_DEFAULT))!
	return [Positioned{index, 0, 0, font.face.glyph.metrics.horiAdvance}]
}

pub fn (font &Font) raster(cp int) !Glyph {
	positions := font.positions(cp)!
	mut xmin, xmax, ymin, ymax := 0, 0, 0, 0
	mut advance := i64(0)
	for entry in positions {
		advance += entry.advance
		xmax = math.max(xmax, pixel(advance))
		ft_check(C.FT_Load_Glyph(font.face, entry.index, C.FT_LOAD_DEFAULT))!
		mut glyph := unsafe { nil }
		ft_check(C.FT_Get_Glyph(font.face.glyph, &glyph))!
		mut box := C.FT_BBox{}
		C.FT_Glyph_Get_CBox(glyph, C.FT_GLYPH_BBOX_PIXELS, &box)
		C.FT_Done_Glyph(glyph)
		xmin = math.min(xmin, int(box.xMin) + entry.x)
		xmax = math.max(xmax, int(box.xMax) + entry.x)
		ymin = math.min(ymin, int(box.yMin) + entry.y)
		ymax = math.max(ymax, int(box.yMax) + entry.y)
	}
	width, height := xmax - xmin, ymax - ymin
	if width < 0 || height < 0 || width > 65535 || height > 65535 {
		return error('invalid glyph dimensions')
	}
	mut pixels := []u8{len: width * height}
	if width == 0 || height == 0 {
		return Glyph{width, height, xmin, font.metrics()![0] - ymax, advance, pixels}
	}
	mut render_x, render_y := 0, 0
	for entry in positions {
		ft_check(C.FT_Load_Glyph(font.face, entry.index, C.FT_LOAD_DEFAULT | C.FT_LOAD_RENDER))!
		render_x = math.min(render_x, int(font.face.glyph.bitmap_left) + entry.x)
		render_y = math.max(render_y, int(font.face.glyph.bitmap_top) + entry.y)
	}
	for entry in positions {
		ft_check(C.FT_Load_Glyph(font.face, entry.index, C.FT_LOAD_DEFAULT | C.FT_LOAD_RENDER))!
		bitmap := font.face.glyph.bitmap
		if bitmap.rows > 0 && bitmap.buffer == unsafe { nil } {
			return error('glyph bitmap is missing')
		}
		if bitmap.pixel_mode !in [C.FT_PIXEL_MODE_GRAY, C.FT_PIXEL_MODE_MONO, C.FT_PIXEL_MODE_GRAY2,
			C.FT_PIXEL_MODE_GRAY4] {
			return error('unsupported glyph bitmap format')
		}
		left := entry.x + int(font.face.glyph.bitmap_left) - render_x
		top := render_y - entry.y - int(font.face.glyph.bitmap_top)
		for row in 0 .. int(bitmap.rows) {
			for column in 0 .. int(bitmap.width) {
				x, y := left + column, top + row
				if x < 0 || y < 0 || x >= width || y >= height { continue }
				bits := if bitmap.pixel_mode == C.FT_PIXEL_MODE_MONO {
					1
				} else if bitmap.pixel_mode == C.FT_PIXEL_MODE_GRAY2 {
					2
				} else if bitmap.pixel_mode == C.FT_PIXEL_MODE_GRAY4 {
					4
				} else {
					8
				}
				byte := unsafe { bitmap.buffer[row * int(bitmap.pitch) + column * bits / 8] }
				mask := (1 << bits) - 1
				alpha := (int(byte) >> (8 - bits - (column * bits % 8))) & mask
				coverage := alpha * (255 / mask)
				old := int(pixels[y * width + x])
				product := old * (255 - coverage) + 128
				pixels[y * width + x] = u8(coverage + ((product + (product >> 8)) >> 8))
			}
		}
	}
	return Glyph{width, height, xmin, font.metrics()![0] - ymax, advance, pixels}
}
