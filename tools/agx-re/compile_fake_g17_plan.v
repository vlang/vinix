// SPDX-License-Identifier: GPL-2.0-or-later
module main

import g17plan
import os

fn main() { exit(g17plan.cli('plan', os.args[1..], os.dir(@FILE))) }
