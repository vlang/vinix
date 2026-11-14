// SPDX-License-Identifier: GPL-2.0-or-later
module main

import diskhost
import policyhost
import os

fn run() ! {
	guard := policyhost.own_commands()
	defer { guard.close() }
	if os.args.len == 6 && os.args[1] == 'create' {
		if os.args[5] != '32' { return error('Wine prefix fixture requires a 32 MiB home') }
		if os.exists(os.args[3]) || os.is_link(os.args[3]) { return error('fresh journal image required') }
		diskhost.journal_fixture(os.args[3], os.args[2], os.args[4], 32)!
		return
	}
	if os.args.len == 4 && os.args[1] == 'export' {
		diskhost.export_clean(os.args[2], os.args[3])!
		return
	}
	return error('usage: IMAGE create SEED_DIRECTORY FRESH_IMAGE FORMATTER 32 | export RECOVERED_IMAGE INSPECTION')
}

fn main() { run() or { eprintln(err.msg()); exit(1) } }
