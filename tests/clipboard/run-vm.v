// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main
import clipboardvm
import os
fn main() { exit(clipboardvm.cli(os.args[1..])) }
