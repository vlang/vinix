// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

import crypto.sha256

fn patch_digest(input string) string {
	bytes := input.bytes()
	mut hash := sha256.new()
	mut sum := []u8{len: sha256.size}
	defer { unsafe { bytes.free(); sum.free(); hash.free(); free(hash) } }
	hash.write(bytes) or { panic(err) }
	hash.checksum_into(mut sum)
	return sum.hex()
}

pub const wine_server_input = '9583955993378e1c20e3c1353b8a6ad0dfbadc6bce77fe14bc26e178cf38d9d6'
pub const wine_client_input = '0d2c95650eb6eff9e7a539d08cb118068b102d812cb505156d3525369dd1ec75'
pub const qemu_splitwx_input = '9025933dcbd195d6fe2fbaaa2dd697173befd8379a10ff1df9040e6a8c941671'

// Alpine's pinned QEMU 9.1.2 Linux-user CLI has no -split-wx option, although
// its TCG implementation supports separate RW/RX aliases. At tcg_init_machine
// this replaces ldr w1,[x19,#0x2c] with mov w1,#1: only the splitwx argument
// changes. Positive one makes region.c refuse failed split mapping instead of
// falling back to an RWX mapping. This is a local-qualification binary patch,
// not a corresponding-source or redistribution assertion.
pub fn splitwx_patch(input string) !string {
	const_offset := 0x85c64
	before := '\x53\x22\x00\x94\xe3\x07\x00\x94\x60\x1a\x40\xf9\x22\x00\x80\x52\x61\x2e\x40\xb9\x00\xac\x6c\xd3\x4d\x8a\x01\x94\xf3\x0b\x40\xf9'
	digest := patch_digest(input)
	defer { unsafe { digest.free() } }
	if digest != qemu_splitwx_input {
		return error('Wine split-WX translator input hash differs')
	}
	start := const_offset - 16
	if start + before.len > input.len || unsafe { tos(input.str + start, before.len) } != before {
		return error('Wine split-WX translator call site differs')
	}
	mut occurrences := 0
	for index in 0 .. input.len - before.len + 1 {
		if input[index] == before[0] && unsafe { tos(input.str + index, before.len) } == before { occurrences++ }
	}
	if occurrences != 1 { return error('Wine split-WX translator call site must occur exactly once') }
	result := input.clone()
	unsafe {
		result.str[const_offset] = 0x21
		result.str[const_offset + 1] = 0x00
		result.str[const_offset + 2] = 0x80
		result.str[const_offset + 3] = 0x52
	}
	return result
}

// Wine 9.17's Linux server and client both chdir(WINEPREFIX) before using
// these strings. Keep UID and prefix device/inode binding, but resolve the
// server directory inside that private prefix instead of shared /tmp.
// Accept only the exact Alpine/Vinix inputs whose source ordering was checked.
pub fn private_server_patch(input string, client bool) !string {
	expected := if client { wine_client_input } else { wine_server_input }
	before := if client { '/tmp/.wine-%u/server-%llx-%llx\x00' } else { '/tmp/.wine-%u\x00' }
	after := if client { '.wine-%u/server-%llx-%llx\x00' } else { '.wine-%u\x00' }
	offset := if client { 408912 } else { 434425 }
	digest := patch_digest(input)
	defer { unsafe { digest.free() } }
	if digest != expected { return error('Wine private-server patch input hash differs') }
	if offset + before.len > input.len || unsafe { tos(input.str + offset, before.len) } != before {
		return error('Wine private-server format site differs')
	}
	mut occurrences := 0
	for index in 0 .. input.len - before.len + 1 {
		if input[index] == before[0] && unsafe { tos(input.str + index, before.len) } == before { occurrences++ }
	}
	if occurrences != 1 { return error('Wine private-server format must occur exactly once') }
	result := input.clone()
	unsafe {
		vmemset(result.str + offset, 0, before.len)
		vmemcpy(result.str + offset, after.str, after.len)
	}
	return result
}
