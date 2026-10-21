// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

fn ws_path_last(pointer i64, output &f32) {
	unsafe {
		path := &WsPath(pointer)
		if path.count == 0 { ws_path_point(pointer, 0, 0, true) }
		last := path.points[path.count - 1]
		output[0] = last.x
		output[1] = last.y
	}
}

fn ws_path_line(pointer i64, x f32, y f32, relative bool, move bool) {
	unsafe {
		origin := &f32(C.alloca(2 * sizeof(f32)))
		ws_path_last(pointer, origin)
		ws_path_point(pointer, x + if relative { origin[0] } else { f32(0) },
			y + if relative { origin[1] } else { f32(0) }, move)
	}
}

fn ws_cubic_segment(pointer i64, x0 f32, y0 f32, x1 f32, y1 f32, x2 f32, y2 f32, x3 f32, y3 f32, depth i32) {
	ux, uy := 3 * x1 - 2 * x0 - x3, 3 * y1 - 2 * y0 - y3
	vx, vy := 3 * x2 - 2 * x3 - x0, 3 * y2 - 2 * y3 - y0
	flat_x := if ux * ux > vx * vx { ux * ux } else { vx * vx }
	flat_y := if uy * uy > vy * vy { uy * uy } else { vy * vy }
	if depth >= 10 || flat_x + flat_y <= 0.16 {
		ws_path_point(pointer, x3, y3, false)
		return
	}
	x01, y01 := (x0 + x1) / 2, (y0 + y1) / 2
	x12, y12 := (x1 + x2) / 2, (y1 + y2) / 2
	x23, y23 := (x2 + x3) / 2, (y2 + y3) / 2
	xa, ya := (x01 + x12) / 2, (y01 + y12) / 2
	xb, yb := (x12 + x23) / 2, (y12 + y23) / 2
	xm, ym := (xa + xb) / 2, (ya + yb) / 2
	ws_cubic_segment(pointer, x0, y0, x01, y01, xa, ya, xm, ym, depth + 1)
	ws_cubic_segment(pointer, xm, ym, xb, yb, x23, y23, x3, y3, depth + 1)
}

fn ws_path_cubic(pointer i64, x1 f32, y1 f32, x2 f32, y2 f32, x3 f32, y3 f32, relative bool) {
	unsafe {
		p := &f32(C.alloca(2 * sizeof(f32)))
		ws_path_last(pointer, p)
		dx, dy := if relative { p[0] } else { f32(0) }, if relative { p[1] } else { f32(0) }
		ws_cubic_segment(pointer, p[0], p[1], x1 + dx, y1 + dy, x2 + dx, y2 + dy, x3 + dx, y3 + dy, 0)
	}
}

fn ws_path_quad(pointer i64, x1 f32, y1 f32, x2 f32, y2 f32, relative bool) {
	unsafe {
		p := &f32(C.alloca(2 * sizeof(f32)))
		ws_path_last(pointer, p)
		dx, dy := if relative { p[0] } else { f32(0) }, if relative { p[1] } else { f32(0) }
		cx, cy, end_x, end_y := x1 + dx, y1 + dy, x2 + dx, y2 + dy
		ws_cubic_segment(pointer, p[0], p[1], p[0] + (cx - p[0]) * 2 / 3, p[1] + (cy - p[1]) * 2 / 3,
			end_x + (cx - end_x) * 2 / 3, end_y + (cy - end_y) * 2 / 3, end_x, end_y, 0)
	}
}

fn ws_path_add(pointer i64, source i64, matrix i64) {
	unsafe {
		if source == 0 { return }
		path := &WsPath(source)
		count := path.count
		mapped := &f32(C.alloca(2 * sizeof(f32)))
		for i := i32(0); i < count; i++ {
			point := path.points[i]
			ws_matrix_map_point(matrix, point.x, point.y, false, mapped)
			ws_path_point(pointer, mapped[0], mapped[1], point.move)
		}
	}
}

fn ws_path_transform(pointer i64, matrix i64) i64 {
	result := ws_path_new()
	ws_path_add(result, pointer, matrix)
	ws_path_unref(pointer)
	return result
}

fn ws_path_arc(pointer i64, left f32, top f32, right f32, bottom f32, start f32, sweep f32, move bool) {
	if right <= left || bottom <= top { return }
	size := if sweep > 360 {
		f32(360)
	} else if sweep < -360 {
		f32(-360)
	} else {
		sweep
	}
	steps := i32((if size < 0 { -size } else { size }) / 5) + 1
	rx, ry := (right - left) / 2, (bottom - top) / 2
	for i := i32(0); i <= steps; i++ {
		angle := (start + size * f32(i) / f32(steps)) * 0.017453292519943295
		ws_path_point(pointer, left + rx + rx * C.cosf(angle), top + ry + ry * C.sinf(angle),
			(i == 0 && move) || unsafe { (&WsPath(pointer)).count == 0 })
	}
}
