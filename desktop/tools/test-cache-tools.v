// SPDX-License-Identifier: GPL-2.0-or-later
module main

import cachefixture
import os

fn main() {
	cachefixture.cli(os.args[1..]) or {
		eprintln(err)
		exit(1)
	}
}
