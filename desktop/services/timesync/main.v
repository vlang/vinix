// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.timesync
import os

fn main() {
	mut server := 'pool.ntp.org'
	for arg in os.args[1..] {
		if arg.starts_with('--time-server=') {
			server = arg['--time-server='.len..]
		} else if arg != '--time-service' {
			eprintln('Usage: vinix-timesync [--time-server=HOST]')
			exit(2)
		}
	}
	timesync.run(server)
}
