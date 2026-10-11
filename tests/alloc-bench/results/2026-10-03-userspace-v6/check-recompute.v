// SPDX-License-Identifier: BSD-2-Clause
@[has_globals]
module main

import os
import reportfixture

fn main() {
	here := os.dir(@FILE)
	exit(reportfixture.run(os.real_path(here + '/../../../..'), here, '2026-10-03-userspace-v6', os.args[1..]))
}
