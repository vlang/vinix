// SPDX-License-Identifier: GPL-2.0-or-later
module main

import linkedcheck
import os

fn main() { exit(linkedcheck.command(os.args[1..])) }
