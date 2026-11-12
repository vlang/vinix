// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import tools.packages.wineadapter

fn refuse(input string) ! {
	wineadapter.private_graphics_patch(input) or { unsafe { err.free() }; return }
	return error('private graphics patch accepted an unpinned input')
}

fn run() ! {
	if os.args.len != 2 { return error('usage: wine-graphics-patch-check ORIGINAL_WINEX11_SO') }
	input := os.read_file(os.args[1])!
	original := input.clone()
	patched := wineadapter.private_graphics_patch(input)!
	defer { unsafe { input.free(); original.free(); patched.free() } }
	if input != original || input.len != patched.len { return error('graphics patch mutated input or changed size') }
	after := '\xb8\xff\xff\xff\xff\x90'
	for at in 0 .. input.len {
		wanted := if at >= 0x7e3a && at < 0x7e40 { after[at - 0x7e3a] } else { input[at] }
		if patched[at] != wanted { return error('graphics patch changed an unrelated byte') }
	}
	refuse('')!; refuse(patched)!; refuse(input[..input.len - 1])!
	for at in [0, 0x30, 0x7e2c, 0x7e3a, 0x7e3f, 0x7e40, input.len - 1]! {
		changed := input.clone()
		unsafe { changed.str[at] ^= 1 }
		refuse(changed)!
		unsafe { changed.free() }
	}
	println('WINE GRAPHICS PATCH PASS immutable input, exact six-byte fallback and 10 refusals')
}

fn main() { run() or { eprintln(err); exit(1) } }
