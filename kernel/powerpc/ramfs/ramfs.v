// SPDX-License-Identifier: GPL-2.0-or-later
module ramfs

pub struct File {
pub mut:
	name      [101]u8
	name_size u32
	data      &u8 = unsafe { nil }
	size      u32
	directory bool
}

pub struct Image {
pub mut:
	count u32
	files [32]File
}

fn octal(data &u8, count u32) u32 {
	mut value := u32(0)
	mut ended := false
	unsafe {
		for i := u32(0); i < count; i++ {
			byte := data[i]
			if byte == 0 || byte == ` ` {
				ended = true
				continue
			}
			if ended || byte < `0` || byte > `7` || value > 0x1fffffff { return 0xffffffff }
			value = value * 8 + u32(byte - `0`)
		}
	}
	return value
}

pub fn (image &Image) find(name &u8, length u32) int {
	if length > 100 { return -1 }
	for i := u32(0); i < image.count; i++ {
		if image.files[i].name_size != length { continue }
		mut matches := true
		for j := u32(0); j < length; j++ {
			if image.files[i].name[j] != unsafe { name[j] } {
				matches = false
				break
			}
		}
		if matches { return int(i) }
	}
	return -1
}

// Bounded read-only USTAR archive; no heap, links, PAX extensions or devices.
pub fn parse(data &u8, size u32, mut image Image) bool {
	image.count = 0
	if size < 1024 || size % 512 != 0 { return false }
	mut at := u32(0)
	unsafe {
		for at <= size - 512 {
			mut sum := u32(0)
			for j := u32(0); j < 512; j++ { sum += data[at + j] }
			if sum == 0 {
				if size - at < 1024 { return false }
				for j := at; j < size; j++ { if data[j] != 0 { return false } }
				return true
			}
			for j := u32(148); j < 156; j++ { sum = sum - data[at + j] + 32 }
			if sum != octal(&data[at + 148], 8) || data[at + 257] != `u`
				|| data[at + 258] != `s` || data[at + 259] != `t` || data[at + 260] != `a`
				|| data[at + 261] != `r` || data[at + 345] != 0 || image.count == 32 {
				return false
			}
			length := octal(&data[at + 124], 12)
			if length == 0xffffffff || length > size - at - 512 { return false }
			kind := data[at + 156]
			if kind != 0 && kind != `0` && kind != `5` { return false }
			if kind == `5` && length != 0 { return false }
			mut file := File{ data: &data[at + 512], size: length, directory: kind == `5` }
			for file.name_size < 100 && data[at + file.name_size] != 0 {
				byte := data[at + file.name_size]
				if byte < 32 || byte > 126 { return false }
				file.name[file.name_size] = byte
				file.name_size++
			}
			if file.directory && file.name_size > 0 && file.name[file.name_size - 1] == `/` {
				file.name_size--
			}
			if file.name_size == 0 || file.name[0] == `/` { return false }
			// Reject empty, dot and dot-dot path components.
			mut component := u32(0)
			for j := u32(0); j <= file.name_size; j++ {
				if j == file.name_size || file.name[j] == `/` {
					if j == component || (file.name[component] == `.` && (j - component == 1 || (j - component == 2 && file.name[component + 1] == `.`))) {
						return false
					}
					component = j + 1
				}
			}
			file.name[file.name_size] = 0
			if image.find(&file.name[0], file.name_size) >= 0 { return false }
			image.files[image.count] = file
			image.count++
			next := u64(at) + 512 + ((u64(length) + 511) & ~u64(511))
			if next > size { return false }
			at = u32(next)
		}
	}
	return false
}
