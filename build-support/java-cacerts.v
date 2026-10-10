// SPDX-License-Identifier: GPL-2.0-or-later
module main

import javacacerts
import os

fn main() {
	exit(javacacerts.run(os.args[1..]))
}
