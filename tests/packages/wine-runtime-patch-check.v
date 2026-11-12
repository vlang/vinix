// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import tools.packages.wineadapter
import tests.packages.wineunwind

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
		if input != original || (!client && patched.len != private.len) { return error('input or output size changed') }
		if client { wineunwind.check(input, patched)! }
		instruction := '\x48\x8b\x3d\x35\x4d\x03\x00'
		client_sites := {
			0x3c3f9: '\x00\x40\x00\x00'
			0x3c410: '\x00\x40\x00\x00'
			0x3c424: '\x00\x40\x00\x00'
			0x5e517: '\x00\x40\x00\x00'
			0x5ce35: '\x00\x40\x00\x00'
			0x98: '\xb9'
			0xa0: '\xb9'
			0x5a25f: '\x29'
			0x5a294: '\x29'
			0x5a312: '\x29'
			0x5a6c1: '\x03'
			0x5a368: '\xe9\x33\x78\x00\x00\x90\x90\x90\x90\x90\x90\x90\x90\x90\x90'
			0x61ba0: '\x8b\x84\x24\xac\x00\x00\x00\x4c\x8b\xbc\x24\xb8\x00\x00\x00\x41\x80\x4f\x30\x04\xe9\xbe\x87\xff\xff'
			0x829b0: '\x2c'
		}
		for i in 0 .. private.len {
			if client && wineunwind.metadata_byte(i) { continue }
			mut wanted := if !client && i >= 0x5efe4 && i < 0x5efeb { instruction[i - 0x5efe4] } else { private[i] }
			if !client && i >= 0x1deac && i < 0x1deb0 { wanted = '\x00\x40\x00\x00'[i - 0x1deac] }
			if client {
				for offset, text in client_sites {
					if i >= offset && i < offset + text.len { wanted = text[i - offset] }
				}
			}
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
		if client {
			for offset, _ in client_sites {
				changed := input.clone()
				unsafe { changed.str[offset] ^= 1 }
				refused(changed, client)!
				unsafe { changed.free() }
			}
		}
	}
	println('WINE RUNTIME PATCH PASS exact server/client composition, immutable inputs and 30 refusals')
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
