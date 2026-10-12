// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import os
import vmfixture

fn main() { exit(vmfixture.cli(os.args[1..])) }
