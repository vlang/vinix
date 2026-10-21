// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_STDIO
#include "stb_image.h"

fn C.stbi_load_from_memory(&u8, i32, &i32, &i32, &i32, i32) &u8
fn C.stbi_image_free(voidptr)
fn C.realloc(voidptr, usize) voidptr
fn C.__atomic_add_fetch(&i32, i32, i32) i32
fn C.__atomic_sub_fetch(&i32, i32, i32) i32

struct WsBitmap {
mut:
	width      i32
	height     i32
	references i32
	rgba       &u8
}

type WsWebPInfo = fn (&u8, usize, &i32, &i32) i32
type WsWebPInto = fn (&u8, usize, &u8, usize, i32) &u8

__global ws_webp_library voidptr
__global ws_webp_info WsWebPInfo
__global ws_webp_into WsWebPInto

fn ws_webp_init() bool {
	unsafe {
		ws_webp_library = C.dlopen(c'libwebp.so.7', 2)
		if ws_webp_library == nil { return false }
		ws_webp_info = WsWebPInfo(C.dlsym(ws_webp_library, c'WebPGetInfo'))
		ws_webp_into = WsWebPInto(C.dlsym(ws_webp_library, c'WebPDecodeRGBAInto'))
		return voidptr(ws_webp_info) != nil && voidptr(ws_webp_into) != nil
	}
}

