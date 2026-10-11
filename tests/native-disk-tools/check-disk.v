// SPDX-License-Identifier: GPL-2.0-or-later
module main

import diskhost
import os
import policyhost

fn main() {
	if os.args.len > 1 && os.args[1] == '-machine' {
		diskhost.check_vm() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len > 1 && os.args[1] == '--child' {
		diskhost.check_child(os.args[2..]) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	guard := policyhost.own_commands()
	defer { guard.close() }
	diskhost.check() or {
		eprintln(err)
		exit(1)
	}
}
