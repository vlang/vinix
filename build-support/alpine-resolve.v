// SPDX-License-Identifier: GPL-2.0-or-later
module main

import alpinecore
import os

fn main() {
	exit(alpinecore.run(os.args[1..]))
}
