// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import os
import officenative

fn main() { exit(officenative.cli(os.args[1..], @FILE)) }