fn ws_bitmap_decode(bytes &u8, length i32) i64 {
	unsafe {
		mut width := i32(0)
		mut height := i32(0)
		mut channels := i32(0)
		mut pixels := &u8(nil)
		webp := length >= 12 && bytes[0] == `R` && bytes[1] == `I` && bytes[2] == `F`
			&& bytes[3] == `F` && bytes[8] == `W` && bytes[9] == `E` && bytes[10] == `B` && bytes[11] == `P`
		if webp {
			if ws_webp_info(bytes, usize(length), &width, &height) == 0 || width <= 0 || height <= 0
				|| width > 16384 || height > 16384 || i64(width) * height > 64 * 1024 * 1024 { return 0 }
			capacity := usize(width) * usize(height) * 4
			pixels = &u8(C.malloc(capacity))
			if pixels == nil { return 0 }
			if ws_webp_into(bytes, usize(length), pixels, capacity, width * 4) == nil {
				C.free(pixels)
				return 0
			}
		} else {
			pixels = C.stbi_load_from_memory(bytes, length, &width, &height, &channels, 4)
		}
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
		if C.__atomic_sub_fetch(&bitmap.references, 1, 5) == 0 {
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
		if pointer != 0 { C.__atomic_add_fetch(&(&WsBitmap(pointer)).references, 1, 5) }
		return pointer
	}
}

fn ws_bitmap_create(e voidptr, snapshot i64, width i32, height i32, stride i32, format i32) i64 {
	if snapshot != 0 { return snapshot } // ownership moves between texture and snapshot
	if width <= 0 || height <= 0 || width > 16384 || height > 16384 || i64(width) * height > 64 * 1024 * 1024 {
		throw(e, c'java/lang/IllegalArgumentException', c'Invalid bitmap dimensions')
		return 0
	}
	if format != 5 || stride != width * 4 {
		throw(e, c'java/lang/UnsupportedOperationException', c'Native WS bitmap storage requires ARGB_8888')
		return 0
	}
	unsafe {
		pixels := &u8(C.calloc(usize(width) * usize(height), 4))
		bitmap := &WsBitmap(C.malloc(sizeof(WsBitmap)))
		if pixels == nil || bitmap == nil {
			C.free(pixels)
			C.free(bitmap)
			throw(e, c'java/lang/OutOfMemoryError', c'Bitmap pixels')
			return 0
		}
		*bitmap = WsBitmap{width: width, height: height, references: 1, rgba: pixels}
		return i64(bitmap)
	}
}

fn ws_bitmap_snapshot(e voidptr, object voidptr) i64 {
	unsafe {
		if Monitor(slot(e, 217))(e, object) != 0 { return 0 }
		defer { Monitor(slot(e, 218))(e, object) }
		if !ws_bitmap_valid(e, object) {
			if !pending(e) { throw(e, c'java/lang/IllegalStateException', c'Bitmap is recycled') }
			return 0
		}
		mut pointer := get_long(e, object, c'android/graphics/Bitmap', c'snapshot')
		if pointer == 0 { pointer = get_long(e, object, c'android/graphics/Bitmap', c'texture') }
		if pointer == 0 {
			config := get_object(e, object, c'android/graphics/Bitmap', c'config', c'Landroid/graphics/Bitmap$Config;')
			format := get_int(e, config, c'android/graphics/Bitmap$Config', c'gdk_memory_format')
			Drop(slot(e, 23))(e, config)
			pointer = ws_bitmap_create(e, 0, get_int(e, object, c'android/graphics/Bitmap', c'width'),
				get_int(e, object, c'android/graphics/Bitmap', c'height'), get_int(e, object, c'android/graphics/Bitmap', c'stride'), format)
		}
		if pending(e) { return 0 }
		ws_bitmap_put_long(e, object, c'snapshot', pointer)
		ws_bitmap_put_long(e, object, c'texture', 0)
		return pointer
	}
}

fn ws_bitmap_clear(e voidptr, object voidptr, color u32) {
	unsafe {
		if Monitor(slot(e, 217))(e, object) != 0 { return }
		defer { Monitor(slot(e, 218))(e, object) }
		pointer := ws_bitmap_snapshot(e, object)
		if pointer == 0 || pending(e) { return }
		bitmap := &WsBitmap(pointer)
		for i := i32(0); i < bitmap.width * bitmap.height; i++ {
			bitmap.rgba[i * 4] = u8(color >> 16)
			bitmap.rgba[i * 4 + 1] = u8(color >> 8)
			bitmap.rgba[i * 4 + 2] = u8(color)
			bitmap.rgba[i * 4 + 3] = u8(color >> 24)
		}
	}
}

fn ws_bitmap_texture(e voidptr, object voidptr) i64 {
	unsafe {
		if Monitor(slot(e, 217))(e, object) != 0 { return 0 }
		defer { Monitor(slot(e, 218))(e, object) }
		pointer := ws_bitmap_snapshot(e, object)
		if pointer == 0 || pending(e) { return 0 }
		ws_bitmap_put_long(e, object, c'texture', pointer)
		ws_bitmap_put_long(e, object, c'snapshot', 0)
		return pointer
	}
}

type WsBitmapIntRegion = fn (voidptr, voidptr, i32, i32, &u32)

fn ws_bitmap_pixels(e voidptr, pointer i64, array voidptr, offset i32, stride i32, x i32, y i32, width i32, height i32, write bool) {
	if pointer == 0 { throw(e, c'java/lang/IllegalStateException', c'Bitmap has no pixels'); return }
	if array == unsafe { nil } { throw(e, c'java/lang/NullPointerException', c'Bitmap pixels'); return }
	unsafe {
		bitmap := &WsBitmap(pointer)
		absolute_stride := if stride < 0 { -i64(stride) } else { i64(stride) }
		if width < 0 || height < 0 || x < 0 || y < 0 || i64(x) + width > bitmap.width
			|| i64(y) + height > bitmap.height || absolute_stride < width {
			throw(e, c'java/lang/IllegalArgumentException', c'Bitmap pixel rectangle or stride')
			return
		}
		if width == 0 || height == 0 { return }
		last := i64(offset) + i64(height - 1) * stride
		first := if last < offset { last } else { i64(offset) }
		end := (if last > offset { last } else { i64(offset) }) + width
		if first < 0 || end > ws_array_len(e, array) {
			throw(e, c'java/lang/ArrayIndexOutOfBoundsException', c'Bitmap pixel array range')
			return
		}
		row := &u32(C.malloc(usize(width) * 4))
		if row == nil { throw(e, c'java/lang/OutOfMemoryError', c'Bitmap pixel row'); return }
		defer { C.free(row) }
		for line := i32(0); line < height && !pending(e); line++ {
			at := offset + line * stride
			if write { WsBitmapIntRegion(slot(e, 203))(e, array, at, width, row) }
			for column := i32(0); column < width; column++ {
				pixels := &bitmap.rgba[((y + line) * bitmap.width + x + column) * 4]
				if write {
					color := row[column]
					pixels[0] = u8(color >> 16); pixels[1] = u8(color >> 8)
					pixels[2] = u8(color); pixels[3] = u8(color >> 24)
				} else {
					row[column] = (u32(pixels[3]) << 24) | (u32(pixels[0]) << 16) | (u32(pixels[1]) << 8) | u32(pixels[2])
				}
			}
			if !write { WsBitmapIntRegion(slot(e, 211))(e, array, at, width, row) }
		}
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
	ws_draw_bitmap_paint(pointer, x, y, width, height, 0)
}

fn ws_draw_bitmap_paint(pointer i64, x i32, y i32, width i32, height i32, paint i64) {
	unsafe {
		if pointer == 0 { return }
		bitmap := &WsBitmap(pointer)
		ws_draw_bitmap_region(pointer, x, y, width, height, 0, 0, bitmap.width, bitmap.height, paint)
	}
}

fn ws_draw_bitmap_region(pointer i64, x i32, y i32, width i32, height i32, left i32, top i32, source_width i32, source_height i32, paint_pointer i64) {
	unsafe {
		if pointer == 0 || width <= 0 || height <= 0 || source_width <= 0 || source_height <= 0 { return }
		bitmap := &WsBitmap(pointer)
		mut pixels := bitmap.rgba
		copying := ws_draw_state().bitmap == pointer
		if copying {
			length := usize(bitmap.width) * usize(bitmap.height) * 4
			pixels = &u8(C.malloc(length))
			if pixels == nil { return }
			C.memcpy(pixels, bitmap.rgba, length)
		}
		defer { if copying { C.free(pixels) } }
		for row := i32(0); row < height; row++ {
			source_y := top + i32(i64(row) * source_height / height)
			if source_y < 0 || source_y >= bitmap.height { continue }
			for column := i32(0); column < width; column++ {
				source_x := left + i32(i64(column) * source_width / width)
				if source_x < 0 || source_x >= bitmap.width { continue }
				offset := (source_y * bitmap.width + source_x) * 4
				mut color := (u32(pixels[offset + 3]) << 24) | (u32(pixels[offset]) << 16) | (u32(pixels[offset + 1]) << 8) | u32(pixels[offset + 2])
				if paint_pointer != 0 {
					paint := &WsPaint(paint_pointer)
					if paint.filter_mode == 5 {
						color = (((color >> 24) * (paint.filter_color >> 24) / 255) << 24) | (paint.filter_color & 0xffffff)
					}
					color = (((color >> 24) * (paint.color >> 24) / 255) << 24) | (color & 0xffffff)
				}
				ws_rect(f32(x + column), f32(y + row), f32(x + column + 1), f32(y + row + 1), color)
			}
		}
	}
}
