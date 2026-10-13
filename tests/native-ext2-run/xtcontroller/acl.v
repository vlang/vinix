// SPDX-License-Identifier: GPL-2.0-or-later
module xtcontroller

import encoding.binary
import os
import strconv

pub fn acl_value() []u8 {
	mut value := []u8{len: 44}
	binary.little_endian_put_u32(mut value[..4], 2)
	for index, row in [[u32(1), 6, 0xffffffff], [u32(2), 4, 1000], [u32(4), 0, 0xffffffff],
		[u32(16), 4, 0xffffffff], [u32(32), 0, 0xffffffff]] {
		at := 4 + index * 8
		binary.little_endian_put_u16(mut value[at..at + 2], u16(row[0]))
		binary.little_endian_put_u16(mut value[at + 2..at + 4], u16(row[1]))
		binary.little_endian_put_u32(mut value[at + 4..at + 8], row[2])
	}
	return value
}

pub fn acl_block(text string) !u64 {
	if !text.contains('File ACL:') { return error('debugfs did not create the ACL fixture') }
	remaining := text.all_after('File ACL:').trim_left(' \t\r\n')
	mut size := 0
	for byte in remaining.bytes() {
		if !byte.is_digit() { break }
		size++
	}
	if size == 0 { return error('debugfs did not create the ACL fixture') }
	block := strconv.parse_uint(remaining[..size], 10, 64)!
	if block == 0 { return error('debugfs did not create the ACL fixture') }
	return block
}

pub fn acl_offset(raw []u8) !int {
	mut offset := 32
	for offset + 4 <= raw.len {
		if raw[offset..offset + 4] == [u8(0), 0, 0, 0] { break }
		if offset + 16 > raw.len { return error('short ext2 ACL entry') }
		name_length := int(raw[offset])
		value_offset := int(binary.little_endian_u16_at(raw, offset + 2))
		if raw[offset + 1] == 2 && name_length == 0 {
			if value_offset > raw.len - 4 { return error('invalid ext2 ACL value offset') }
			return value_offset
		}
		offset += (16 + name_length + 3) & ~3
	}
	return error('ACL fixture has no ext2 access-ACL entry')
}

pub fn seed_acl(debugfs string, disk string, path string, value string) ! {
	os.write_file_array(value, acl_value())!
	command([debugfs, '-w', '-R', 'ea_set -f ' + value + ' ' + path + ' system.posix_acl_access',
		disk], os.environ())!
}

pub fn corrupt_acl(debugfs string, disk string, path string, value string) ! {
	seed_acl(debugfs, disk, path, value)!
	block_number := acl_block(output([debugfs, '-R', 'stat ' + path, disk], os.environ())!)!
	mut image := os.open_file(disk, 'r+')!
	defer { image.close() }
	image.seek(1048, .start)!
	mut exponent := []u8{len: 4}
	if image.read(mut exponent)! != 4 { return error('short ext2 superblock') }
	shift := binary.little_endian_u32(exponent)
	if shift > 6 { return error('invalid ext2 block size') }
	block_size := u64(1024) << shift
	if block_number > u64(0x7fffffffffffffff) / block_size {
		return error('ext2 ACL block offset overflows')
	}
	block := block_number * block_size
	image.seek(i64(block), .start)!
	mut raw := []u8{len: int(block_size)}
	if image.read(mut raw)! != raw.len { return error('short ext2 ACL block') }
	index := acl_offset(raw)!
	image.seek(i64(block) + index, .start)!
	if image.write([u8(0), 0, 0, 0])! != 4 { return error('short ext2 ACL corruption write') }
}
