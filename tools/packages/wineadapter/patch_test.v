// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

import os

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn test_splitwx_exact_instruction_and_refusals() {
	path := os.getenv('VINIX_WINE_PATCH_INPUT')
	defer { unsafe { path.free() } }
	if path == '' { panic('set VINIX_WINE_PATCH_INPUT to the pinned Alpine QEMU ELF') }
	input := os.read_file(path)!
	defer { unsafe { input.free() } }
	patched := splitwx_patch(input)!
	defer { unsafe { patched.free() } }
	assert patched.len == input.len
	mut differences := 0
	for index in 0 .. input.len {
		if input[index] != patched[index] { assert index >= 0x85c64 && index < 0x85c68; differences++ }
	}
	assert differences == 4
	assert unsafe { tos(patched.str + 0x85c64, 4) } == '\x21\x00\x80\x52'
	assert patch_digest(input) == qemu_splitwx_input
	for wrong in ['', 'not an ELF', patched] {
		mut denied := false
		splitwx_patch(wrong) or { unsafe { err.free() }; denied = true; '' }
		assert denied
	}
	// Unchanged size and unrelated code are necessary too: neither one-byte
	// corruption outside the site nor a repeated neighborhood is admitted.
	for offset in [0, 0x85c54, 0x85c64, input.len - 1]! {
		corrupt := input.clone()
		unsafe { corrupt.str[offset] ^= 1 }
		mut denied := false
		splitwx_patch(corrupt) or { unsafe { err.free() }; denied = true; '' }
		unsafe { corrupt.free() }
		assert denied
	}
	duplicate := input + unsafe { tos(input.str + 0x85c54, 32) }
	mut denied := false
	splitwx_patch(duplicate) or { unsafe { err.free() }; denied = true; '' }
	unsafe { duplicate.free() }
	assert denied
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 64 {
		result := splitwx_patch(input)!
		unsafe { result.free() }
		splitwx_patch('untrusted') or { unsafe { err.free() }; '' }
	}
	$if track_heap ? { assert C.vinix_heap_end() == 0 }
}
