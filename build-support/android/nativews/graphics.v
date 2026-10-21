// SPDX-License-Identifier: GPL-2.0-or-later
// Software Android Canvas for the native WS surface. stb is used only as a
// TrueType rasterizer; layout, clipping and composition are implemented in V.
@[translated]
module atlframework

#define STB_TRUETYPE_IMPLEMENTATION
#define STBTT_STATIC
#define FONTSTASH_MALLOC malloc
#define FONTSTASH_FREE free
#include "stb_truetype.h"
#include <math.h>

struct C.stbtt_fontinfo {}

fn C.stbtt_InitFont(voidptr, &u8, i32) i32
fn C.stbtt_ScaleForPixelHeight(voidptr, f32) f32
fn C.stbtt_GetCodepointHMetrics(voidptr, i32, &i32, &i32)
fn C.stbtt_GetCodepointBitmap(voidptr, f32, f32, i32, &i32, &i32, &i32, &i32) &u8
fn C.stbtt_FreeBitmap(voidptr, voidptr)
fn C.lseek(i32, i64, i32) i64
fn C.floorf(f32) f32
fn C.sqrtf(f32) f32

struct WsTransform {
mut:
	x      f32
	y      f32
	sx     f32 = 1
	sy     f32 = 1
	left   i32
	top    i32
	right  i32
	bottom i32
}

struct WsPaint {
mut:
	color        u32 = 0xff000000
	size         f32 = 16
	stroke       f32 = 1
	style        i32
	align        i32
	cap          i32
	join_        i32
	filter_mode  i32
	filter_color u32
}

__global ws_font voidptr
__global ws_font_data &u8

fn ws_font_init(root &char) bool {
	unsafe {
		path := &char(C.alloca(8192))
		C.snprintf(path, 8192, c'%s/usr/share/fonts/dejavu/DejaVuSans.ttf', root)
		fd := C.open(path, 0)
		if fd < 0 {
			C.puts(c'ANDROID-WS-FAIL DejaVuSans font missing')
			return false
		}
		length := C.lseek(fd, 0, 2)
		C.lseek(fd, 0, 0)
		if length <= 0 || length > 64 * 1024 * 1024 {
			C.close(fd)
			return false
		}
		ws_font_data = &u8(C.malloc(usize(length)))
		mut used := i64(0)
		for used < length {
			count := C.read(fd, &ws_font_data[used], usize(length - used))
			if count <= 0 {
				C.close(fd)
				return false
			}
			used += count
		}
		C.close(fd)
		ws_font = C.calloc(1, sizeof(C.stbtt_fontinfo))
		return C.stbtt_InitFont(ws_font, ws_font_data, 0) != 0
	}
}

fn ws_blend(x i32, y i32, color u32, coverage u32) {
	unsafe {
		if x < ws.transform.left || y < ws.transform.top || x >= ws.transform.right || y >= ws.transform.bottom || x < 0 || y < 0 || x >= ws.width || y >= ws.height {
			return
		}
		alpha := (color >> 24) * coverage / 255
		if alpha == 0 { return }
		target := &ws.pixels[y * ws.width + x]
		before := *target
		r := (((color >> 16) & 255) * alpha + ((before >> 16) & 255) * (255 - alpha)) / 255
		g := (((color >> 8) & 255) * alpha + ((before >> 8) & 255) * (255 - alpha)) / 255
		b := ((color & 255) * alpha + (before & 255) * (255 - alpha)) / 255
		*target = 0xff000000 | (r << 16) | (g << 8) | b
	}
}

fn ws_rect(left f32, top f32, right f32, bottom f32, color u32) {
	x0 := i32(left * ws.transform.sx + ws.transform.x)
	y0 := i32(top * ws.transform.sy + ws.transform.y)
	x1 := i32(right * ws.transform.sx + ws.transform.x)
	y1 := i32(bottom * ws.transform.sy + ws.transform.y)
	for y := if y0 < ws.transform.top { ws.transform.top } else { y0 }; y < y1 && y < ws.transform.bottom; y++ {
		for x := if x0 < ws.transform.left { ws.transform.left } else { x0 }; x < x1 && x < ws.transform.right; x++ {
			ws_blend(x, y, color, 255)
		}
	}
}

