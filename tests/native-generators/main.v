// SPDX-License-Identifier: GPL-2.0-or-later
module main

import generators
import os

fn main() {
	if os.args.len < 2 {
		eprintln('missing generator')
		exit(2)
	}
	if os.args[1] == 'check' { exit(generators.check_cli(os.args[2..])) }
	exit(generators.cli(os.args[2..], os.args[1]))
}
