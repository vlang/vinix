// SPDX-License-Identifier: GPL-2.0-or-later
import os
import hosttest
import policyhost
import qemuhost

fn main() {
	guard := policyhost.own_commands()
	defer { guard.close() }
	if os.args.len == 2 && os.args[1] in ['-h', '--help'] {
		println('Usage: prepare-qemu SOURCE TARGET')
		return
	}
	if os.args.len != 3 {
		eprintln('Usage: prepare-qemu SOURCE TARGET')
		exit(2)
	}
	source := hosttest.module_resolve(os.args[1]) or {
		eprintln(err.msg())
		exit(1)
	}
	target := hosttest.module_resolve(os.args[2]) or {
		eprintln(err.msg())
		exit(1)
	}
	qemuhost.prepare(source, target) or {
		eprintln('prepare-qemu: ' + err.msg())
		exit(if err.msg() == 'Host test interrupted' { 130 } else { 1 })
	}
}
