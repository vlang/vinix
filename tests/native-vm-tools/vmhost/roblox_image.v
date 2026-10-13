// SPDX-License-Identifier: MIT
module vmhost

import encoding.binary
import hash.crc32
import os

#flag -lz
#include <zlib.h>

fn C.compressBound(usize) usize
fn C.compress2(&u8, &usize, &u8, usize, i32) i32

fn png_chunk(kind string, body []u8) []u8 {
	mut data := []u8{len: 4}
	binary.big_endian_put_u32(mut data, u32(body.len))
	data << kind.bytes()
	data << body
	mut crc := []u8{len: 4}
	binary.big_endian_put_u32(mut crc, crc32.sum([...kind.bytes(), ...body]))
	data << crc
	return data
}

pub fn roblox_xwd(source string, target string) !bool {
	data := os.read_bytes(source)!
	if data.len < 100 { return false }
	header_size := u64(binary.big_endian_u32_at(data, 0))
	width := u64(binary.big_endian_u32_at(data, 16))
	height := u64(binary.big_endian_u32_at(data, 20))
	little := binary.big_endian_u32_at(data, 28) == 0
	bits := binary.big_endian_u32_at(data, 44)
	line_bytes := u64(binary.big_endian_u32_at(data, 48))
	colours := u64(binary.big_endian_u32_at(data, 76))
	start := header_size + colours * 12
	if bits != 32 || start + line_bytes * height > u64(data.len) { return false }
	if width == 0 || height == 0 || width * 4 > line_bytes || height * (1 + width * 3) > u64(max_int) {
		return error('invalid XWD pixel dimensions')
	}
	mut rows := []u8{len: int(height * (1 + width * 3))}
	mut drawn := false
	for y in 0 .. int(height) {
		begin := int(start + u64(y) * line_bytes)
		output := y * (1 + int(width) * 3) + 1
		for x in 0 .. int(width) {
			offset := begin + x * 4
			for channel, at in (if little { [2, 1, 0] } else { [1, 2, 3] }) {
				value := data[offset + at]
				rows[output + x * 3 + channel] = value
				drawn = drawn || value != 0
			}
		}
	}
	mut size := C.compressBound(usize(rows.len))
	mut compressed := []u8{len: int(size)}
	if C.compress2(compressed.data, &size, rows.data, usize(rows.len), 6) != C.Z_OK {
		return error('could not compress framebuffer')
	}
	mut info := []u8{len: 13}
	binary.big_endian_put_u32(mut info[..4], u32(width))
	binary.big_endian_put_u32(mut info[4..8], u32(height))
	info[8] = 8
	info[9] = 2
	mut png := [u8(137), `P`, `N`, `G`, 13, 10, 26, 10]
	for part in [png_chunk('IHDR', info), png_chunk('IDAT', compressed[..int(size)]),
		png_chunk('IEND', [])] {
		png << part
	}
	os.write_file_array(target, png)!
	return drawn
}
