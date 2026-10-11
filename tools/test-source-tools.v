// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main
import os
import sourcefixture
fn main() { exit(sourcefixture.cli(os.args[1..])) }
