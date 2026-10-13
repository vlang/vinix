// SPDX-License-Identifier: GPL-2.0-or-later
module surfacecore

import encoding.binary
import hash.crc32
import os
import time

#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

fn C.lseek(i32, i64, i32) i64
fn C.pread(i32, voidptr, usize, i64) isize

pub struct Mapping {
pub:
	length int
pub mut:
	data &u8 = unsafe { nil }
	fd   i32 = -1
}

pub fn map_file(path string, writable bool) !Mapping {
	fd := i32(C.open(path.str, if writable { 2 } else { 0 }))
	if fd < 0 { return os.error_posix() }
	mut retained := false
	defer { if !retained { C.close(fd) } }
	length := C.lseek(fd, 0, 2)
	if length <= 0 { return error('surface file cannot be mapped') }
	area := unsafe {
		C.mmap(nil, usize(length), C.PROT_READ | if writable {
			C.PROT_WRITE
		} else {
			0
		}, C.MAP_SHARED, fd, 0)
	}
	if area == voidptr(-1) { return os.error_posix() }
	retained = true
	return Mapping{ length: int(length), data: unsafe { &u8(area) }, fd: fd }
}

pub fn (mut mapping Mapping) close() {
	if mapping.fd < 0 { return }
	unsafe { C.munmap(mapping.data, usize(mapping.length)) }
	C.close(mapping.fd)
	mapping.fd = -1
	mapping.data = unsafe { nil }
}

fn floor_divide(value i64, divisor i64) i64 {
	quotient := value / divisor
	return if value < 0 && value % divisor != 0 { quotient - 1 } else { quotient }
}

fn scaled(value i64, index i64, divisor i64) i64 {
	// This preserves arbitrary-integer floor division without a wide product.
	return (value / divisor) * index + floor_divide((value % divisor) * index, divisor)
}

fn clipped(value i64, length int) int {
	adjusted := if value < 0 { value + length } else { value }
	return if adjusted < 0 {
		0
	} else if adjusted > length {
		length
	} else {
		int(adjusted)
	}
}

pub fn (mapping &Mapping) colors() !int {
	if mapping.fd < 0 { return error('surface mapping is retired') }
	mut seen := map[u32]bool{}
	defer { unsafe { seen.free() } }
	for index in 0 .. 1000 {
		at := i64(4096) + scaled(i64(mapping.length) - 8192, index, 1000)
		start, stop := clipped(at, mapping.length), clipped(at + 64, mapping.length)
		for offset := 0; offset < stop - start - 3; offset += 4 {
			pixel := start + offset
			key := unsafe { (u32(mapping.data[pixel]) << 16) | (u32(mapping.data[pixel + 1]) << 8) | u32(mapping.data[pixel + 2]) }
			seen[key] = true
		}
	}
	return seen.len
}

pub fn damage(path string) !u32 {
	mut file := os.open(path)!
	defer { file.close() }
	mut bytes := []u8{len: 4}
	if file.read(mut bytes)! != 4 { return error('incomplete damage counter') }
	return binary.little_endian_u32_at(bytes, 0)
}

pub fn sampled_crc(path string) !u32 {
	fd := i32(C.open(path.str, 0))
	if fd < 0 { return os.error_posix() }
	defer { C.close(fd) }
	length := C.lseek(fd, 0, 2)
	if length < 0 { return os.error_posix() }
	mut table := [256]u32{}
	for index in 0 .. 256 {
		mut value := u32(index)
		for _ in 0 .. 8 { value = (value >> 1) ^ if value & 1 != 0 { crc32.ieee } else { u32(0) } }
		table[index] = value
	}
	mut buffer := [4096]u8{}
	mut state := ~u32(0)
	for index in 0 .. 64 {
		position := scaled(length, index, 64)
		count := C.pread(fd, unsafe { &buffer[0] }, 4096, position)
		if count < 0 { return os.error_posix() }
		for byte_index in 0 .. int(count) {
			state = table[u8(state) ^ buffer[byte_index]] ^ (state >> 8)
		}
	}
	return ~state
}

pub fn (mapping &Mapping) word(offset int) !u32 {
	if mapping.fd < 0 || offset < 0 || offset > mapping.length - 4 {
		return error('incomplete XWD header')
	}
	return unsafe { (u32(mapping.data[offset]) << 24) | (u32(mapping.data[offset + 1]) << 16) | (u32(mapping.data[offset + 2]) << 8) | u32(mapping.data[offset + 3]) }
}

pub fn (mapping &Mapping) wait_for_paint(timeout time.Duration) ! {
	if mapping.length < 100 { return error('incomplete XWD header') }
	width, height, stride := u64(mapping.word(16)!), u64(mapping.word(20)!), u64(mapping.word(48)!)
	start := u64(mapping.word(0)!) + u64(mapping.word(76)!) * 12
	if start > u64(mapping.length) || (stride > 0 && height > (u64(mapping.length) - start) / stride) {
		return error('incomplete XWD screen')
	}
	mut seen := map[u32]bool{}
	defer { unsafe { seen.free() } }
	deadline := time.sys_mono_now() + u64(timeout)
	for time.sys_mono_now() < deadline {
		seen.clear()
		for y := u64(0); y < height; y += 16 {
			for x := u64(0); x < width; x += 16 {
				position := start + y * stride + x * 4
				mut key := u32(0)
				mut count := u32(0)
				for index in 0 .. 3 {
					if position + u64(index) >= u64(mapping.length) { break }
					key = (key << 8) | unsafe { u32(mapping.data[int(position) + index]) }
					count++
				}
				seen[(count << 24) | key] = true
			}
		}
		if seen.len >= 16 { return }
		time.sleep(time.second)
	}
	return error('OBS controls did not paint')
}
