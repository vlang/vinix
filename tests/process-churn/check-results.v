// SPDX-License-Identifier: GPL-2.0-or-later
module main

import churncheck
import os

fn main() { exit(churncheck.run(os.args[1..])) }
