// SPDX-License-Identifier: GPL-2.0-or-later
module main

import browsertransfer
import os
import time

fn run() ! {
	if os.args.len == 7 && os.args[1] == 'receive' {
		browsertransfer.receive(os.args[2], os.args[3], browsertransfer.expected(os.args[4], os.args[5])!, os.args[6])!
	} else if os.args.len == 5 && os.args[1] == 'send' {
		port := os.args[2]
		if port == '' || port.len > 5 || !port.bytes().all(it >= `0` && it <= `9`)
			|| port.u64() == 0 || port.u64() > 65535 {
			return error('port must be 1..65535')
		}
		browsertransfer.send('/tmp/vinix-browser-probe-results.json', '10.0.2.2:' + port,
			browsertransfer.expected(os.args[3], os.args[4])!, 120 * time.second)!
	} else {
		return error('usage: transfer receive FRESH_DIR PORT SHA BYTES SOURCE_SERIAL | send PORT SHA BYTES')
	}
}

fn main() {
	run() or {
		eprintln(err.msg())
		exit(1)
	}
}
