// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import tools.packages.wineadapter

fn refuse(input string) ! {
	wineadapter.private_bootstrap_patch(input) or { unsafe { err.free() }; return }
	return error('bootstrap patch accepted an unpinned input')
}

fn run() ! {
	if os.args.len != 2 { return error('usage: wine-bootstrap-patch-check ORIGINAL_WINEBOOT_EXE') }
	input := os.read_file(os.args[1])!
	original := input.clone()
	patched := wineadapter.private_bootstrap_patch(input)!
	defer { unsafe { input.free(); original.free(); patched.free() } }
	if input != original || input.len != patched.len { return error('bootstrap patch mutated input or changed size') }
	after := '\xb8\x01\x00\x00\x00'
	for at in 0 .. input.len {
		wanted := if at >= 0x6864 && at < 0x6869 { after[at - 0x6864] }
			else if at >= 0x62d2 && at < 0x62d6 { '\x00\x40\x00\x00'[at - 0x62d2] } else { input[at] }
		if patched[at] != wanted { return error('bootstrap patch changed unrelated byte') }
	}
	refuse('')!; refuse(patched)!; refuse(input[..input.len - 1])!
	for at in [0, 0x30, 0x6854, 0x6864, 0x6868, 0x6869, input.len - 1]! {
		changed := input.clone()
		unsafe { changed.str[at] ^= 1 }
		refuse(changed)!
		unsafe { changed.free() }
	}
	println('WINE BOOTSTRAP PATCH PASS immutable input, exact literal-name/shared-view composition and 10 refusals')
}

fn main() { run() or { eprintln(err); exit(1) } }
