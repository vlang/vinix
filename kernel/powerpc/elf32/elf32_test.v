// SPDX-License-Identifier: GPL-2.0-or-later
module elf32

import encoding.binary

fn put32(mut data []u8, at int, value u32) {
	binary.big_endian_put_u32(mut data[at..at + 4], value)
}

fn fixture() []u8 {
	mut data := []u8{len: 260}
	put32(mut data, 0, 0x7f454c46)
	put32(mut data, 4, 0x01020100)
	put32(mut data, 16, 0x00020014)
	put32(mut data, 20, 1)
	put32(mut data, 24, 0x02000100)
	put32(mut data, 28, 52)
	put32(mut data, 40, 0x00340020)
	put32(mut data, 44, 0x00010000)
	put32(mut data, 52, 1)
	put32(mut data, 56, 256)
	put32(mut data, 60, 0x02000100)
	put32(mut data, 64, 0x02000100)
	put32(mut data, 68, 4)
	put32(mut data, 72, 4096)
	put32(mut data, 76, 5)
	put32(mut data, 80, 4096)
	return data
}

fn test_static_big_endian_image() {
	data := fixture()
	mut image := Image{}
	assert parse(data.data, u32(data.len), mut image)
	assert image.entry == 0x02000100
	assert image.base == 0x02000000 && image.end == 0x02002000
	assert image.count == 1 && image.segments[0].memory_size == 4096
	for length in 0 .. data.len {
		assert !parse(data.data, u32(length), mut image)
		assert image.count == 0
	}
}

fn test_reject_invalid_header_and_segments() {
	// Header class/order/machine, unaligned/nonexecutable entry, overflowed
	// tables, unsupported loaders, file/memory bounds, address and alignment.
	for change in [[u32(4), 0x02020100]!, [u32(4), 0x01010100]!, [u32(16), 0x00020015]!,
		[u32(24), 0x02000101]!, [u32(24), 0x02000200]!, [u32(28), 0xfffffff0]!, [u32(44), 0xffff0000]!,
		[u32(52), 2]!, [u32(52), 3]!, [u32(52), 7]!, [u32(56), 0xfffffffc]!, [u32(68), 4097]!,
		[u32(68), 2]!, [u32(72), 0xffffffff]!, [u32(64), 0x03000100]!, [u32(76), 6]!, [u32(80),
			3]!, [u32(80), 0x10000000]!] {
		mut data := fixture()
		put32(mut data, int(change[0]), change[1])
		mut image := Image{}
		assert !parse(data.data, u32(data.len), mut image), '${change}'
	}
}

fn test_reject_overlapping_loads() {
	mut data := fixture()
	put32(mut data, 44, 0x00020000)
	copy(mut data[84..116], data[52..84])
	mut image := Image{}
	assert !parse(data.data, u32(data.len), mut image)
	put32(mut data, 92, 0x02002100)
	put32(mut data, 96, 0x02002100)
	assert parse(data.data, u32(data.len), mut image)
	assert image.count == 2
}

fn tls_fixture() []u8 {
	mut data := fixture()
	put32(mut data, 24, 0x40000100)
	put32(mut data, 44, 0x00020000)
	put32(mut data, 56, 0)
	put32(mut data, 60, 0x40000000)
	put32(mut data, 64, 0x40000000)
	put32(mut data, 68, u32(data.len))
	for i, value in [u32(7), 256, 0x40000100, 0x40000100, 4, 16, 4, 8] {
		put32(mut data, 84 + i * 4, value)
	}
	return data
}

fn test_user_tls_requires_mapped_headers_and_template() {
	data := tls_fixture()
	mut image := Image{}
	assert !parse(data.data, u32(data.len), mut image)
	assert parse_user(data.data, u32(data.len), mut image)
	assert image.phdr == 0x40000034 && image.phnum == 2
	for change in [[u32(88), 255]!, [u32(92), 0x41000000]!, [u32(100), 17]!,
		[u32(104), 0xffffffff]!, [u32(112), 3]!, [u32(84), 3]!, [u32(84), 2]!] {
		mut bad := data.clone()
		put32(mut bad, int(change[0]), change[1])
		assert !parse_user(bad.data, u32(bad.len), mut image)
		assert image.count == 0
	}
	mut duplicate := data.clone()
	put32(mut duplicate, 44, 0x00030000)
	copy(mut duplicate[116..148], data[84..116])
	assert !parse_user(duplicate.data, u32(duplicate.len), mut image)
}
