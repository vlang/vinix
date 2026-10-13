// SPDX-License-Identifier: GPL-2.0-or-later
module surfacecore

import encoding.binary
import os
import time

#include <stdlib.h>

fn C.mkdtemp(voidptr) voidptr

fn fixture_directory() string {
	mut name := (os.temp_dir() + '/vinix-surface-test.XXXXXX\x00').bytes()
	assert C.mkdtemp(name.data) != unsafe { nil }
	return name.bytestr().all_before('\x00')
}

fn test_scaled_offsets_keep_floor_and_avoid_wide_product_overflow() {
	for value in [i64(-8192), -8188, -8191, -1, 0, 1, 8192, 9999999] {
		for index in 0 .. 1000 {
			product := value * index
			golden := if product >= 0 { product / 1000 } else { -((-product + 999) / 1000) }
			assert scaled(value, index, 1000) == golden
		}
	}
	assert scaled(9223372036854775807, 999, 1000) == 9214148664817921031
	assert clipped(-1, 500) == 499 && clipped(-501, 500) == 0
	assert clipped(501, 500) == 500
}

fn test_surface_sampling_small_files_and_live_shared_updates() {
	work := fixture_directory()
	defer { os.rmdir_all(work) or {} }
	path := work + '/surface'
	for length in [1, 2, 3, 4, 64, 4096, 8192, 20000] {
		os.write_file(path, []u8{len: length, init: u8(0x11)}.bytestr()) or { panic(err) }
		mut mapped := map_file(path, false) or { panic(err) }
		assert mapped.colors() or { panic(err) } == if length <= 3 { 0 } else { 1 }, length.str()
		mapped.close()
		mapped.close()
		if _ := mapped.colors() {
			assert false
		}
	}
	os.write_file(path, []u8{len: 8192}.bytestr()) or { panic(err) }
	mut reader := map_file(path, false) or { panic(err) }
	mut writer := map_file(path, true) or { panic(err) }
	assert reader.colors() or { panic(err) } == 1
	unsafe { writer.data[4100] = 0x42 }
	assert reader.colors() or { panic(err) } == 2
	writer.close()
	reader.close()
	os.write_file(path, '') or { panic(err) }
	if _ := map_file(path, false) {
		assert false
	}
	if _ := map_file(work + '/missing', false) {
		assert false
	}
}

fn test_damage_unsigned_boundaries_and_crc_reference_vectors() {
	work := fixture_directory()
	defer { os.rmdir_all(work) or {} }
	path := work + '/value'
	for number in [u32(0), 1, 0x7fffffff, 0x80000000, 0xffffffff] {
		mut bytes := []u8{len: 8, init: u8(0xa5)}
		binary.little_endian_put_u32(mut bytes, number)
		os.write_file(path, bytes.bytestr()) or { panic(err) }
		assert damage(path) or { panic(err) } == number
	}
	os.write_file(path, 'abc') or { panic(err) }
	if _ := damage(path) {
		assert false
	}
	os.write_file(path, '') or { panic(err) }
	assert sampled_crc(path) or { panic(err) } == 0
	// For a one-byte file every sampled offset is zero: 64 ASCII zeros.
	os.write_file(path, '0') or { panic(err) }
	// Independently captured from the system gzip trailer for 64 ASCII zeros.
	assert sampled_crc(path) or { panic(err) } == u32(0x34b1e4cb)
}

fn test_xwd_paint_grid_and_incomplete_header_bounds() {
	work := fixture_directory()
	defer { os.rmdir_all(work) or {} }
	path := work + '/screen'
	mut bytes := []u8{len: 100 + 64 * 256}
	for index, number in {
		0:  u32(100)
		16: 64
		20: 64
		48: 256
		76: 0
	} {
		binary.big_endian_put_u32(mut bytes[index..index + 4], number)
	}
	for y in 0 .. 64 {
		for x in 0 .. 64 { bytes[100 + y * 256 + x * 4] = u8((y / 16) * 4 + x / 16) }
	}
	os.write_file(path, bytes.bytestr()) or { panic(err) }
	mut screen := map_file(path, false) or { panic(err) }
	screen.wait_for_paint(100 * time.millisecond) or { panic(err) }
	screen.close()
	os.write_file(path, bytes[..bytes.len - 1].bytestr()) or { panic(err) }
	mut short := map_file(path, false) or { panic(err) }
	if _ := short.wait_for_paint(time.millisecond) {
		assert false
	}
	short.close()
	for index in 100 .. bytes.len { bytes[index] = 0 }
	os.write_file(path, bytes.bytestr()) or { panic(err) }
	mut blank := map_file(path, false) or { panic(err) }
	start := time.sys_mono_now()
	if _ := blank.wait_for_paint(time.millisecond) {
		assert false
	}
	assert time.sys_mono_now() - start >= u64(time.second)
	blank.close()
}
