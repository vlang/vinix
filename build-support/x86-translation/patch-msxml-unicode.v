// SPDX-License-Identifier: GPL-2.0-or-later
module main

import winepatch
import os

fn main() { exit(winepatch.run('msxml-unicode', os.args[1..])) }
