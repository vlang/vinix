// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import systemhost

fn main() { exit(systemhost.command('ipv6', os.args[1..])) }
