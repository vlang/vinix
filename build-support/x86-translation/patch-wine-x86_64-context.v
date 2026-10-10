// SPDX-License-Identifier: GPL-2.0-or-later
module main

import winepatch
import os

fn main() { exit(winepatch.run('wine-x86_64-context', os.args[1..])) }
