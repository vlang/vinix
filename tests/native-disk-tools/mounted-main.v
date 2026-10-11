// SPDX-License-Identifier: GPL-2.0-or-later
module main

import diskhost
import os

fn main() { exit(diskhost.command('mounted', os.args[1..])) }
