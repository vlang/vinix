// SPDX-License-Identifier: GPL-2.0-or-later
import os
import nativehost

fn main() { exit(nativehost.command('mmap', os.args[1..])) }
