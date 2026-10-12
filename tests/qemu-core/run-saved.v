// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import os
import corevm

fn main() {
	assert os.args.len >= 3
	exit(corevm.cli(os.args[3..], os.args[1] + '/../..', os.args[2]))
}
