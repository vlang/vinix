// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import asahipolicy
import os

fn main() {
	exit(asahipolicy.execute(os.args[1..]) or {
		eprintln(err)
		if err.code() == 2 { 2 } else { 1 }
	})
}
