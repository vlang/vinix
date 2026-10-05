// SPDX-License-Identifier: GPL-2.0-or-later
// stb's ordinary PNG loader can grow the inflated IDAT buffer beyond the image
// header's dimensions. Preflight the exact compressed bytes with its fixed
// output-buffer inflater before handing them to the ordinary image decoder.
module main

fn C.stbi_zlib_decode_buffer(output &char, output_length int, input &char, input_length int) int
fn C.stbi_zlib_decode_noheader_buffer(output &char, output_length int, input &char, input_length int) int
fn C.stbi_convert_iphone_png_to_rgb(enabled int)
fn C.stbi_set_unpremultiply_on_load(enabled int)

fn preview_be32(bytes []u8, offset int) u32 {
	return u32(bytes[offset]) << 24 | u32(bytes[offset + 1]) << 16 |
		u32(bytes[offset + 2]) << 8 | u32(bytes[offset + 3])
}

fn preview_png_inflate_bounded(source []u8, width int, height int) bool {
	mut at := 8
	mut idat_length := 0
	mut iphone := false
	mut ended := false
	for at + 12 <= source.len {
		raw_length := preview_be32(source, at)
		if raw_length > u32(source.len - at - 12) { return false }
		length := int(raw_length)
		kind := preview_be32(source, at + 4)
		if kind == 0x49444154 { idat_length += length } // IDAT
		if kind == 0x43674249 { iphone = true } // CgBI uses raw DEFLATE
		if kind == 0x49454e44 { // IEND
			if length != 0 { return false }
			ended = true
			break
		}
		at += length + 12
	}
	if !ended || idat_length <= 0 { return false }
	mut compressed := []u8{len: idat_length}
	defer { unsafe { compressed.free() } }
	at = 8
	mut offset := 0
	for at + 12 <= source.len {
		length := int(preview_be32(source, at))
		kind := preview_be32(source, at + 4)
		if kind == 0x49444154 {
			unsafe { C.memcpy(&u8(compressed.data) + offset, &u8(source.data) + at + 8, usize(length)) }
			offset += length
		}
		if kind == 0x49454e44 { break }
		at += length + 12
	}
	// Eight bytes per pixel covers 16-bit RGBA; the row allowance covers
	// Adam7 passes and packed samples. Even a malformed stream cannot grow
	// this caller-owned output buffer. Release both buffers before decoding.
	mut expanded := []u8{len: width * height * 8 + height * 8 + 1024}
	defer { unsafe { expanded.free() } }
	result := if iphone {
		C.stbi_zlib_decode_noheader_buffer(&char(expanded.data), expanded.len,
			&char(compressed.data), compressed.len)
	} else {
		C.stbi_zlib_decode_buffer(&char(expanded.data), expanded.len,
			&char(compressed.data), compressed.len)
	}
	return result >= 0
}
