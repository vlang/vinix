// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main
import gpustage
import os
fn main() { exit(gpustage.cli(os.args[1..])) }
