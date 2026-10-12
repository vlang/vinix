// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import kpihost
import os

fn main() {
	if os.args.len >= 2 && os.args[1] == '--audit-mock-compiler' {
		result := kpihost.controlled_audit_compiler(os.args[2..]) or {
			eprintln(err)
			exit(1)
		}
		exit(result)
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len < 2 {
		eprintln('expected native LinuxKPI command')
		exit(2)
	}
	result := kpihost.dispatch(os.real_path(os.dir(@FILE) + '/../..'), os.args[1], os.args[2..]) or {
		eprintln(err)
		exit(if cachecli.cancelled() {
			cachecli.interrupt_status()
		} else if err.code() == 2 {
			2
		} else {
			1
		})
	}
	exit(if cachecli.cancelled() { cachecli.interrupt_status() } else { result })
}
