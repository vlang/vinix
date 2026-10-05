// SPDX-License-Identifier: GPL-2.0-or-later
// Export PNG as one streamed IDAT chunk. Stored DEFLATE blocks require only a
// 64 KiB scratch buffer and do not flatten the original image's alpha channel.
module main

const preview_crc_table = [
	u32(0x00000000),
	0x77073096,
	0xee0e612c,
	0x990951ba,
	0x076dc419,
	0x706af48f,
	0xe963a535,
	0x9e6495a3,
	0x0edb8832,
	0x79dcb8a4,
	0xe0d5e91e,
	0x97d2d988,
	0x09b64c2b,
	0x7eb17cbd,
	0xe7b82d07,
	0x90bf1d91,
	0x1db71064,
	0x6ab020f2,
	0xf3b97148,
	0x84be41de,
	0x1adad47d,
	0x6ddde4eb,
	0xf4d4b551,
	0x83d385c7,
	0x136c9856,
	0x646ba8c0,
	0xfd62f97a,
	0x8a65c9ec,
	0x14015c4f,
	0x63066cd9,
	0xfa0f3d63,
	0x8d080df5,
	0x3b6e20c8,
	0x4c69105e,
	0xd56041e4,
	0xa2677172,
	0x3c03e4d1,
	0x4b04d447,
	0xd20d85fd,
	0xa50ab56b,
	0x35b5a8fa,
	0x42b2986c,
	0xdbbbc9d6,
	0xacbcf940,
	0x32d86ce3,
	0x45df5c75,
	0xdcd60dcf,
	0xabd13d59,
	0x26d930ac,
	0x51de003a,
	0xc8d75180,
	0xbfd06116,
	0x21b4f4b5,
	0x56b3c423,
	0xcfba9599,
	0xb8bda50f,
	0x2802b89e,
	0x5f058808,
	0xc60cd9b2,
	0xb10be924,
	0x2f6f7c87,
	0x58684c11,
	0xc1611dab,
	0xb6662d3d,
	0x76dc4190,
	0x01db7106,
	0x98d220bc,
	0xefd5102a,
	0x71b18589,
	0x06b6b51f,
	0x9fbfe4a5,
	0xe8b8d433,
	0x7807c9a2,
	0x0f00f934,
	0x9609a88e,
	0xe10e9818,
	0x7f6a0dbb,
	0x086d3d2d,
	0x91646c97,
	0xe6635c01,
	0x6b6b51f4,
	0x1c6c6162,
	0x856530d8,
	0xf262004e,
	0x6c0695ed,
	0x1b01a57b,
	0x8208f4c1,
	0xf50fc457,
	0x65b0d9c6,
	0x12b7e950,
	0x8bbeb8ea,
	0xfcb9887c,
	0x62dd1ddf,
	0x15da2d49,
	0x8cd37cf3,
	0xfbd44c65,
	0x4db26158,
	0x3ab551ce,
	0xa3bc0074,
	0xd4bb30e2,
	0x4adfa541,
	0x3dd895d7,
	0xa4d1c46d,
	0xd3d6f4fb,
	0x4369e96a,
	0x346ed9fc,
	0xad678846,
	0xda60b8d0,
	0x44042d73,
	0x33031de5,
	0xaa0a4c5f,
	0xdd0d7cc9,
	0x5005713c,
	0x270241aa,
	0xbe0b1010,
	0xc90c2086,
	0x5768b525,
	0x206f85b3,
	0xb966d409,
	0xce61e49f,
	0x5edef90e,
	0x29d9c998,
	0xb0d09822,
	0xc7d7a8b4,
	0x59b33d17,
	0x2eb40d81,
	0xb7bd5c3b,
	0xc0ba6cad,
	0xedb88320,
	0x9abfb3b6,
	0x03b6e20c,
	0x74b1d29a,
	0xead54739,
	0x9dd277af,
	0x04db2615,
	0x73dc1683,
	0xe3630b12,
	0x94643b84,
	0x0d6d6a3e,
	0x7a6a5aa8,
	0xe40ecf0b,
	0x9309ff9d,
	0x0a00ae27,
	0x7d079eb1,
	0xf00f9344,
	0x8708a3d2,
	0x1e01f268,
	0x6906c2fe,
	0xf762575d,
	0x806567cb,
	0x196c3671,
	0x6e6b06e7,
	0xfed41b76,
	0x89d32be0,
	0x10da7a5a,
	0x67dd4acc,
	0xf9b9df6f,
	0x8ebeeff9,
	0x17b7be43,
	0x60b08ed5,
	0xd6d6a3e8,
	0xa1d1937e,
	0x38d8c2c4,
	0x4fdff252,
	0xd1bb67f1,
	0xa6bc5767,
	0x3fb506dd,
	0x48b2364b,
	0xd80d2bda,
	0xaf0a1b4c,
	0x36034af6,
	0x41047a60,
	0xdf60efc3,
	0xa867df55,
	0x316e8eef,
	0x4669be79,
	0xcb61b38c,
	0xbc66831a,
	0x256fd2a0,
	0x5268e236,
	0xcc0c7795,
	0xbb0b4703,
	0x220216b9,
	0x5505262f,
	0xc5ba3bbe,
	0xb2bd0b28,
	0x2bb45a92,
	0x5cb36a04,
	0xc2d7ffa7,
	0xb5d0cf31,
	0x2cd99e8b,
	0x5bdeae1d,
	0x9b64c2b0,
	0xec63f226,
	0x756aa39c,
	0x026d930a,
	0x9c0906a9,
	0xeb0e363f,
	0x72076785,
	0x05005713,
	0x95bf4a82,
	0xe2b87a14,
	0x7bb12bae,
	0x0cb61b38,
	0x92d28e9b,
	0xe5d5be0d,
	0x7cdcefb7,
	0x0bdbdf21,
	0x86d3d2d4,
	0xf1d4e242,
	0x68ddb3f8,
	0x1fda836e,
	0x81be16cd,
	0xf6b9265b,
	0x6fb077e1,
	0x18b74777,
	0x88085ae6,
	0xff0f6a70,
	0x66063bca,
	0x11010b5c,
	0x8f659eff,
	0xf862ae69,
	0x616bffd3,
	0x166ccf45,
	0xa00ae278,
	0xd70dd2ee,
	0x4e048354,
	0x3903b3c2,
	0xa7672661,
	0xd06016f7,
	0x4969474d,
	0x3e6e77db,
	0xaed16a4a,
	0xd9d65adc,
	0x40df0b66,
	0x37d83bf0,
	0xa9bcae53,
	0xdebb9ec5,
	0x47b2cf7f,
	0x30b5ffe9,
	0xbdbdf21c,
	0xcabac28a,
	0x53b39330,
	0x24b4a3a6,
	0xbad03605,
	0xcdd70693,
	0x54de5729,
	0x23d967bf,
	0xb3667a2e,
	0xc4614ab8,
	0x5d681b02,
	0x2a6f2b94,
	0xb40bbe37,
	0xc30c8ea1,
	0x5a05df1b,
	0x2d02ef8d,
]!

