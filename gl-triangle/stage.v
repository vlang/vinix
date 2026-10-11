// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import glhost
import os

fn main() { exit(glhost.command(os.args[1..], 'stage')) }
