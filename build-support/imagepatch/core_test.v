// SPDX-License-Identifier: GPL-2.0-or-later
module imagepatch

import os

#include <stdlib.h>

fn C.mkdtemp(&char) &char

fn temporary_directory() !string {
	mut pattern := (os.temp_dir() + '/vinix-imagepatch-test-XXXXXX\x00').bytes()
	unsafe {
		path := C.mkdtemp(&char(pattern.data))
		if path == nil { return error('cannot create test directory') }
		return path.vstring().clone()
	}
}

fn test_interpreter_keeps_size_and_other_bytes() {
	mut data := '\x7fELF\x00/lib/ld-musl-aarch64.so.1\x00after'.bytes()
	interpreter(mut data, '/lib/ld-musl-aarch64.so.1', '/lib/ld-chromium.so.1')!
	assert data.bytestr() == '\x7fELF\x00/lib/ld-chromium.so.1\x00\x00\x00\x00\x00after'
	mut utf8 := 'prefix/☃/loader\x00suffix'.bytes()
	interpreter(mut utf8, '/☃/loader', '/é/ld')!
	assert utf8[..6].bytestr() == 'prefix'
	assert utf8[utf8.len - 6..].bytestr() == 'suffix'
	assert utf8[6..13].bytestr() == '/é/ld\x00'
}

fn test_interpreter_errors_never_modify_bytes() {
	for original in ['no match', '/loader\x00/loader\x00', '/loader-with-suffix\x00'] {
		mut data := original.bytes()
		interpreter(mut data, '/loader', '/new') or {
			assert err.msg().starts_with('expected one interpreter path')
			assert data.bytestr() == original
			continue
		}
		assert false
	}
	mut data := '/a\x00'.bytes()
	interpreter(mut data, '/a', '/longer') or {
		assert err.msg() == 'the replacement interpreter path is longer than the original'
		assert data.bytestr() == '/a\x00'
		return
	}
	assert false
}

fn put16(mut data []u8, offset int, value u16) {
	data[offset] = u8(value)
	data[offset + 1] = u8(value >> 8)
}

fn put32(mut data []u8, offset int, value u32) {
	put16(mut data, offset, u16(value))
	put16(mut data, offset + 2, u16(value >> 16))
}

fn fixture() []u8 {
	mut data := []u8{len: 8192, init: 0xa5}
	for index in 1024 .. 3072 { data[index] = 0 }
	put32(mut data, 1024, 3)
	put32(mut data, 1024 + 20, 1)
	put32(mut data, 1024 + 40, 2)
	put16(mut data, 1024 + 56, 0xef53)
	put32(mut data, 1024 + 76, 1)
	put16(mut data, 1024 + 88, 256)
	put32(mut data, 2048 + 8, 4)
	put32(mut data, 2048 + 32 + 8, 6)
	return data
}

fn test_ext2_all_owner_halves_and_partial_last_group_only() {
	work := temporary_directory()!
	defer { os.rmdir_all(work) or { panic(err) } }
	path := work + '/root.ext2'
	data := fixture()
	os.write_file_array(path, data)!
	assert root_owner(path)! == 12
	mut expected := data.clone()
	for base in [4096, 4352, 6144] {
		for field in [2, 24, 120, 122] { put16(mut expected, base + field, 0) }
	}
	assert os.read_bytes(path)! == expected
	assert root_owner(path)! == 0
	assert os.read_bytes(path)! == expected
}

fn test_ext2_rejects_unsupported_features_and_truncated_tables() {
	work := temporary_directory()!
	defer { os.rmdir_all(work) or { panic(err) } }
	path := work + '/root.ext2'
	for offset, value in {
		96:  u32(0x0080)
		100: u32(0x0400)
		40:  u32(0)
	} {
		mut data := fixture()
		put32(mut data, 1024 + offset, value)
		os.write_file_array(path, data)!
		root_owner(path) or {
			assert os.read_bytes(path)! == data
			continue
		}
		assert false
	}
	mut data := fixture()
	put32(mut data, 2048 + 8, 0xffffffff)
	os.write_file_array(path, data)!
	root_owner(path) or {
		assert err.msg() == '${path}: truncated inode table in group 0'
		assert os.read_bytes(path)! == data
		return
	}
	assert false
}
