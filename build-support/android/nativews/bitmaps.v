// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_STDIO
#include "stb_image.h"

fn C.stbi_load_from_memory(&u8, i32, &i32, &i32, &i32, i32) &u8
fn C.stbi_image_free(voidptr)
fn C.realloc(voidptr, usize) voidptr

struct WsBitmap {
mut:
	width      i32
	height     i32
	references i32
	rgba       &u8
}

fn ws_bitmap_decode(bytes &u8, length i32) i64 {
	unsafe {
		mut width := i32(0)
		mut height := i32(0)
		mut channels := i32(0)
		pixels := C.stbi_load_from_memory(bytes, length, &width, &height, &channels, 4)
		if pixels == nil { return 0 }
		bitmap := &WsBitmap(C.malloc(sizeof(WsBitmap)))
		*bitmap = WsBitmap{ width: width, height: height, references: 1, rgba: pixels }
		return i64(bitmap)
	}
}

fn ws_bitmap_unref(pointer i64) {
	unsafe {
		if pointer == 0 { return }
		bitmap := &WsBitmap(pointer)
		bitmap.references--
		if bitmap.references == 0 {
			C.stbi_image_free(bitmap.rgba)
			C.free(bitmap)
		}
	}
}

fn ws_bitmap_file(e voidptr, name voidptr) i64 {
	unsafe {
		path := ws_utf(e, name)
		fd := C.open(path, 0)
		ws_release(e, name, path)
		if fd < 0 { return 0 }
		defer { C.close(fd) }
		length := C.lseek(fd, 0, 2)
		if length <= 0 || length > 64 * 1024 * 1024 { return 0 }
		C.lseek(fd, 0, 0)
		bytes := &u8(C.malloc(usize(length)))
		defer { C.free(bytes) }
		mut used := i64(0)
		for used < length {
			n := C.read(fd, &bytes[used], usize(length - used))
			if n <= 0 { return 0 }
			used += i64(n)
		}
		return ws_bitmap_decode(bytes, i32(length))
	}
}

fn ws_bitmap_ref(pointer i64) i64 {
	unsafe {
		if pointer != 0 { (&WsBitmap(pointer)).references++ }
		return pointer
	}
}

fn ws_bitmap_stream(e voidptr, stream voidptr, storage voidptr) i64 {
	unsafe {
		count := ws_array_len(e, storage)
		if count <= 0 { return 0 }
		mut buffer := &u8(C.malloc(8192))
		mut capacity := usize(8192)
		mut used := usize(0)
		defer { C.free(buffer) }
		args := [Value{ l: storage }, Value{ i: 0 }, Value{ i: count }]!
		for !pending(e) {
			n := integer(e, stream, c'java/io/InputStream', c'read', c'([BII)I', &args[0])
			if n <= 0 { break }
			if used + usize(n) > 64 * 1024 * 1024 { return 0 }
			if used + usize(n) > capacity {
				for used + usize(n) > capacity { capacity *= 2 }
				grown := &u8(C.realloc(buffer, capacity))
				if grown == nil { return 0 }
				buffer = grown
			}
			WsByteRegion(slot(e, 200))(e, storage, 0, n, &buffer[used])
			used += usize(n)
		}
		if pending(e) { return 0 }
		return ws_bitmap_decode(buffer, i32(used))
	}
}

fn ws_bitmap_bytes(e voidptr, array voidptr, offset i32, length i32) voidptr {
	unsafe {
		if offset < 0 || length < 0 || i64(offset) + i64(length) > ws_array_len(e, array) {
			return nil
		}
		buffer := &u8(C.malloc(usize(length)))
		defer { C.free(buffer) }
		WsByteRegion(slot(e, 200))(e, array, offset, length, buffer)
		pointer := ws_bitmap_decode(buffer, length)
		if pointer == 0 { return nil }
		args := &Value(C.alloca(sizeof(Value)))
		args[0] = Value{ j: pointer }
		return new_object(e, c'android/graphics/Bitmap', c'(J)V', args)
	}
}

fn ws_draw_bitmap(pointer i64, x i32, y i32, width i32, height i32) {
	unsafe {
		if pointer == 0 || width <= 0 || height <= 0 { return }
		bitmap := &WsBitmap(pointer)
		for row := i32(0); row < height; row++ {
			source_y := row * bitmap.height / height
			for column := i32(0); column < width; column++ {
				source_x := column * bitmap.width / width
				offset := (source_y * bitmap.width + source_x) * 4
				color := (u32(bitmap.rgba[offset + 3]) << 24) + (u32(bitmap.rgba[offset]) << 16) + (u32(bitmap.rgba[offset + 1]) << 8) + u32(bitmap.rgba[offset + 2])
				ws_rect(f32(x + column), f32(y + row), f32(x + column + 1), f32(y + row + 1), color)
			}
		}
	}
}
