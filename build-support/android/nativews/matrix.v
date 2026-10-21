// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

struct WsMatrix {
mut:
	values [9]f32
}

type WsFloatRegion = fn (voidptr, voidptr, i32, i32, &f32)

fn C.sinf(f32) f32
fn C.cosf(f32) f32
fn C.fmodf(f32, f32) f32

fn ws_matrix_new(copy i64) i64 {
	unsafe {
		matrix := &WsMatrix(C.calloc(1, sizeof(WsMatrix)))
		if copy != 0 {
			C.memcpy(matrix, voidptr(copy), sizeof(WsMatrix))
		} else {
			matrix.values[0] = 1
			matrix.values[4] = 1
			matrix.values[8] = 1
		}
		return i64(matrix)
	}
}

fn ws_matrix_reset(pointer i64) {
	unsafe {
		matrix := &WsMatrix(pointer)
		C.memset(matrix, 0, sizeof(WsMatrix))
		matrix.values[0] = 1
		matrix.values[4] = 1
		matrix.values[8] = 1
	}
}

fn ws_matrix_identity(pointer i64) u8 {
	unsafe {
		matrix := &WsMatrix(pointer)
		for i := 0; i < 9; i++ {
			if matrix.values[i] != if i == 0 || i == 4 || i == 8 { f32(1) } else { f32(0) } {
				return 0
			}
		}
		return 1
	}
}

fn ws_matrix_values(e voidptr, pointer i64, array voidptr, put bool) {
	if ws_array_len(e, array) < 9 { return }
	unsafe {
		matrix := &WsMatrix(pointer)
		WsFloatRegion(slot(e, if put { 213 } else { 205 }))(e, array, 0, 9, &matrix.values[0])
	}
}

fn ws_matrix_concat(output i64, first i64, second i64) u8 {
	unsafe {
		a, b, c := &WsMatrix(first), &WsMatrix(second), &WsMatrix(output)
		mut values := [9]f32{}
		for row := 0; row < 3; row++ {
			for column := 0; column < 3; column++ {
				mut value := f32(0)
				for k := 0; k < 3; k++ { value += a.values[row * 3 + k] * b.values[k * 3 + column] }
				values[row * 3 + column] = value
			}
		}
		C.memcpy(c, &values[0], sizeof(WsMatrix))
		return 1
	}
}

fn ws_matrix_transform(pointer i64, kind i32, x f32, y f32, post bool, reset bool) u8 {
	unsafe {
		transform := &WsMatrix(C.alloca(sizeof(WsMatrix)))
		*transform = WsMatrix{}
		transform.values[0] = 1
		transform.values[4] = 1
		transform.values[8] = 1
		if kind == 0 {
			transform.values[2] = x
			transform.values[5] = y
		} else if kind == 1 {
			transform.values[0] = x
			transform.values[4] = y
		} else if kind == 3 {
			transform.values[1] = x
			transform.values[3] = y
		} else {
			radians := x * 0.017453292519943295
			mut sine, mut cosine := C.sinf(radians), C.cosf(radians)
			quarter := C.fmodf(x, 360)
			if quarter == 0 { sine = 0; cosine = 1 }
			else if quarter == 90 || quarter == -270 { sine = 1; cosine = 0 }
			else if quarter == 180 || quarter == -180 { sine = 0; cosine = -1 }
			else if quarter == 270 || quarter == -90 { sine = -1; cosine = 0 }
			transform.values[0] = cosine
			transform.values[1] = -sine
			transform.values[3] = sine
			transform.values[4] = cosine
		}
		if reset {
			C.memcpy(voidptr(pointer), transform, sizeof(WsMatrix))
			return 1
		}
		if post { return ws_matrix_concat(pointer, i64(transform), pointer) }
		return ws_matrix_concat(pointer, pointer, i64(transform))
	}
}

fn ws_matrix_pivot(pointer i64, kind i32, x f32, y f32, px f32, py f32, post bool, reset bool) u8 {
	unsafe {
		transform := &WsMatrix(C.alloca(sizeof(WsMatrix)))
		ws_matrix_transform(i64(transform), kind, x, y, false, true)
		transform.values[2] = px - transform.values[0] * px - transform.values[1] * py
		transform.values[5] = py - transform.values[3] * px - transform.values[4] * py
		if reset {
			C.memcpy(voidptr(pointer), transform, sizeof(WsMatrix))
			return 1
		}
		return if post { ws_matrix_concat(pointer, i64(transform), pointer) }
			else { ws_matrix_concat(pointer, pointer, i64(transform)) }
	}
}

fn ws_matrix_map_point(pointer i64, x f32, y f32, vector bool, output &f32) {
	unsafe {
		m := &WsMatrix(pointer)
		if vector {
			output[0] = m.values[0] * x + m.values[1] * y
			output[1] = m.values[3] * x + m.values[4] * y
		} else {
			z := m.values[6] * x + m.values[7] * y + m.values[8]
			output[0] = (m.values[0] * x + m.values[1] * y + m.values[2]) / z
			output[1] = (m.values[3] * x + m.values[4] * y + m.values[5]) / z
		}
	}
}

fn ws_matrix_map_points(e voidptr, pointer i64, destination voidptr, offset i32, source voidptr, start i32, count i32, points u8) {
	if count < 0 || offset < 0 || start < 0 || i64(offset) + i64(count) * 2 > ws_array_len(e, destination)
		|| i64(start) + i64(count) * 2 > ws_array_len(e, source) {
		throw(e, c'java/lang/ArrayIndexOutOfBoundsException', c'Matrix point range')
		return
	}
	unsafe {
		// Copy before writing: source and destination may be overlapping ranges
		// of the same Java array.
		buffer := &f32(C.malloc(usize(count) * 2 * sizeof(f32)))
		if buffer == nil && count != 0 { throw(e, c'java/lang/OutOfMemoryError', c'Matrix points'); return }
		defer { C.free(buffer) }
		WsFloatRegion(slot(e, 205))(e, source, start, count * 2, buffer)
		for i := i32(0); i < count; i++ {
			ws_matrix_map_point(pointer, buffer[i * 2], buffer[i * 2 + 1], points == 0, &buffer[i * 2])
		}
		WsFloatRegion(slot(e, 213))(e, destination, offset, count * 2, buffer)
	}
}

fn ws_matrix_rect_stays(pointer i64) u8 {
	unsafe {
		m := &WsMatrix(pointer)
		return u8(m.values[6] == 0 && m.values[7] == 0 && m.values[8] == 1
			&& ((m.values[1] == 0 && m.values[3] == 0) || (m.values[0] == 0 && m.values[4] == 0)))
	}
}
