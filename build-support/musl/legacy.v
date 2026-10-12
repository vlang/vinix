// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hosttest
import muslnative
import os

fn main() {
	if os.args.len < 2 {
		eprintln('usage: legacy-musl ORIGIN [stage options]')
		exit(2)
	}
	origin := hosttest.module_resolve(os.args[1]) or {
		eprintln(err)
		exit(1)
	}
	exit(muslnative.cli(os.args[2..], os.dir(os.dir(os.dir(origin))), os.dir(origin), true))
}
