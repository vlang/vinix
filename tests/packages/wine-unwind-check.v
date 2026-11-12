// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import tests.packages.wineunwind
import tools.packages.wineadapter

fn run() ! {
	if os.args.len != 3 { return error('usage: wine-unwind-check ORIGINAL_NTDLL FRESH_OUTPUT') }
	out := os.abs_path(os.args[2])
	if os.exists(out) || os.is_link(out) { return error('output must be fresh') }
	input := os.read_file(os.args[1])!
	patched := wineadapter.private_runtime_patch(input, true)!
	defer { unsafe { input.free(); patched.free() } }
	if wineunwind.check(input, patched)! != 701 { return error('original frame count differs') }
	mut refused := 0
	for offset in [0x38, 0x2ac, 0x2b0, 0x2b8, 0x2c8, 0x160, 0x1a0, 0x1d0, 0x208,
		0x826e8, 0x82a28, 0x82a60, 0x82a70, 0x83004, 0x83054, 0x83060, 0x83080,
		0x83084, 0x8df58, 0x8df5c, 0x8df60, 0x8df64, 0x8df68, 0x8df6a, 0x8df77,
		0x8df80, 0x8df88, 0x8df94, 0x8df98, 0x8df9c, 0x8dfa0, 0x8f584, 0x8f588]! {
		changed := patched.clone()
		unsafe { changed.str[offset] ^= 1 }
		mut rejected := false
		wineunwind.check(input, changed) or { unsafe { err.free() }; rejected = true; 0 }
		unsafe { changed.free() }
		if !rejected { return error('unwind checker accepted corruption at ' + offset.str()) }
		refused++
	}
	os.mkdir_all(out)!
	os.write_file(out + '/ntdll.so', patched)!
	println('WINE UNWIND CHECK PASS 701 unchanged frames/index entries, constant trampoline CFA and ' + refused.str() + ' metadata refusals')
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
