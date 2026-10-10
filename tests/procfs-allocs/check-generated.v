// SPDX-License-Identifier: GPL-2.0-or-later
module main

import guardcore
import os

fn main() { exit(guardcore.run_scratch(os.args[1..], 'procfs-scratch')) }
