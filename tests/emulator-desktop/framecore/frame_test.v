// SPDX-License-Identifier: GPL-2.0-or-later
module framecore

import compress.zlib
import encoding.binary
import hash.crc32

fn decoded(png []u8, width int, height int) []u8 {
	assert png[..8] == [u8(137), 80, 78, 71, 13, 10, 26, 10]
	mut offset := 8
	mut kinds := []string{}
	mut pixels := []u8{}
	for offset < png.len {
		length := int(binary.big_endian_u32(png[offset..offset + 4]))
		kind := png[offset + 4..offset + 8].bytestr()
		body := png[offset + 8..offset + 8 + length]
		assert binary.big_endian_u32(png[offset + 8 + length..offset + 12 + length]) == crc32.sum(png[offset + 4..offset + 8 + length])
		kinds << kind
		if kind == 'IHDR' {
			assert binary.big_endian_u32(body[..4]) == width
			assert binary.big_endian_u32(body[4..8]) == height
			assert body[8..] == [u8(8), 2, 0, 0, 0]
		} else if kind == 'IDAT' {
			pixels = zlib.decompress(body) or { panic(err) }
		}
		offset += 12 + length
	}
	assert kinds == ['IHDR', 'IDAT', 'IEND']
	return pixels
}

fn failure(text string, kind Emulator, index i64, expected string) {
	extract(text, kind, index) or {
		assert err.msg() == expected
		return
	}
	assert false, 'accepted an invalid capture'
}

fn test_all_emulators_select_frames_and_write_valid_rgb_pngs() {
	for kind in [Emulator.n64, .ps1, .ps2, .ios] {
		prefix := kind.prefix()
		text := 'boot\r\n${prefix}-FRAME: 2 2\r\n${prefix}-ROW: ff000000ff00\r\n${prefix}-ROW: 0000ffffffff\r\nnoise\n${prefix}-FRAME: 1 1\n${prefix}-ROW: 123456\n'
		first := extract(text, kind, 0) or { panic(err) }
		assert decoded(first, 2, 2) == [u8(0), 255, 0, 0, 0, 255, 0, 0, 0, 0, 255, 255, 255, 255]
		assert extract(text, kind, -2) or { panic(err) } == first
		last := extract(text, kind, -1) or { panic(err) }
		assert decoded(last, 1, 1) == [u8(0), 0x12, 0x34, 0x56]
		assert extract(text, kind, 1) or { panic(err) } == last
		failure(text, kind, -3, 'Frame index out of range: this log has 2 frame(s)')
		failure(text, kind, 2, 'Frame index out of range: this log has 2 frame(s)')
	}
}

fn test_frame_boundaries_and_validation() {
	for kind in [Emulator.n64, .ps1, .ps2, .ios] {
		prefix := kind.prefix()
		message := 'Incomplete ${kind.description()} framebuffer in this log'
		failure('no frame', kind, -1, 'No ${kind.description()} framebuffer in this log')
		for dimensions in ['0 1', '1 0', '8193 1', '1 8193', '9999999999999999999999999999 1'] {
			failure('${prefix}-FRAME: ${dimensions}\n${prefix}-ROW: 123456', kind, 0, message)
		}
		for rows in ['', '${prefix}-ROW: 12345', '${prefix}-ROW: 12345678', '${prefix}-ROW: AABBCC',
			'${prefix}-ROW: 123456\n${prefix}-ROW: abcdef'] {
			failure('${prefix}-FRAME: 1 1\n${rows}', kind, 0, message)
		}
		// A valid second frame must neither repair nor invalidate the first.
		text := '${prefix}-FRAME: 1 1\n${prefix}-FRAME: 1 1\n${prefix}-ROW: 123456'
		failure(text, kind, 0, message)
		assert decoded(extract(text, kind, 1) or { panic(err) }, 1, 1) == [u8(0), 0x12, 0x34, 0x56]
		text2 := '${prefix}-FRAME: 1 1\n${prefix}-ROW: abcdef\n${prefix}-FRAME: 0 0'
		assert decoded(extract(text2, kind, 0) or { panic(err) }, 1, 1) == [u8(0), 0xab, 0xcd,
			0xef]
		failure(text2, kind, -1, message)
	}
}

fn test_large_rows_and_embedded_markers() {
	row := '123456'.repeat(8192)
	// Python's original search is not anchored to line beginnings, and takes
	// the lowercase hexadecimal prefix of a row even if diagnostic text follows.
	text := 'prefix N64-FRAME: 8192 1tail\n[serial] N64-ROW: ${row} STOP'
	png := extract(text, .n64, -1) or { panic(err) }
	mut expected := [u8(0)]
	for _ in 0 .. 8192 {
		expected << [u8(0x12), 0x34, 0x56]
	}
	assert decoded(png, 8192, 1) == expected
}

fn test_unicode_header_digits_and_invalid_utf8_diagnostics() {
	text := 'boot\xffN64-FRAME: ١ １\nN64-ROW: 123456\xfe'
	assert decoded(extract(text, .n64, -1) or { panic(err) }, 1, 1) == [u8(0), 0x12, 0x34, 0x56]
	failure('N64-FRAME: 1 1\nN64-ROW: １２３４５６', .n64, 0,
		'Incomplete Nintendo 64 framebuffer in this log')
}
