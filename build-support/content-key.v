// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import os
import cachecli

fn main() { exit(cachecli.cli('content', os.args[1..], os.real_path(@DIR + '/..'))) }
