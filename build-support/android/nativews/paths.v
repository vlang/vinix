// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

struct WsVertex {
	x    f32
	y    f32
	move bool
}

struct WsPath {
mut:
	points     &WsVertex
	count      i32
	capacity   i32
	references i32
	controls &WsVertex
	control_count i32
	control_capacity i32
}

struct WsCrossing {
	x         f32
	direction i32
}

fn ws_path_new() i64 {
	unsafe {
		path := &WsPath(C.calloc(1, sizeof(WsPath)))
		path.references = 1
		return i64(path)
	}
}

fn ws_path_unref(pointer i64) {
	unsafe {
		if pointer == 0 { return }
		path := &WsPath(pointer)
		path.references--
		if path.references == 0 {
			C.free(path.points)
			C.free(path.controls)
			C.free(path)
		}
	}
}

fn ws_path_ref(pointer i64) i64 {
	unsafe {
		if pointer != 0 { (&WsPath(pointer)).references++ }
		return pointer
	}
}

fn ws_path_point(pointer i64, x f32, y f32, move bool) {
	unsafe {
		path := &WsPath(pointer)
		if path.count == path.capacity {
			capacity := if path.capacity == 0 { i32(32) } else { path.capacity * 2 }
			path.points = &WsVertex(C.realloc(path.points, usize(capacity) * sizeof(WsVertex)))
			path.capacity = capacity
		}
		path.points[path.count] = WsVertex{x, y, move}
		path.count++
	}
}

fn ws_path_builder(pointer i64, builder i64) i64 {
	unsafe {
		result := if builder == 0 { ws_path_new() } else { builder }
		if pointer != 0 {
			path := &WsPath(pointer)
			for i := i32(0); i < path.count; i++ {
				p := path.points[i]
				ws_path_point(result, p.x, p.y, p.move)
			}
			for i := i32(0); i < path.control_count; i++ {
				p := path.controls[i]
				ws_path_control(result, p.x, p.y)
			}
			ws_path_unref(pointer)
		}
		return result
	}
}

fn ws_path_close(pointer i64) {
	unsafe {
		path := &WsPath(pointer)
		for i := path.count - 1; i >= 0; i-- {
			p := path.points[i]
			if p.move {
				ws_path_point(pointer, p.x, p.y, false)
				return
			}
		}
	}
}

fn ws_path_rect(pointer i64, left f32, top f32, right f32, bottom f32) {
	ws_path_point(pointer, left, top, true)
	ws_path_point(pointer, right, top, false)
	ws_path_point(pointer, right, bottom, false)
	ws_path_point(pointer, left, bottom, false)
	ws_path_point(pointer, left, top, false)
}

fn ws_path_round_rect(e voidptr, pointer i64, left f32, top f32, right f32, bottom f32, radii voidptr) {
	if ws_array_len(e, radii) < 8 {
		throw(e, c'java/lang/ArrayIndexOutOfBoundsException', c'Eight corner radii required')
		return
	}
	if right <= left || bottom <= top { return }
	unsafe {
		mut radius := [8]f32{}
		WsFloatRegion(slot(e, 205))(e, radii, 0, 8, &radius[0])
		for i := 0; i < 8; i++ {
			if radius[i] != radius[i] { return }
			if radius[i] < 0 { radius[i] = 0 }
		}
		// Preserve the relative corner sizes when adjacent radii overlap.
		mut factor := f32(1)
		for corner := 0; corner < 4; corner++ {
			a := corner * 2
			b := ((corner + 1) % 4) * 2
			vertical := corner % 2 == 1
			sum := radius[a + int(vertical)] + radius[b + int(vertical)]
			limit := if vertical { bottom - top } else { right - left }
			if sum > limit && limit / sum < factor { factor = limit / sum }
		}
		for i := 0; i < 8; i++ { radius[i] *= factor }
		for corner := 0; corner < 4; corner++ {
			rx, ry := radius[corner * 2], radius[corner * 2 + 1]
			cx := if corner == 0 || corner == 3 { left + rx } else { right - rx }
			cy := if corner < 2 { top + ry } else { bottom - ry }
			start := f32(corner * 90 + 180)
			for step := 0; step <= 8; step++ {
				angle := (start + f32(step) * 90 / 8) * 0.017453292519943295
				ws_path_point(pointer, cx + rx * C.cosf(angle), cy + ry * C.sinf(angle), corner == 0 && step == 0)
			}
		}
		ws_path_close(pointer)
	}
}

fn ws_draw_path(pointer i64, paint_pointer i64) {
	mut draw := ws_draw_state()
	unsafe {
		if pointer == 0 { return }
		path := &WsPath(pointer)
		paint := &WsPaint(paint_pointer)
		if paint.style != 0 {
			for i := i32(1); i < path.count; i++ {
				a, b := path.points[i - 1], path.points[i]
				if !b.move { ws_canvas_line(a.x, a.y, b.x, b.y, paint_pointer) }
			}
			return
		}
		// Scanline nonzero winding fill, clipped by the current Canvas state.
		crossings := &WsCrossing(C.malloc(usize(path.count + 1) * sizeof(WsCrossing)))
		defer { C.free(crossings) }
		for y := i32(0); y < draw.height; y++ {
			local_y := (f32(y) + 0.5 - draw.transform.y) / draw.transform.sy
			mut count := i32(0)
			for i := i32(1); i < path.count; i++ {
				a, b := path.points[i - 1], path.points[i]
				if b.move || !((a.y <= local_y && b.y > local_y) || (b.y <= local_y && a.y > local_y)) {
					continue
				}
				x := a.x + (local_y - a.y) * (b.x - a.x) / (b.y - a.y)
				crossings[count] = WsCrossing{x, if b.y > a.y { 1 } else { -1 }}
				count++
			}
			for i := i32(1); i < count; i++ {
				value := crossings[i]
				mut j := i
				for j > 0 && crossings[j - 1].x > value.x {
					crossings[j] = crossings[j - 1]
					j--
				}
				crossings[j] = value
			}
			mut winding := i32(0)
			for i := i32(0); i < count; i++ {
				if i > 0 && winding != 0 {
					left := i32(crossings[i - 1].x * draw.transform.sx + draw.transform.x)
					right := i32(crossings[i].x * draw.transform.sx + draw.transform.x)
					for x := left; x < right; x++ { ws_blend(x, y, paint.color, 255) }
				}
				winding += crossings[i].direction
			}
		}
	}
}
