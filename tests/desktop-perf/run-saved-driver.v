// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import os
import savedworkflow

fn main() { exit(savedworkflow.cli(os.args[1..], os.real_path(@DIR + '/../..'))) }
