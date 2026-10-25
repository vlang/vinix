// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

// PNG uses straight RGBA, which is also WsBitmap's byte order. Stored DEFLATE
// blocks keep this encoder independent of another native codec or ABI header.
struct WsPngWriter {
mut:
	bytes &u8
	offset i32
	remaining i32
	block_left i32
	adler_a u32 = 1
	adler_b u32
	adler_count i32
}

fn ws_png_be32(bytes &u8, offset i32, value u32) {
	bytes[offset] = u8(value >> 24)
	bytes[offset + 1] = u8(value >> 16)
	bytes[offset + 2] = u8(value >> 8)
	bytes[offset + 3] = u8(value)
}

fn ws_png_crc(bytes &u8, length i32) u32 {
	mut table := [256]u32{}
	entries := unsafe { &table[0] }
	for index := 0; index < 256; index++ {
		mut value := u32(index)
		for bit := 0; bit < 8; bit++ {
			value = if value & 1 != 0 { (value >> 1) ^ u32(0xedb88320) } else { value >> 1 }
		}
		entries[index] = value
	}
	mut crc := ~u32(0)
	for index := i32(0); index < length; index++ {
		crc = (crc >> 8) ^ entries[(crc ^ bytes[index]) & 255]
	}
	return ~crc
}

@[inline]
fn ws_png_byte(mut writer WsPngWriter, value u8) {
	if writer.block_left == 0 {
		length := if writer.remaining > 65535 { i32(65535) } else { writer.remaining }
		writer.bytes[writer.offset] = if length == writer.remaining { u8(1) } else { u8(0) }
		writer.bytes[writer.offset + 1] = u8(length)
		writer.bytes[writer.offset + 2] = u8(length >> 8)
		writer.bytes[writer.offset + 3] = u8(~u16(length))
		writer.bytes[writer.offset + 4] = u8((~u16(length)) >> 8)
		writer.offset += 5
		writer.block_left = length
	}
	writer.bytes[writer.offset] = value
	writer.offset++
	writer.block_left--
	writer.remaining--
	writer.adler_a += value
	writer.adler_b += writer.adler_a
	writer.adler_count++
	// zlib's NMAX bound keeps both sums within u32 before reduction.
	if writer.adler_count == 5552 {
		writer.adler_a %= 65521
		writer.adler_b %= 65521
		writer.adler_count = 0
	}
}

fn ws_bitmap_png(e voidptr, pointer i64) voidptr {
	if pending(e) { return unsafe { nil } }
	if pointer == 0 {
		throw(e, c'java/lang/IllegalStateException', c'Bitmap has no pixel storage')
		return unsafe { nil }
	}
	bitmap := &WsBitmap(pointer)
	channels := if bitmap.alpha_only { i32(1) } else { i32(4) }
	if bitmap.width <= 0 || bitmap.height <= 0 || bitmap.width > 16384
		|| bitmap.height > 16384 || i64(bitmap.width) * bitmap.height > 64 * 1024 * 1024
		|| bitmap.row_bytes < i64(bitmap.width) * channels
		|| i64(bitmap.row_bytes) * bitmap.height > 2147483647 {
		throw(e, c'java/lang/IllegalArgumentException', c'Invalid bitmap dimensions or row stride')
		return unsafe { nil }
	}
	if bitmap.rgba == unsafe { nil } {
		throw(e, c'java/lang/IllegalStateException', c'Bitmap has no pixel storage')
		return unsafe { nil }
	}
	// The creation limits above bound every allocation, PNG chunk and JNI length
	// below INT_MAX. Include one filter byte per row and five bytes per block.
	raw_size := (bitmap.width * 4 + 1) * bitmap.height
	blocks := (raw_size + 65534) / 65535
	zlib_size := raw_size + blocks * 5 + 6
	size := zlib_size + 57
	bytes := &u8(C.malloc(usize(size)))
	if bytes == unsafe { nil } {
		throw(e, c'java/lang/OutOfMemoryError', c'PNG buffer allocation failed')
		return unsafe { nil }
	}
	defer { C.free(bytes) }
	ws_png_be32(bytes, 0, 0x89504e47)
	ws_png_be32(bytes, 4, 0x0d0a1a0a)
	ws_png_be32(bytes, 8, 13)
	ws_png_be32(bytes, 12, 0x49484452) // IHDR
	ws_png_be32(bytes, 16, u32(bitmap.width))
	ws_png_be32(bytes, 20, u32(bitmap.height))
	bytes[24] = 8
	bytes[25] = 6 // RGBA
	bytes[26] = 0
	bytes[27] = 0
	bytes[28] = 0
	ws_png_be32(bytes, 29, ws_png_crc(&bytes[12], 17))
	ws_png_be32(bytes, 33, u32(zlib_size))
	ws_png_be32(bytes, 37, 0x49444154) // IDAT
	bytes[41] = 0x78
	bytes[42] = 0x01
	mut writer := WsPngWriter{bytes: bytes, offset: 43, remaining: raw_size}
	for y := i32(0); y < bitmap.height; y++ {
		ws_png_byte(mut writer, 0) // PNG filter: None
		row := y * bitmap.row_bytes
		for x := i32(0); x < bitmap.width; x++ {
			if bitmap.alpha_only {
				ws_png_byte(mut writer, 0)
				ws_png_byte(mut writer, 0)
				ws_png_byte(mut writer, 0)
				ws_png_byte(mut writer, bitmap.rgba[row + x])
			} else {
				pixel := row + x * 4
				for channel := i32(0); channel < 4; channel++ {
					ws_png_byte(mut writer, bitmap.rgba[pixel + channel])
				}
			}
		}
	}
	ws_png_be32(bytes, writer.offset, ((writer.adler_b % 65521) << 16) | (writer.adler_a % 65521))
	ws_png_be32(bytes, writer.offset + 4, ws_png_crc(&bytes[37], zlib_size + 4))
	ws_png_be32(bytes, writer.offset + 8, 0)
	ws_png_be32(bytes, writer.offset + 12, 0x49454e44) // IEND
	ws_png_be32(bytes, writer.offset + 16, 0xae426082)
	result := WsNewByteArray(slot(e, 176))(e, size)
	if result == unsafe { nil } || pending(e) { return unsafe { nil } }
	WsByteRegion(slot(e, 208))(e, result, 0, size, bytes)
	if pending(e) { return unsafe { nil } }
	return result
}
