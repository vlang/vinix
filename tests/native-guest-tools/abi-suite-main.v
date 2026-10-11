// SPDX-License-Identifier: GPL-2.0-or-later
module main

import guesthost
import os

fn main() {
	if os.args.len < 2 {
		eprintln('Missing ABI suite')
		exit(2)
	}
	exit(guesthost.abi_command(os.args[2..], os.args[1]))
}
