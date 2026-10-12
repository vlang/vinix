// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import dl
import gamehost
import os
import guestvalidation

type Live = fn () int

fn cases(library_path string) ! {
	library := guestvalidation.open_xlib(library_path)!
	defer { library.close() }
	probe := dl.open_opt(library_path, dl.rtld_lazy)!
	defer { dl.close(probe) }
	live := unsafe { Live(dl.sym_opt(probe, 'vinix_xfixture_live')!) }
	assert sizeof(guestvalidation.WindowAttributes) == 136
	assert guestvalidation.check_xwindow(library, 'absent', 'Target', 0)! == 1 && live() == 0
	for mode in ['legacy', 'utf8', 'nested', 'deep', 'tree-error', 'property-error'] {
		os.setenv('VINIX_XMOCK_MODE', mode, true)
		assert guestvalidation.check_xwindow(library, ':99', 'Target', 0)! == if mode in [
			'deep',
			'tree-error',
			'property-error',
		] {
			1
		} else {
			0
		}
		assert live() == 0
	}
	os.setenv('VINIX_XMOCK_MODE', 'utf8', true)
	for _ in 0 .. 100 {
		assert guestvalidation.check_xwindow(library, ':99', 'Target�', 0)! == 0 && live() == 0
	}
	mut refused := false
	guestvalidation.check_xwindow(library, 'é', 'Target', 0) or { refused = true }
	assert refused && live() == 0
	os.unsetenv('VINIX_XMOCK_MODE')
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len != 3 { exit(2) }
	gamehost.mkdir(os.args[2]) or { panic(err) }
	cases(os.args[1]) or {
		eprintln(err)
		exit(1)
	}
	os.write_file(os.args[2] + '/passed', 'PASS\n') or { panic(err) }
	println('NATIVE X WINDOW / real dynamic ABI, 136-byte attributes, legacy and UTF-8 replacement, hidden windows/depth limit, every name/property/tree/display owner and 100 cycles: PASS')
}
