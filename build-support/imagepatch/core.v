// SPDX-License-Identifier: GPL-2.0-or-later
module imagepatch

import os

// Match bytearray.count's non-overlapping matches, including the terminator.
pub fn interpreter(mut image []u8, old_path string, new_path string) ! {
	old := (old_path + '\x00').bytes()
	replacement := (new_path + '\x00').bytes()
	if replacement.len > old.len {
		return error('the replacement interpreter path is longer than the original')
	}
	mut count := 0
	mut found := 0
	mut offset := 0
	for offset <= image.len - old.len {
		if image[offset..offset + old.len] == old {
			count++
			found = offset
			offset += old.len
		} else {
			offset++
		}
	}
	if count != 1 {
		return error('expected one interpreter path, found ${count}')
	}
	for index in 0 .. old.len {
		image[found + index] = if index < replacement.len { replacement[index] } else { u8(0) }
	}
}

pub fn interpreter_file(path string, old_path string, new_path string) ! {
	if new_path.len > old_path.len {
		return error('the replacement interpreter path is longer than the original')
	}
	mut image := os.read_bytes(path)!
	interpreter(mut image, old_path, new_path)!
	mut file := os.open_file(path, 'r+b')!
	defer { file.close() }
	write_table(mut file, image)!
}

fn write_table(mut file os.File, data []u8) ! {
	mut used := 0
	for used < data.len {
		written := file.write(data[used..])!
		if written == 0 { return error('0 bytes written') }
		used += written
	}
}

fn le16(data []u8, offset int) u16 {
	return u16(data[offset]) | u16(data[offset + 1]) << 8
}

fn le32(data []u8, offset int) u32 {
	return u32(le16(data, offset)) | u32(le16(data, offset + 2)) << 16
}

// Bounds-check before allocation; damaged geometry must not wrap an offset or
// allocate a table larger than the image that contains it.
fn read_table(mut file os.File, image_size u64, offset u64, length u64, diagnostic string) ![]u8 {
	if length > 0x7fffffff || offset > image_size || length > image_size - offset {
		return error(diagnostic)
	}
	file.seek(i64(offset), .start)!
	mut data := []u8{len: int(length)}
	mut used := 0
	for used < data.len {
		read := file.read(mut data[used..])!
		if read == 0 { return error(diagnostic) }
		used += read
	}
	return data
}

// mke2fs -d retains the host's owners. Change all four owner halves, including
// unused inodes, without touching any other inode or filesystem metadata.
pub fn root_owner(path string) !u64 {
	mut image := os.open_file(path, 'r+b')!
	defer { image.close() }
	image_size := os.file_size(path)
	superblock := read_table(mut image, image_size, 1024, 1024,
		'${path}: too small to hold a superblock')!
	if le16(superblock, 56) != 0xef53 { return error('${path}: not an ext2 image') }
	inodes := u64(le32(superblock, 0))
	first_block := u64(le32(superblock, 20))
	block_shift := le32(superblock, 24)
	per_group := u64(le32(superblock, 40))
	revision := le32(superblock, 76)
	inode_size := u64(if revision >= 1 { le16(superblock, 88) } else { u16(128) })
	if le32(superblock, 96) & 0x0080 != 0 || le32(superblock, 100) & 0x0400 != 0 {
		return error('${path}: 64-bit or checksummed images need their descriptors rewritten too')
	}
	if per_group == 0 || inode_size < 128 || block_shift > 30 {
		return error('${path}: implausible inode geometry')
	}
	block_size := u64(1024) << block_shift
	groups := (inodes + per_group - 1) / per_group
	if first_block + 1 > image_size / block_size {
		return error('${path}: truncated group descriptor table')
	}
	descriptors := read_table(mut image, image_size, (first_block + 1) * block_size,
		32 * groups, '${path}: truncated group descriptor table')!
	mut changed := u64(0)
	for group := u64(0); group < groups; group++ {
		table_block := u64(le32(descriptors, int(group * 32 + 8)))
		if table_block > image_size / block_size {
			return error('${path}: truncated inode table in group ${group}')
		}
		count := if per_group < inodes - group * per_group {
			per_group
		} else {
			inodes - group * per_group
		}
		mut table := read_table(mut image, image_size, table_block * block_size, inode_size * count,
			'${path}: truncated inode table in group ${group}')!
		for index := u64(0); index < count; index++ {
			for field in [2, 24, 120, 122] {
				offset := int(index * inode_size) + field
				if le16(table, offset) != 0 {
					table[offset] = 0
					table[offset + 1] = 0
					changed++
				}
			}
		}
		image.seek(i64(table_block * block_size), .start)!
		write_table(mut image, table)!
	}
	return changed
}
