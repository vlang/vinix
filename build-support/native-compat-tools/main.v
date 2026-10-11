// SPDX-License-Identifier: GPL-2.0-or-later
module main

import compathost
import os

fn main() {
	if os.args.len < 2 { eprintln('Missing compatibility command'); exit(2) }
	exit(compathost.command(os.args[2..], os.args[1]))
}
