// SPDX-License-Identifier: GPL-2.0-or-later
import os
import nativehost

fn main() { exit(nativehost.command('wake', os.args[1..])) }
