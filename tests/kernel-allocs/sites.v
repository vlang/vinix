// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import symbolcore

fn main() { exit(symbolcore.run_allocations(os.args[1..])) }
