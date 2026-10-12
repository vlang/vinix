// SPDX-License-Identifier: GPL-2.0-or-later
module main
import memorytools
import os
fn main() { exit(memorytools.cli(os.args[1..], false)) }
