// SPDX-License-Identifier: GPL-2.0-only
module main

import vmxcheck
import os

fn main() { exit(vmxcheck.run(os.args[1..])) }
