// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import tools.packages.wineadapter

fn refuse(input string, part string) ! {
	wineadapter.shared_user_data_patch(input, part) or { unsafe { err.free() }; return }
	return error('shared-user patch accepted an unpinned input')
}

fn refuse_pe(input string, ntdll bool) ! {
	wineadapter.private_dispatcher_pe_patch(input, ntdll) or { unsafe { err.free() }; return }
	return error('dispatcher PE patch accepted an unpinned input')
}

fn run() ! {
	if os.args.len != 2 { return error('usage: wine-shared-user-patch-check ORIGINAL_DISTRIBUTION_ROOT') }
	mut refusals := 0
	for part, suffix in {'server': '/usr/bin/wineserver', 'client': '/usr/lib/wine/x86_64-unix/ntdll.so', 'boot': '/usr/lib/wine/x86_64-windows/wineboot.exe'} {
		input := os.read_file(os.args[1] + suffix)!
		original := input.clone()
		patched := wineadapter.shared_user_data_patch(input, part)!
		defer { unsafe { input.free(); original.free(); patched.free() } }
		if input != original || input.len != patched.len { return error('input or output extent changed') }
		fields := match part { 'server' { [0x1deac] } 'boot' { [0x62d2] } else { [0x3c3f9, 0x3c410, 0x3c424, 0x5e517, 0x5ce35] } }
		defer { unsafe { fields.free() } }
		for at in 0 .. input.len {
			mut wanted := input[at]
			for field in fields { if at >= field && at < field + 4 { wanted = '\x00\x40\x00\x00'[at - field] } }
			if patched[at] != wanted { return error('unrelated shared-user byte changed') }
		}
		refuse('', part)!; refuse(patched, part)!; refuse(input[..input.len - 1], part)!
		refuse(input, if part == 'boot' { 'server' } else { 'boot' })!; refusals += 4
		for at in [0, fields[0] - 1, fields[0], fields.last() + 4, input.len - 1] {
			changed := input.clone()
			unsafe { changed.str[at] ^= 1 }
			refuse(changed, part)!; refusals++
			unsafe { changed.free() }
		}
	}
	refuse('', 'unknown')!; refusals++
	for ntdll in [false, true]! {
		input := os.read_file(os.args[1] + '/usr/lib/wine/x86_64-windows/' + if ntdll { 'ntdll.dll' } else { 'win32u.dll' })!
		original := input.clone()
		patched := wineadapter.private_dispatcher_pe_patch(input, ntdll)!
		defer { unsafe { input.free(); original.free(); patched.free() } }
		first := if ntdll { 0x54740 } else { 0x96c0 }
		count := if ntdll { 237 } else { 426 }
		if input != original || input.len != patched.len { return error('dispatcher input/output changed extent') }
		for at in 0 .. input.len {
			wanted := if at >= first + 28 && at < first + count * 32 && (at - first - 28) % 32 == 0 { u8(0x40) } else { input[at] }
			if patched[at] != wanted { return error('unrelated dispatcher PE byte changed') }
		}
		refuse_pe('', ntdll)!; refuse_pe(patched, ntdll)!; refuse_pe(input, !ntdll)!; refusals += 3
		for at in [0, first, first + 28, first + (count - 1) * 32 + 28, input.len - 1] {
			changed := input.clone()
			unsafe { changed.str[at] ^= 1 }
			refuse_pe(changed, ntdll)!; refusals++
			unsafe { changed.free() }
		}
	}
	println('WINE SHARED USER PATCH PASS seven 16 KiB fields, 663 dispatcher stubs, preserved WOW64 sentinel, immutable inputs and ' + refusals.str() + ' refusals')
}

fn main() { run() or { eprintln(err); exit(1) } }