fn ws_codepoint(text &u8, length usize, position &usize) i32 {
	unsafe {
		c := text[*position]
		(*position)++
		if c < 128 { return i32(c) }
		count := if c & 0xe0 == 0xc0 {
			1
		} else if c & 0xf0 == 0xe0 {
			2
		} else {
			3
		}
		mut result := i32(c & if count == 1 {
			u8(31)
		} else if count == 2 {
			u8(15)
		} else {
			u8(7)
		})
		for j := 0; j < count; j++ {
			if *position >= length { return 0xfffd }
			result = (result << 6) | i32(text[*position] & 63)
			(*position)++
		}
		return result
	}
}

fn ws_text_width(text &char, size f32) f32 {
	if ws_font == unsafe { nil } { return 0 }
	scale := C.stbtt_ScaleForPixelHeight(ws_font, size)
	length := C.strlen(text)
	mut pos := usize(0)
	mut width := f32(0)
	for pos < length {
		code := ws_codepoint(unsafe { &u8(text) }, length, &pos)
		mut advance := i32(0)
		mut bearing := i32(0)
		C.stbtt_GetCodepointHMetrics(ws_font, code, &advance, &bearing)
		width += f32(advance) * scale
	}
	return width
}

fn ws_text(text &char, x f32, baseline f32, size f32, color u32) {
	if ws_font == unsafe { nil } { return }
	scale := C.stbtt_ScaleForPixelHeight(ws_font, size * ws.transform.sy)
	mut position := usize(0)
	length := C.strlen(text)
	mut pen := x * ws.transform.sx + ws.transform.x
	mut line := baseline * ws.transform.sy + ws.transform.y
	for position < length {
		code := ws_codepoint(unsafe { &u8(text) }, length, &position)
		if code == 10 {
			pen = x * ws.transform.sx + ws.transform.x
			line += size * 1.25
			continue
		}
		mut width := i32(0)
		mut height := i32(0)
		mut xo := i32(0)
		mut yo := i32(0)
		bitmap := C.stbtt_GetCodepointBitmap(ws_font, scale, scale, code, &width, &height, &xo, &yo)
		for row := i32(0); row < height; row++ {
			for column := i32(0); column < width; column++ {
				unsafe { ws_blend(i32(pen) + xo + column, i32(line) + yo + row, color, u32(bitmap[row * width + column])) }
			}
		}
		C.stbtt_FreeBitmap(bitmap, unsafe { nil })
		mut advance := i32(0)
		mut bearing := i32(0)
		C.stbtt_GetCodepointHMetrics(ws_font, code, &advance, &bearing)
		pen += f32(advance) * scale
	}
}

fn ws_paint_new() i64 {
	unsafe {
		paint := &WsPaint(C.malloc(sizeof(WsPaint)))
		*paint = WsPaint{}
		return i64(paint)
	}
}

fn ws_paint_clone(pointer i64) i64 {
	paint := ws_paint_new()
	C.memcpy(voidptr(paint), voidptr(pointer), sizeof(WsPaint))
	return paint
}

fn ws_bounds(e voidptr, pointer i64, text voidptr, bounds voidptr) {
	unsafe {
		paint := &WsPaint(pointer)
		chars := ws_utf(e, text)
		put_int(e, bounds, c'android/graphics/Rect', c'left', 0)
		put_int(e, bounds, c'android/graphics/Rect', c'top', -i32(paint.size * 0.8))
		put_int(e, bounds, c'android/graphics/Rect', c'right', i32(ws_text_width(chars, paint.size)))
		put_int(e, bounds, c'android/graphics/Rect', c'bottom', i32(paint.size * 0.2))
		ws_release(e, text, chars)
	}
}

fn ws_canvas_rect(left f32, top f32, right f32, bottom f32, pointer i64) {
	unsafe {
		paint := &WsPaint(pointer)
		if paint.style != 1 {
			ws_rect(left, top, right, bottom, paint.color)
		} else {
			ws_rect(left, top, right, top + paint.stroke, paint.color)
			ws_rect(left, bottom - paint.stroke, right, bottom, paint.color)
			ws_rect(left, top, left + paint.stroke, bottom, paint.color)
			ws_rect(right - paint.stroke, top, right, bottom, paint.color)
		}
	}
}