fn preview_crc_update(initial u32, bytes &u8, length int) u32 {
	mut crc := initial
	for index in 0 .. length {
		crc = preview_crc_table[int((crc ^ u32(unsafe { bytes[index] })) & 0xff)] ^ (crc >> 8)
	}
	return crc
}

fn (a &PreviewApp) write_png(fd int) bool {
	if a.pixels == unsafe { nil } { return false }
	width, height := a.oriented_dimensions()
	if !preview_dimensions_valid(width, height) { return false }
	mut header := [33]u8{}
	signature := [u8(0x89), `P`, `N`, `G`, `\r`, `\n`, 0x1a, `\n`]!
	for index, byte in signature { header[index] = byte }
	preview_put_be32(unsafe { &header[0] }, 8, 13)
	for index, byte in 'IHDR' { header[12 + index] = byte }
	preview_put_be32(unsafe { &header[0] }, 16, u32(width))
	preview_put_be32(unsafe { &header[0] }, 20, u32(height))
	header[24] = 8
	header[25] = 6 // RGBA
	preview_put_be32(unsafe { &header[0] }, 29, ~preview_crc_update(~u32(0), unsafe { &header[12] }, 17))
	if !desktop_write_all(fd, unsafe { &header[0] }, u64(header.len)) { return false }
	row_size := width * 4 + 1
	raw_size := row_size * height
	blocks := (raw_size + 65534) / 65535
	mut idat := [8]u8{}
	preview_put_be32(unsafe { &idat[0] }, 0, u32(raw_size + blocks * 5 + 6))
	for index, byte in 'IDAT' { idat[4 + index] = byte }
	if !desktop_write_all(fd, unsafe { &idat[0] }, u64(idat.len)) { return false }
	mut crc := preview_crc_update(~u32(0), unsafe { &idat[4] }, 4)
	zlib_header := [u8(0x78), 0x01]!
	crc = preview_crc_update(crc, unsafe { &zlib_header[0] }, zlib_header.len)
	if !desktop_write_all(fd, unsafe { &zlib_header[0] }, u64(zlib_header.len)) { return false }
	mut block := []u8{len: 65535}
	defer { unsafe { block.free() } }
	mut offset := 0
	mut row := 0
	mut within_row := 0
	mut pixel := 0
	mut adler_a := u32(1)
	mut adler_b := u32(0)
	for offset < raw_size {
		length := if raw_size - offset > block.len { block.len } else { raw_size - offset }
		for index in 0 .. length {
			byte := if within_row == 0 {
				u8(0)
			} else {
				component := (within_row - 1) % 4
				if component == 0 { pixel = a.pixel_offset((within_row - 1) / 4, row) }
				unsafe { a.pixels[pixel + component] }
			}
			block[index] = byte
			within_row++
			if within_row == row_size {
				within_row = 0
				row++
			}
		}
		// At most 5552 bytes can be accumulated without overflowing Adler's
		// 32-bit sums. Reduce once per group instead of twice for every byte.
		mut checksum_offset := 0
		for checksum_offset < length {
			end := if length - checksum_offset > 5552 { checksum_offset + 5552 } else { length }
			for index in checksum_offset .. end {
				adler_a += u32(block[index])
				adler_b += adler_a
			}
			adler_a %= 65521
			adler_b %= 65521
			checksum_offset = end
		}
		inverse := ~u16(length)
		block_header := [u8(if offset + length == raw_size { 1 } else { 0 }), u8(length),
			u8(length >> 8), u8(inverse), u8(inverse >> 8)]!
		crc = preview_crc_update(crc, unsafe { &block_header[0] }, block_header.len)
		crc = preview_crc_update(crc, block.data, length)
		if !desktop_write_all(fd, unsafe { &block_header[0] }, u64(block_header.len))
			|| !desktop_write_all(fd, block.data, u64(length)) {
			return false
		}
		offset += length
	}
	mut ending := [8]u8{}
	preview_put_be32(unsafe { &ending[0] }, 0, adler_b << 16 | adler_a)
	crc = preview_crc_update(crc, unsafe { &ending[0] }, 4)
	preview_put_be32(unsafe { &ending[0] }, 4, ~crc)
	if !desktop_write_all(fd, unsafe { &ending[0] }, u64(ending.len)) { return false }
	iend := [u8(0), 0, 0, 0, `I`, `E`, `N`, `D`, 0xae, 0x42, 0x60, 0x82]!
	return desktop_write_all(fd, unsafe { &iend[0] }, u64(iend.len))
}

fn (mut a PreviewApp) export_image(original bool) bool {
	if a.pixels == unsafe { nil } {
		a.set_status('preview.status.no_image')
		return false
	}
	path := editor_bytes_text(a.export_path).clone()
	defer { unsafe { path.free() } }
	if path.len == 0 {
		a.set_status('preview.status.export_path')
		return false
	}
	if !preview_path_valid(path) {
		a.set_status('preview.status.export_failed')
		return false
	}
	fd := C.open(&char(path.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL, 0o600)
	if fd < 0 {
		a.set_status(if desktop_lstat(path) != none {
			'preview.status.exists'
		} else {
			'preview.status.export_failed'
		})
		return false
	}
	written := if original {
		desktop_write_all(fd, a.source.data, u64(a.source.len))
	} else {
		a.write_png(fd)
	}
	synced := written && C.fsync(fd) == 0
	closed := desktop_close(fd) == 0
	if !written || !synced || !closed {
		// O_EXCL guarantees that this path was created by this export. Failed
		// writes remove only that new incomplete file, never an existing one.
		desktop_unlink(path)
		a.set_status('preview.status.export_failed')
		return false
	}
	a.set_status(if original { 'preview.status.copied' } else { 'preview.status.exported' })
	return true
}
