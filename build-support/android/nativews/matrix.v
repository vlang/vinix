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
		WsFloatRegion(slot(e, if put { 212 } else { 204 }))(e, array, 0, 9, &matrix.values[0])
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
		} else {
			radians := x * 0.017453292519943295
			transform.values[0] = C.cosf(radians)
			transform.values[1] = -C.sinf(radians)
			transform.values[3] = C.sinf(radians)
			transform.values[4] = C.cosf(radians)
		}
		if reset {
			C.memcpy(voidptr(pointer), transform, sizeof(WsMatrix))
			return 1
		}
		if post { return ws_matrix_concat(pointer, i64(transform), pointer) }
		return ws_matrix_concat(pointer, pointer, i64(transform))
	}
}
