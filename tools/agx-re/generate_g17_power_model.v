// SPDX-License-Identifier: GPL-2.0-or-later
module main

import g17power
import os

fn main() { exit(g17power.cli(os.args[1..], os.dir(@FILE))) }
