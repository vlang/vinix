// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.servicerunner
import desktop.sessioncore
import os

fn main() {
	if os.args.len < 4 || !os.args[1].starts_with('--lease-fd=') || os.args[2] != '--' {
		eprintln('Usage: vinix-service-runner --lease-fd=FD -- /absolute/program [ARGUMENTS...]')
		exit(2)
	}
	fd := int(sessioncore.number(os.args[1]['--lease-fd='.len..], 3, 2147483647)!)
	servicerunner.run(fd, os.args[3..]) or {
		eprintln(err)
		exit(127)
	}
}
