// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import tools.packages.wineadapter

fn refused(input string, client bool) ! {
	wineadapter.private_runtime_patch(input, client) or {
		unsafe { err.free() }
		return
	}
	return error('runtime patch accepted an unpinned input')
}

fn run() ! {
	if os.args.len != 2 { return error('usage: wine-runtime-patch-check DISTRIBUTION_ROOT') }
	root := os.args[1]
	for client in [false, true]! {
		path := root + if client { '/usr/lib/wine/x86_64-unix/ntdll.so' } else { '/usr/bin/wineserver' }
		input := os.read_file(path)!
		original := input.clone()
		private := wineadapter.private_server_patch(input, client)!
		patched := wineadapter.private_runtime_patch(input, client)!
		defer { unsafe { path.free(); input.free(); original.free(); private.free(); patched.free() } }
		if input != original || patched.len != private.len { return error('input or output size changed') }
		instruction := '\x48\x8b\x3d\x35\x4d\x03\x00'
		for i in 0 .. patched.len {
			wanted := if !client && i >= 0x5efe4 && i < 0x5efeb { instruction[i - 0x5efe4] } else { private[i] }
			if patched[i] != wanted { return error('unexpected runtime byte change at ' + i.str()) }
		}
		// Reapplication, using the other binary, truncation and corruption of
		// code, argv0 storage, data or unrelated bytes must all refuse.
		refused(patched, client)!
		refused(input, !client)!
		refused('', client)!
		for offset in [0, 0x30f3, 0x5efe4, 0x5efff, input.len - 1]! {
			changed := input.clone()
			defer { unsafe { changed.free() } }
			unsafe { changed.str[offset] ^= 1 }
			refused(changed, client)!
		}
	}
	println('WINE RUNTIME PATCH PASS exact server/client composition, immutable inputs and 16 refusals')
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
