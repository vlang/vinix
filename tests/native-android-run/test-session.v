// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import androidrunfixtures
import hosttest
import os

fn main() {
	if os.args.len == 2 && os.args[1] == '--mock-vm' {
		androidrunfixtures.mock_vm() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len != 2 { exit(2) }
	androidrunfixtures.session_tests(hosttest.root(), os.args[1]) or {
		eprintln(err)
		exit(1)
	}
}
