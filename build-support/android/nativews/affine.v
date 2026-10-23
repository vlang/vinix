// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

struct WsClipQuad {
mut:
	x [4]f32
	y [4]f32
}

fn ws_affine_point(m WsTransform, x f32, y f32) (f32, f32) {
	return m.sx * x + m.kx * y + m.x, m.ky * x + m.sy * y + m.y
}

fn ws_affine_inverse(m WsTransform, x f32, y f32) (f32, f32, bool) {
	det := m.sx * m.sy - m.kx * m.ky
	if det == 0 { return 0, 0, false }
	xx, yy := x - m.x, y - m.y
	return (m.sy * xx - m.kx * yy) / det, (m.sx * yy - m.ky * xx) / det, true
}

fn ws_affine_bounds(m WsTransform, left f32, top f32, right f32, bottom f32) (i32, i32, i32, i32) {
	mut l, mut t, mut r, mut b := f32(1e30), f32(1e30), f32(-1e30), f32(-1e30)
	for i := 0; i < 4; i++ {
		x, y := ws_affine_point(m, if i == 0 || i == 3 { left } else { right }, if i < 2 { top } else { bottom })
		if x < l { l = x }
		if x > r { r = x }
		if y < t { t = y }
		if y > b { b = y }
	}
	// Clamp before converting to integers: SVG coordinates may be very large.
	return if l < f32(m.left) { m.left } else if l > f32(m.right) { m.right } else { i32(C.floorf(l)) },
		if t < f32(m.top) { m.top } else if t > f32(m.bottom) { m.bottom } else { i32(C.floorf(t)) },
		if r > f32(m.right) { m.right } else if r < f32(m.left) { m.left } else { i32(C.ceilf(r)) },
		if b > f32(m.bottom) { m.bottom } else if b < f32(m.top) { m.top } else { i32(C.ceilf(b)) }
}

fn ws_affine_clip(draw &WsDrawState, x f32, y f32) bool {
	unsafe {
		for index := i32(0); index < draw.transform.clip_count; index++ {
			quad := draw.clips[index]
			mut positive, mut negative := false, false
			for i := 0; i < 4; i++ {
				j := (i + 1) % 4
				cross := (quad.x[j] - quad.x[i]) * (y - quad.y[i]) - (quad.y[j] - quad.y[i]) * (x - quad.x[i])
				if cross == 0 && (i == 1 || i == 2) { return false }
				positive = positive || cross > 0
				negative = negative || cross < 0
			}
			if positive && negative { return false }
		}
	}
	return true
}

fn ws_scale(x f32, y f32) {
	mut draw := ws_draw_state()
	draw.transform.sx *= x
	draw.transform.ky *= x
	draw.transform.kx *= y
	draw.transform.sy *= y
}

fn ws_affine_text(text &char, x f32, baseline f32, size f32, color u32, info voidptr) {
	draw := ws_draw_state()
	scale := C.stbtt_ScaleForPixelHeight(info, size)
	mut position := usize(0)
	length := C.strlen(text)
	mut pen, mut line := x, baseline
	for position < length {
		code := ws_codepoint(unsafe { &u8(text) }, length, &position)
		if code == 10 { pen = x; line += size * 1.25; continue }
		mut width, mut height, mut xo, mut yo := i32(0), i32(0), i32(0), i32(0)
		bitmap := C.stbtt_GetCodepointBitmap(info, scale, scale, code, &width, &height, &xo, &yo)
		left, top := pen + f32(xo), line + f32(yo)
		l, t, r, b := ws_affine_bounds(draw.transform, left, top, left + f32(width), top + f32(height))
		for yy := t; yy < b; yy++ {
			for xx := l; xx < r; xx++ {
				px, py, valid := ws_affine_inverse(draw.transform, f32(xx) + 0.5, f32(yy) + 0.5)
				column, row := i32(C.floorf(px - left)), i32(C.floorf(py - top))
				if valid && column >= 0 && row >= 0 && column < width && row < height {
					unsafe { ws_blend(xx, yy, color, u32(bitmap[row * width + column])) }
				}
			}
		}
		C.stbtt_FreeBitmap(bitmap, unsafe { nil })
		mut advance, mut bearing := i32(0), i32(0)
		C.stbtt_GetCodepointHMetrics(info, code, &advance, &bearing)
		pen += f32(advance) * scale
	}
}
