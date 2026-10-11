// SPDX-License-Identifier: GPL-2.0-or-later
import os
import systemhost
fn main() { exit(systemhost.command('ext2-export', os.args[1..])) }
