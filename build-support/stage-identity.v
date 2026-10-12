// SPDX-License-Identifier: GPL-2.0-or-later
module main

import identitycore
import os

fn main() {
	if os.args.len != 2 {
		eprintln('usage: stage-uname.sh STAGING')
		exit(2)
	}
	identitycore.stage(os.args[1], os.dir(@FILE) + '/uname') or {
		eprintln(err.msg())
		exit(1)
	}
}
