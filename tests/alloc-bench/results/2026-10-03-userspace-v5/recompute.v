// SPDX-License-Identifier: BSD-2-Clause
@[has_globals]
module main

import os
import reportcore

fn main() {
	here := os.dir(@FILE)
	exit(reportcore.run(os.real_path(here + '/../../../..'), here, '2026-10-03-userspace-v5', os.args[1..]))
}
