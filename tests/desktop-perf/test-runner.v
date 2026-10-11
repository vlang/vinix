// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import os
import runnerfixture

fn main() { exit(runnerfixture.cli(os.args[1..])) }
