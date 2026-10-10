// SPDX-License-Identifier: GPL-2.0-or-later
module main

import guardcore
import os

fn main() { exit(guardcore.run(os.args[1..], 'pagecache')) }
