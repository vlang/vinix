// SPDX-License-Identifier: GPL-2.0-or-later
module main

import boottools
import os

fn main() { exit(boottools.iboot_cli(os.args[1..])) }
