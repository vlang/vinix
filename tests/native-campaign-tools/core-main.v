// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import corevm
import coreboot
import os

fn run() int {
	if os.args.len < 3 {
		eprintln('usage: core-harness ROOT CPU [boot options]')
		return 2
	}
	options := corevm.parse(os.args[3..], os.args[1], os.args[2]) or { eprintln(err); return 2 }
	guard := corevm.own_commands()
	defer { guard.close() }
	mut directory := ''
	defer { if directory != '' { coreboot.remove(directory) or { eprintln(err) } } }
	mut selected := options
	if options.arch == 'aarch64' && !os.is_file(options.root + '/scripts/run-aarch64.sh') && os.is_file(options.root + '/run-aarch64.sh') {
		path, work := coreboot.legacy(options.root, os.getenv('VINIX_CAMPAIGN_PACKAGE_SERVER')) or { eprintln(err); return 1 }
		directory = work
		selected = corevm.Options{...options, arm_runner: path}
	}
	return corevm.run_vm(selected) or {
		eprintln(err.msg())
		if err.msg() == 'Core guest run interrupted' { return err.code() }
		return 1
	}
}

fn main() { exit(run()) }
