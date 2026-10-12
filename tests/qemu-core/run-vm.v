// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import os
import corevm

fn main() { exit(corevm.cli(os.args[1..], @DIR + '/../..', 'max')) }
