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

// Wine 9.17 server/unicode.c uses realpath(server_argv0, NULL) on platforms
// without /proc/self/exe. Use that same discovery path in our private bridge:
// it supplies an absolute, admitted usr/bin/wineserver identity through musl's
// --argv0. This avoids needing procfs visibility under unveil. The exact input
// pin is checked by private_server_patch before any instruction is changed.
pub fn private_runtime_patch(input string, client bool) !string {
	result := private_server_patch(input, client)!
	if client {
		defer { unsafe { result.free() } }
		pe_mapping_patch(input, result)!
		unwound := pe_unwind_patch(input, result)!
		patch_shared_user_sites(input, unwound, 'client') or { unsafe { unwound.free() }; return err }
		return unwound
	}
	before := '\x41\x57\x31\xf6\x48\x8d\x3d\x40\xf9\x00\x00\x41\x56\x41\x55\x41\x54\x55\x53\x48\x83\xec\x28\xc7\x44\x24\x14\x80\x01\x00\x00\xff\x15\xe3\x3c\x03\x00'
	// main stores argv[0] at virtual address 0x93d20; this instruction at
	// 0x5efe4 ends at 0x5efeb. Both executable sections have VA == file offset.
	store := '\x48\x8b\x03\x48\x89\x05\x23\x0c\x09\x00'
	if input.len < 0x5efe0 + before.len
		|| unsafe { tos(input.str + 0x5efe0, before.len) } != before
		|| unsafe { tos(input.str + 0x30f3, store.len) } != store {
		unsafe { result.free() }
		return error('Wine argv0 NLS discovery sites differ')
	}
	after := '\x48\x8b\x3d\x35\x4d\x03\x00'
	unsafe { vmemcpy(result.str + 0x5efe4, after.str, after.len) }
	patch_shared_user_sites(input, result, 'server') or { unsafe { result.free() }; return err }
	return result
}

// The pinned ntdll inlines map_image_view/map_image_into_view. Populate the
// image in RW pages, then let its existing set_vprot calls install the final
// PE section protections. Keep the view's original execute access metadata:
// NtProtectVirtualMemory checks it even after final section protections exist.
fn pe_mapping_patch(input string, result string) ! {
	for offset in [0x5a25d, 0x5a292, 0x5a310]! {
		if unsafe { tos(input.str + offset, 6) } != '\x41\xb8\x2d\x00\x80\x01' {
			return error('Wine initial PE view flags differ')
		}
	}
	hook := '\x8b\x84\x24\xac\x00\x00\x00\x4c\x8b\xbc\x24\xb8\x00\x00\x00'
	header := '\xba\x07\x00\x00\x00\x48\x89\xef\xff\x15\x5a\x85\x02\x00'
	if unsafe { tos(input.str + 0x5a368, hook.len) } != hook
		|| unsafe { tos(input.str + 0x5a6c0, header.len) } != header {
		return error('Wine PE mapping instruction sites differ')
	}
	// Extend only the existing RX segment and .fini section into verified zero
	// padding before the R-only segment at 0x62000. No RWX segment is created.
	for offset in [0x98, 0xa0]! {
		if unsafe { tos(input.str + offset, 8) } != '\x90\xab\x05\x00\x00\x00\x00\x00' {
			return error('Wine PE executable segment bounds differ')
		}
	}
	if unsafe { tos(input.str + 0x829b0, 8) } != '\x03\x00\x00\x00\x00\x00\x00\x00' {
		return error('Wine PE fini section bounds differ')
	}
	for offset in 0x61b90 .. 0x61bb9 {
		if input[offset] != 0 { return error('Wine PE trampoline padding differs') }
	}
	// Replay both overwritten moves, restore EXEC only in view->protect at
	// offset 0x30, and jump back. The OR's flags are dead before the next test.
	cave := '\x8b\x84\x24\xac\x00\x00\x00\x4c\x8b\xbc\x24\xb8\x00\x00\x00\x41\x80\x4f\x30\x04\xe9\xbe\x87\xff\xff'
	jump := '\xe9\x33\x78\x00\x00\x90\x90\x90\x90\x90\x90\x90\x90\x90\x90'
	unsafe {
		for offset in [0x5a25f, 0x5a294, 0x5a312]! { result.str[offset] = 0x29 }
		result.str[0x5a6c1] = 3 // mmap header: PROT_READ | PROT_WRITE
		vmemcpy(result.str + 0x5a368, jump.str, jump.len)
		vmemcpy(result.str + 0x61ba0, cave.str, cave.len)
		for offset in [0x98, 0xa0]! { result.str[offset] = 0xb9 }
		result.str[0x829b0] = 0x2c
	}
}