fn ws_round_inset(y f32, top f32, bottom f32, rx f32, ry f32) f32 {
	if rx <= 0 || ry <= 0 { return 0 }
	distance := if y < top + ry {
		(top + ry - y) / ry
	} else if y > bottom - ry {
		(y - bottom + ry) / ry
	} else {
		f32(0)
	}
	if distance >= 1 { return rx }
	return rx * (1 - C.sqrtf(1 - distance * distance))
}

fn ws_canvas_round_rect(left f32, top f32, right f32, bottom f32, radius_x f32, radius_y f32, pointer i64) {
	unsafe {
		if right <= left || bottom <= top { return }
		paint := &WsPaint(pointer)
		rx := if radius_x > (right - left) / 2 { (right - left) / 2 } else { radius_x }
		ry := if radius_y > (bottom - top) / 2 { (bottom - top) / 2 } else { radius_y }
		for row := i32(C.floorf(top)); f32(row) < bottom; row++ {
			y := f32(row) + 0.5
			inset := ws_round_inset(y, top, bottom, rx, ry)
			if paint.style != 1 || y < top + paint.stroke || y >= bottom - paint.stroke {
				ws_rect(left + inset, f32(row), right - inset, f32(row + 1), paint.color)
			} else {
				inner := ws_round_inset(y, top + paint.stroke, bottom - paint.stroke, rx - paint.stroke, ry - paint.stroke)
				ws_rect(left + inset, f32(row), left + paint.stroke + inner, f32(row + 1), paint.color)
				ws_rect(right - paint.stroke - inner, f32(row), right - inset, f32(row + 1), paint.color)
			}
		}
	}
}

fn ws_canvas_text(e voidptr, text voidptr, x f32, y f32, pointer i64) {
	unsafe {
		paint := &WsPaint(pointer)
		chars := ws_utf(e, text)
		width := ws_text_width(chars, paint.size)
		start := if paint.align == 1 {
			x - width / 2
		} else if paint.align == 2 {
			x - width
		} else {
			x
		}
		ws_text(chars, start, y, paint.size, paint.color)
		ws_release(e, text, chars)
	}
}

fn ws_save() {
	if ws.save_count >= 64 { return }
	unsafe { ws.transforms[ws.save_count] = ws.transform }
	ws.save_count++
}

fn ws_restore() {
	if ws.save_count > 0 {
		ws.save_count--
		unsafe { ws.transform = ws.transforms[ws.save_count] }
	}
}

fn ws_translate(x f32, y f32) {
	ws.transform.x += x * ws.transform.sx
	ws.transform.y += y * ws.transform.sy
}

fn ws_clip(left f32, top f32, right f32, bottom f32) {
	l, t, r, b := i32(left * ws.transform.sx + ws.transform.x), i32(top * ws.transform.sy + ws.transform.y), i32(right * ws.transform.sx + ws.transform.x), i32(bottom * ws.transform.sy + ws.transform.y)
	if l > ws.transform.left { ws.transform.left = l }
	if t > ws.transform.top { ws.transform.top = t }
	if r < ws.transform.right { ws.transform.right = r }
	if b < ws.transform.bottom { ws.transform.bottom = b }
}

fn ws_canvas_line(x0 f32, y0 f32, x1 f32, y1 f32, pointer i64) {
	unsafe {
		paint := &WsPaint(pointer)
		dx, dy := x1 - x0, y1 - y0
		ax, ay := if dx < 0 { -dx } else { dx }, if dy < 0 { -dy } else { dy }
		steps := i32(if ax > ay { ax } else { ay }) + 1
		for i := i32(0); i <= steps; i++ {
			x, y := x0 + dx * f32(i) / f32(steps), y0 + dy * f32(i) / f32(steps)
			ws_rect(x, y, x + paint.stroke, y + paint.stroke, paint.color)
		}
	}
}
