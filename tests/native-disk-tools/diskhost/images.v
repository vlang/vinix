// SPDX-License-Identifier: GPL-2.0-or-later
module diskhost

import os
import policyhost
import hosttest

const page = i64(4096)
const tail = i64(4 * 1024 * 1024)

pub fn crc32c(data []u8) u32 {
	mut crc := u32(0xffffffff)
	for byte in data {
		crc ^= byte
		for _ in 0 .. 8 { crc = (crc >> 1) ^ if crc & 1 != 0 { u32(0x82f63b78) } else { u32(0) } }
	}
	return crc ^ 0xffffffff
}

fn put(mut data []u8, offset int, value u64, size int) {
	for index in 0 .. size { data[offset + index] = u8(value >> u32(index * 8)) }
}

fn number(data []u8, offset int, size int) u64 {
	mut value := u64(0)
	for index in 0 .. size { value |= u64(data[offset + index]) << u32(index * 8) }
	return value
}

fn read_exact(mut file os.File, offset i64, size int) ![]u8 {
	file.seek(offset, .start)!
	mut data := []u8{len: size}
	mut got := 0
	for got < size {
		count := file.read(mut data[got..])!
		if count == 0 { return error('short filesystem image') }
		got += count
	}
	return data
}

fn write_exact(mut file os.File, data []u8) ! {
	mut sent := 0
	for sent < data.len {
		count := file.write(data[sent..])!
		if count == 0 { return error('short filesystem image write') }
		sent += count
	}
}

pub fn journal_config(uuid []u8, home i64) ![]u8 {
	if uuid.len != 16 || home < 0 { return error('invalid filesystem fixture identity') }
	mut config := []u8{len: int(page)}
	put(mut config, 0, 0x314c4e4a58494e56, 8)
	put(mut config, 8, 1, 4)
	put(mut config, 12, u64(page), 4)
	put(mut config, 16, u64(home), 8)
	put(mut config, 24, u64(home), 8)
	put(mut config, 32, u64(tail), 8)
	for index in 0 .. 16 { config[40 + index] = uuid[index] }
	put(mut config, 56, crc32c(config), 4)
	return config
}

pub fn journal_fixture(path string, seed string, tool string, home_mib int) ! {
	if home_mib <= 0 { return error('invalid disposable filesystem capacity') }
	home := i64(home_mib) * 1024 * 1024
	format_ext2(tool, path, seed, home)!
	mut file := os.open_file(path, 'r+')!
	defer { file.close() }
	config := journal_config(read_exact(mut file, 1128, 16)!, home)!
	if C.ftruncate(file.fd, u64(home + tail)) != 0 { return os.error_posix() }
	file.seek(home, .start)!
	write_exact(mut file, config)!
	file.seek(1080, .start)!
	write_exact(mut file, [u8(0x56), 0x4a])!
}

fn power(value u64, base u64) bool {
	mut remaining := value
	for remaining > 1 && remaining % base == 0 { remaining /= base }
	return remaining == 1
}

// Export only a recovered volume. Read the source; all signature writes go to
// a separate sparse inspection image and never to the live journaled disk.
pub fn export_clean(source string, destination string) !string {
	if os.real_path(source) == os.real_path(destination) {
		return error('inspection source and destination must differ')
	}
	if os.exists(destination) {
		a, b := hosttest.bounds_file_state(source)!, hosttest.bounds_file_state(destination)!
		if a['st_dev']! == b['st_dev']! && a['st_ino']! == b['st_ino']! {
			return error('inspection source and destination must differ')
		}
	}
	mut input := os.open(source)!
	defer { input.close() }
	size := i64(os.file_size(source))
	if size < tail + 2 * page { return error('short filesystem image') }
	marker := read_exact(mut input, size / page * page - tail + page, int(page))!
	if marker.any(it != 0) {
		return error('inspection requires a cleared commit marker after native recovery')
	}
	sb := read_exact(mut input, 1024, 1024)!
	blocks, first, shift, per_group := number(sb, 4, 4), number(sb, 20, 4), number(sb, 24, 4), number(sb, 32, 4)
	if shift > 6 || blocks <= first || per_group == 0 {
		return error('invalid filesystem geometry')
	}
	block := u64(1024) << u32(shift)
	home := blocks * block
	if home > u64(size) { return error('short filesystem image') }
	mut output := os.create(destination)!
	defer { output.close() }
	mut position := u64(0)
	for position < home {
		policyhost.command_checkpoint()!
		count := int(if home - position < 1024 * 1024 { home - position } else { u64(1024 * 1024) })
		data := read_exact(mut input, i64(position), count)!
		if data.any(it != 0) {
			output.seek(i64(position), .start)!
			write_exact(mut output, data)!
		}
		position += u64(count)
	}
	if C.ftruncate(output.fd, home) != 0 { return os.error_posix() }
	output.seek(1080, .start)!
	write_exact(mut output, [u8(0x53), 0xef])!
	groups := (blocks - first + per_group - 1) / per_group
	sparse := number(sb, 100, 4) & 1 != 0
	for group in u64(1) .. groups {
		policyhost.command_checkpoint()!
		if sparse && group != 1 && ![u64(3), 5, 7].any(power(group, it)) { continue }
		offset := (first + group * per_group) * block + 56
		if offset + 2 > home { return error('invalid backup superblock geometry') }
		output.seek(i64(offset), .start)!
		write_exact(mut output, [u8(0x53), 0xef])!
	}
	return destination
}
